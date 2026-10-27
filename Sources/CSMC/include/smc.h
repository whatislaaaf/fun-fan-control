#ifndef CSMC_SMC_H
#define CSMC_SMC_H

#include <stdint.h>
#include <IOKit/IOKitLib.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;      // four-char code, e.g. 'flt ' 'sp78' 'fpe2' 'ui8 '
    uint8_t  dataAttributes;
} smc_key_info_t;

/// Opens a connection to the AppleSMC service. Returns 0 on success, kern_return_t otherwise.
int smc_open(io_connect_t *conn);
void smc_close(io_connect_t conn);

/// Number of keys the SMC exposes (reads "#KEY").
int smc_key_count(io_connect_t conn, uint32_t *count);
/// Key name at a given index; `key` receives 4 chars plus NUL.
int smc_key_at_index(io_connect_t conn, uint32_t index, char key[5]);
/// Type/size information for a key.
int smc_key_info(io_connect_t conn, const char *key, smc_key_info_t *info);
/// Reads up to 32 raw bytes for a key. `info` may be NULL.
int smc_read(io_connect_t conn, const char *key, smc_key_info_t *info, uint8_t out[32]);
/// Writes `size` raw bytes to a key. Requires root.
int smc_write(io_connect_t conn, const char *key, const uint8_t *bytes, uint32_t size);

#ifdef __cplusplus
}
#endif

#endif
