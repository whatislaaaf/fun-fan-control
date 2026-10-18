import AppKit
import SwiftUI
import Combine
import FanKit

/// Owns the menu bar item and the dropdown panel.
final class StatusBarController: NSObject {
    private let engine: FanEngine
    private let statusItem: NSStatusItem
    private let panel: MenuBarPanel
    private var cancellables: Set<AnyCancellable> = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    /// When the panel was last closed. A click on the status item first makes the panel resign key
    /// (closing it) and then fires the button action; without this the action would reopen it.
    private var lastClose = Date.distantPast

    init(engine: FanEngine) {
        self.engine = engine
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = MenuBarPanel(rootView: StatusPopover().environmentObject(engine))
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        }
        updateButton()

        engine.objectWillChange
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)

        panel.onClose = { [weak self] in self?.panelDidClose() }
    }

    // MARK: Menu bar button

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let name = engine.controlling ? "fan.fill" : "fan"
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Fun Fan Control")?.withSymbolConfiguration(config)

        var parts: [String] = []
        if engine.settings.showTempInMenuBar, let t = engine.sourceTemp { parts.append("\(Int(t.rounded()))°") }
        if engine.settings.showRPMInMenuBar, let f = engine.fans.first { parts.append(f.actualRPM < 1 ? "off" : "\(Int(f.actualRPM))") }
        button.title = parts.isEmpty ? "" : " " + parts.joined(separator: " ")
        button.toolTip = engine.fans.map { "\($0.name): \($0.actualRPM < 1 ? "off" : "\(Int($0.actualRPM)) RPM")" }.joined(separator: "\n")
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Curves & Settings…", action: #selector(openCurves), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Fun Fan Control", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openCurves() {
        CurvesWindowController.shared.show()
    }

    // MARK: Panel

    func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else if Date().timeIntervalSince(lastClose) > 0.4 {
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.present(below: buttonRect, on: buttonWindow.screen ?? NSScreen.main)
        button.highlight(true)

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.closePanel(); return nil }   // Escape
                return event
            }
            if event.window !== self.panel {
                // A click on the status item itself is handled by the button action.
                if event.window === buttonWindow { return event }
                self.closePanel()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    func closePanel() {
        panel.dismiss()
    }

    private func panelDidClose() {
        lastClose = Date()
        statusItem.button?.highlight(false)
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }
}

/// Borderless, non-activating panel with a rounded vibrancy background that hugs its SwiftUI content.
/// The SwiftUI view reports its ideal size and the panel resizes to it, keeping its top edge under the menu bar.
final class MenuBarPanel: NSPanel {
    var onClose: (() -> Void)?
    private var hostingView: NSHostingView<AnyView>!
    private var contentSize = CGSize(width: 330, height: 200)
    static let cornerRadius: CGFloat = 16

    init<V: View>(rootView: V) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 330, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true

        let root = PanelRoot(onSize: { [weak self] size in self?.contentDidResize(size) }) { rootView }
        hostingView = NSHostingView(rootView: AnyView(root))
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = effect.bounds
        effect.addSubview(hostingView)
        contentView = effect

        // Hairline border on top, matching the cards.
        let border = NSView()
        border.wantsLayer = true
        border.layer?.cornerRadius = Self.cornerRadius
        border.layer?.cornerCurve = .continuous
        border.layer?.borderWidth = 1
        border.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        border.autoresizingMask = [.width, .height]
        border.frame = effect.bounds
        effect.addSubview(border, positioned: .above, relativeTo: hostingView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var anchorTop: CGFloat = 0
    private var anchorMidX: CGFloat = 0
    private var screenFrame: NSRect = .zero

    func present(below buttonRect: NSRect, on screen: NSScreen?) {
        screenFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        anchorMidX = buttonRect.midX
        anchorTop = buttonRect.minY - 2    // flush under the menu bar
        hostingView.layoutSubtreeIfNeeded()
        fitToContent()
        makeKeyAndOrderFront(nil)
    }

    private func contentDidResize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        contentSize = size
        if isVisible || anchorTop != 0 { fitToContent() }
    }

    private func fitToContent() {
        let size = contentSize
        var x = anchorMidX - size.width / 2
        x = min(max(x, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        let frame = NSRect(x: x.rounded(), y: (anchorTop - size.height).rounded(), width: size.width.rounded(), height: size.height.rounded())
        if frame != self.frame {
            setFrame(frame, display: true)
            invalidateShadow()
        }
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
        onClose?()
    }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }
}

/// Lets the SwiftUI content take its ideal height, pins it to the top of the window, and reports its size.
private struct PanelRoot<Content: View>: View {
    let onSize: (CGSize) -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
