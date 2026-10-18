import AppKit

// AppKit lifecycle: the menu bar item and its dropdown are custom AppKit windows so the
// panel can sit flush under the icon with rounded corners, which SwiftUI's MenuBarExtra
// does not allow.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
