import SwiftUI
import AppKit
import FanKit

@main
struct FunFanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = FanEngine.shared

    var body: some Scene {
        MenuBarExtra {
            StatusPopover()
                .environmentObject(engine)
        } label: {
            MenuBarLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)

        Window("Fan Curves", id: "curves") {
            CurveEditorWindow()
                .environmentObject(engine)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        FanEngine.shared.start()

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
}

struct MenuBarLabel: View {
    @ObservedObject var engine: FanEngine

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: engine.settings.controlEnabled ? "fan.fill" : "fan")
            if engine.settings.showTempInMenuBar, let t = engine.sourceTemp {
                Text("\(Int(t.rounded()))°")
            }
            if engine.settings.showRPMInMenuBar, let f = engine.fans.first {
                Text("\(Int(f.actualRPM))")
            }
        }
    }
}
