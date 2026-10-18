import Foundation

public enum HelperError: Error, CustomStringConvertible {
    case notFound(String)
    case notInstalled
    case failed(Int32, String)
    case installFailed(String)

    public var description: String {
        switch self {
        case .notFound(let p): return "Helper not found at \(p)"
        case .notInstalled: return "Helper is not installed (needs setuid root)"
        case .failed(let code, let out): return "Helper failed (\(code)): \(out.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .installFailed(let out): return "Install failed: \(out.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

/// Talks to the `ffc-helper` binary that sits next to the app executable.
/// Writing to the SMC needs root, so the helper is installed once as a setuid-root binary.
public enum HelperClient {
    public static let helperName = "ffc-helper"

    public static var helperURL: URL {
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        return exe.deletingLastPathComponent().appendingPathComponent(helperName)
    }

    public static func exists() -> Bool {
        FileManager.default.isExecutableFile(atPath: helperURL.path)
    }

    /// True when the helper is owned by root and has the setuid bit.
    public static func isInstalled() -> Bool {
        var st = stat()
        guard stat(helperURL.path, &st) == 0 else { return false }
        return st.st_uid == 0 && (st.st_mode & S_ISUID) != 0
    }

    /// Prompts for an administrator password and marks the helper setuid root.
    public static func install() throws {
        let path = helperURL.path
        guard exists() else { throw HelperError.notFound(path) }
        let shell = "chown root:wheel '\(path)' && chmod 4755 '\(path)'"
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let (status, out) = run("/usr/bin/osascript", ["-e", script])
        if status != 0 { throw HelperError.installFailed(out) }
        guard isInstalled() else { throw HelperError.installFailed("setuid bit missing after install. \(out)") }
    }

    /// Forces the given fans to the given RPM targets.
    @discardableResult
    public static func setFans(_ targets: [(fan: Int, rpm: Double)]) throws -> String {
        guard isInstalled() else { throw HelperError.notInstalled }
        var args = ["set"]
        for t in targets { args += [String(t.fan), String(Int(t.rpm.rounded()))] }
        let (status, out) = run(helperURL.path, args)
        if status != 0 { throw HelperError.failed(status, out) }
        return out
    }

    /// Returns every fan to macOS automatic control.
    @discardableResult
    public static func setAuto() throws -> String {
        guard isInstalled() else { throw HelperError.notInstalled }
        let (status, out) = run(helperURL.path, ["auto"])
        if status != 0 { throw HelperError.failed(status, out) }
        return out
    }

    static func run(_ path: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
