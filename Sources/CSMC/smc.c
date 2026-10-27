#include "smc.h"
#include <string.h>
#include <IOKit/IOKitLib.h>

#define KERNEL_INDEX_SMC      2
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6
#define SMC_CMD_READ_INDEX    8
#define SMC_CMD_READ_KEYINFO  9

typedef struct {
    unsigned char  major;
    unsigned char  minor;
    unsigned char  build;
    unsigned char  reserved[1];
    unsigned short release;
} SMCKeyData_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char     dataAttributes;
} SMCKeyData_keyInfo_t;

typedef struct {
    uint32_t                key;
    SMCKeyData_vers_t       vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t    keyInfo;
    char                    result;
    char                    status;
    char                    data8;
    uint32_t                data32;
    unsigned char           bytes[32];
} SMCKeyData_t;

static uint32_t key_to_u32(const char *key) {
    return ((uint32_t)(unsigned char)key[0] << 24) |
           ((uint32_t)(unsigned char)key[1] << 16) |
           ((uint32_t)(unsigned char)key[2] << 8)  |
           ((uint32_t)(unsigned char)key[3]);
}

static void u32_to_key(uint32_t v, char key[5]) {
    key[0] = (char)(v >> 24);
    key[1] = (char)(v >> 16);
    key[2] = (char)(v >> 8);
    key[3] = (char)(v);
    key[4] = 0;
}

int smc_open(io_connect_t *conn) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) return -1;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, conn);
    IOObjectRelease(service);
    return kr;
}

void smc_close(io_connect_t conn) {
    IOServiceClose(conn);
}

static int smc_call(io_connect_t conn, SMCKeyData_t *in, SMCKeyData_t *out) {
    size_t outSize = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, in, sizeof(SMCKeyData_t), out, &outSize);
}

int smc_key_info(io_connect_t conn, const char *key, smc_key_info_t *info) {
    SMCKeyData_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key_to_u32(key);
    in.data8 = SMC_CMD_READ_KEYINFO;
    int kr = smc_call(conn, &in, &out);
    if (kr != 0) return kr;
    if (out.result != 0) return 0x100 + (unsigned char)out.result;
    info->dataSize = out.keyInfo.dataSize;
    info->dataType = out.keyInfo.dataType;
    info->dataAttributes = (uint8_t)out.keyInfo.dataAttributes;
    return 0;
}

int smc_read(io_connect_t conn, const char *key, smc_key_info_t *info, uint8_t outBytes[32]) {
    smc_key_info_t local;
    int kr = smc_key_info(conn, key, &local);
    if (kr != 0) return kr;
    if (info) *info = local;

    SMCKeyData_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key_to_u32(key);
    in.keyInfo.dataSize = local.dataSize;
    in.keyInfo.dataType = local.dataType;
    in.data8 = SMC_CMD_READ_BYTES;
    kr = smc_call(conn, &in, &out);
    if (kr != 0) return kr;
    if (out.result != 0) return 0x100 + (unsigned char)out.result;
    memcpy(outBytes, out.bytes, 32);
    return 0;
}

int smc_write(io_connect_t conn, const char *key, const uint8_t *bytes, uint32_t size) {
    if (size > 32) return -2;
    smc_key_info_t local;
    int kr = smc_key_info(conn, key, &local);
    if (kr != 0) return kr;

    SMCKeyData_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key_to_u32(key);
    in.keyInfo.dataSize = size;
    in.keyInfo.dataType = local.dataType;
    in.data8 = SMC_CMD_WRITE_BYTES;
    memcpy(in.bytes, bytes, size);
    kr = smc_call(conn, &in, &out);
    if (kr != 0) return kr;
    if (out.result != 0) return 0x100 + (unsigned char)out.result;
    return 0;
}

int smc_key_count(io_connect_t conn, uint32_t *count) {
    uint8_t bytes[32];
    smc_key_info_t info;
    int kr = smc_read(conn, "#KEY", &info, bytes);
    if (kr != 0) return kr;
    *count = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | bytes[3];
    return 0;
}

int smc_key_at_index(io_connect_t conn, uint32_t index, char key[5]) {
    SMCKeyData_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.data8 = SMC_CMD_READ_INDEX;
    in.data32 = index;
    int kr = smc_call(conn, &in, &out);
    if (kr != 0) return kr;
    if (out.result != 0) return 0x100 + (unsigned char)out.result;
    u32_to_key(out.key, key);
    return 0;
}
