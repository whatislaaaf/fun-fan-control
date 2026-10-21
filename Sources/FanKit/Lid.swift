import Foundation
import IOKit

/// Reads the laptop lid (clamshell) state from the power-management root domain.
public enum Lid {
    /// True when the lid is closed, false when open, nil when the machine has no lid sensor
    /// (desktops) or the state could not be read.
    public static func isClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let raw = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let value = raw.takeRetainedValue()
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }
}
