import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.info("Islet launching")
        print("Islet launching")

        let island = IslandController()
        island.start()
        self.island = island

        installStatusItem()

        // Show off once on launch so there is something visible immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.island?.expand(temporarilyFor: 4.0)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        island?.stop()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Islet")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Toggle Island", action: #selector(toggleIsland), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Islet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleIsland() {
        island?.toggleExpanded()
    }
}
