import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var island: IslandController?
    private var hud: HUDController?
    private var mascot: MascotController?
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private var hudItem: NSMenuItem?
    private var mascotItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.info(
            "Islet launching from \(Bundle.main.bundlePath, privacy: .public) login=\(LaunchAtLogin.isEnabled, privacy: .public)"
        )
        print("Islet launching from \(Bundle.main.bundlePath)")

        let island = IslandController()
        island.start()
        self.island = island

        let hud = HUDController(
            audio: island.audioService,
            isIslandExpanded: { [weak island] in island?.isExpanded ?? false }
        )
        hud.start()
        self.hud = hud
        island.onExpand = { [weak hud] in hud?.hide() }

        let mascot = MascotController(island: island)
        mascot.start()
        self.mascot = mascot

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

        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launch)
        launchAtLoginItem = launch

        let hudItem = NSMenuItem(title: "Enable HUD Control…", action: #selector(enableHUD), keyEquivalent: "")
        hudItem.target = self
        hudItem.state = hud?.isEnabled == true ? .on : .off
        menu.addItem(hudItem)
        self.hudItem = hudItem

        let testHUD = NSMenuItem(title: "Test HUD Line", action: #selector(testHUDLine), keyEquivalent: "")
        testHUD.target = self
        menu.addItem(testHUD)

        let mascotItem = NSMenuItem(title: "Show Cat", action: #selector(toggleMascot), keyEquivalent: "")
        mascotItem.target = self
        mascotItem.state = mascot?.isEnabled == true ? .on : .off
        menu.addItem(mascotItem)
        self.mascotItem = mascotItem

        let peekItem = NSMenuItem(title: "Cat: Peek-a-Boo", action: #selector(peekCat), keyEquivalent: "")
        peekItem.target = self
        menu.addItem(peekItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Islet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
        hudItem?.state = hud?.isEnabled == true ? .on : .off
        mascotItem?.state = mascot?.isEnabled == true ? .on : .off
    }

    @objc private func toggleIsland() {
        island?.toggleExpanded()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func enableHUD() {
        hud?.requestAccess()
    }

    @objc private func testHUDLine() {
        hud?.showTest()
    }

    @objc private func toggleMascot() {
        guard let mascot else { return }
        mascot.setEnabled(!mascot.isEnabled)
        mascotItem?.state = mascot.isEnabled ? .on : .off
    }

    @objc private func peekCat() {
        mascot?.forcePeek()
    }
}
