import AppKit
import FanKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        FanEngine.shared.start()
        statusBar = StatusBarController(engine: FanEngine.shared)

        // Give the fans back to macOS if we are killed with SIGTERM / SIGINT.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                FanEngine.shared.shutdown()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        FanEngine.shared.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBar?.togglePanel()
        return false
    }
}
