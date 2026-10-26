import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AtollSettings.shared

    private var island: IslandController?
    private var hud: HUDController?
    private var mascot: MascotController?
    private var settingsWindow: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var mascotItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.info(
            "Atoll launching from \(Bundle.main.bundlePath, privacy: .public) login=\(LaunchAtLogin.isEnabled, privacy: .public)"
        )
        print("Atoll launching from \(Bundle.main.bundlePath)")

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

        ShortcutManager.shared.onToggleCat = { [weak self] in
            self?.toggleMascot()
        }
        ShortcutManager.shared.start()

        installStatusItem()

        if settings.showIntroOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.island?.expand(temporarilyFor: 4.0)
            }
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
            button.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Atoll")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Toggle Island", action: #selector(toggleIsland), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let mascotItem = NSMenuItem(title: "Show Cat", action: #selector(toggleMascot), keyEquivalent: "")
        mascotItem.target = self
        mascotItem.state = settings.catEnabled ? .on : .off
        menu.addItem(mascotItem)
        self.mascotItem = mascotItem

        let peekItem = NSMenuItem(title: "Cat: Peek-a-Boo", action: #selector(peekCat), keyEquivalent: "")
        peekItem.target = self
        menu.addItem(peekItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Atoll", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        mascotItem?.state = settings.catEnabled ? .on : .off
    }

    @objc private func toggleIsland() {
        island?.toggleExpanded()
    }

    @objc private func toggleMascot() {
        settings.catEnabled.toggle()
        mascotItem?.state = settings.catEnabled ? .on : .off
    }

    @objc private func peekCat() {
        mascot?.forcePeek()
    }

    @objc private func openSettings() {
        guard let island, let hud, let mascot else { return }

        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                calendar: island.calendarService,
                hud: hud,
                mascot: mascot
            )
        }
        settingsWindow?.show()
    }
}
