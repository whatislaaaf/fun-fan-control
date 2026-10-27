import AppKit
import SwiftUI

/// The "Fan Curves" window, hosted in AppKit so the dropdown can open it without a SwiftUI scene.
final class CurvesWindowController: NSWindowController {
    static let shared = CurvesWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Fan Curves"
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 920, height: 600)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("FanCurvesWindow")
        window.contentView = NSHostingView(rootView: CurveEditorWindow().environmentObject(FanEngine.shared))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
