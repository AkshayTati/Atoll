import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(calendar: CalendarService, hud: HUDController, mascot: MascotController) {
        let root = SettingsView(calendar: calendar, hud: hud, mascot: mascot)
        let hosting = NSHostingController(rootView: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Atoll Settings"
        window.contentViewController = hosting
        window.minSize = NSSize(width: 720, height: 520)
        window.setContentSize(NSSize(width: 780, height: 580))
        window.center()

        if let screen = IslandGeometry.resolve()?.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            ))
        }

        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}
