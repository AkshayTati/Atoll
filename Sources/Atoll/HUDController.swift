import AppKit
import ApplicationServices
import Combine
import SwiftUI
import os

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class HUDController: ObservableObject {
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var tapInstalled = false

    private let audio: AudioService
    private let brightness = BrightnessService()
    private let state = HUDState()
    private let isIslandExpanded: () -> Bool
    private let settings = AtollSettings.shared

    private var panel: HUDPanel?
    private var tap: MediaKeyTap?
    private var hideWorkItem: DispatchWorkItem?
    private var permissionTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var lastInstallAttempt = Date.distantPast
    private var settingsCancellables = Set<AnyCancellable>()

    init(audio: AudioService, isIslandExpanded: @escaping () -> Bool) {
        self.audio = audio
        self.isIslandExpanded = isIslandExpanded
    }

    var isEnabled: Bool {
        tapInstalled
    }

    // MARK: - Lifecycle

    func start() {
        brightness.start()
        refreshPermissions()
        startPermissionTimer()

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPermissions()
        }

        settings.$hudEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.applyEnabled(enabled)
            }
            .store(in: &settingsCancellables)
    }

    private func applyEnabled(_ enabled: Bool) {
        if enabled {
            refreshPermissions()
        } else {
            uninstallTap()
            hide()
        }
    }

    func refreshPermissions() {
        let ax = AXIsProcessTrusted()

        if ax != accessibilityTrusted {
            accessibilityTrusted = ax
            Logger.app.info("hud: accessibility trusted=\(ax, privacy: .public)")
        }

        guard settings.hudEnabled else {
            uninstallTap()
            return
        }

        if ax {
            installTapIfPossible()
        } else {
            uninstallTap()
        }
    }

    private func startPermissionTimer() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func uninstallTap() {
        tap?.stop()
        tap = nil
        tapInstalled = false
    }

    func requestAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        for delay in [1.0, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshPermissions()
            }
        }
    }

    func resetPermissions() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.akshay.atoll"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        try? process.run()
        process.waitUntilExit()
        refreshPermissions()
        requestAccess()
    }

    func restartApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func showTest() {
        show(kind: .volume, value: 0.62, muted: false)
    }

    private func installTapIfPossible() {
        guard tap == nil,
              settings.hudEnabled,
              accessibilityTrusted,
              Date().timeIntervalSince(lastInstallAttempt) > 5 else { return }
        lastInstallAttempt = Date()
        installTap()
    }

    deinit {
        permissionTimer?.invalidate()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    private func installTap() {
        let tap = MediaKeyTap()
        tap.shouldHandle = { [weak self] in
            guard let self else { return false }
            return self.tap != nil && self.settings.hudEnabled && !self.isIslandExpanded()
        }
        tap.brightnessAvailable = { [weak self] in
            self?.brightness.available ?? false
        }
        tap.onVolumeUp = { [weak self] fine in
            self?.adjustVolume(fine ? 1.0 / 64.0 : 1.0 / 16.0)
        }
        tap.onVolumeDown = { [weak self] fine in
            self?.adjustVolume(fine ? -1.0 / 64.0 : -1.0 / 16.0)
        }
        tap.onMute = { [weak self] in
            self?.toggleMute()
        }
        tap.onBrightnessUp = { [weak self] fine in
            self?.adjustBrightness(fine ? 1.0 / 64.0 : 1.0 / 16.0)
        }
        tap.onBrightnessDown = { [weak self] fine in
            self?.adjustBrightness(fine ? -1.0 / 64.0 : -1.0 / 16.0)
        }

        if tap.start() {
            self.tap = tap
            tapInstalled = true
            Logger.app.info("hud: key tap installed")
        } else {
            tapInstalled = false
            Logger.app.info("hud: key tap failed")
        }
    }

    // MARK: - Actions

    private func adjustVolume(_ delta: Double) {
        let value = audio.adjustVolume(by: delta)
        show(kind: .volume, value: value, muted: audio.isMuted)
    }

    private func toggleMute() {
        let muted = audio.toggleMute()
        show(kind: .volume, value: audio.volume, muted: muted)
    }

    private func adjustBrightness(_ delta: Double) {
        guard brightness.available else { return }
        let value = brightness.adjust(by: delta)
        show(kind: .brightness, value: value, muted: false)
    }

    // MARK: - HUD panel

    private func show(kind: HUDKind, value: Double, muted: Bool) {
        guard settings.hudEnabled, !isIslandExpanded() else { return }

        switch kind {
        case .volume:
            if muted {
                guard settings.hudShowMute else { return }
            } else {
                guard settings.hudShowVolume else { return }
            }
        case .brightness:
            guard settings.hudShowBrightness else { return }
        }

        guard let panel = ensurePanel() else { return }

        state.kind = kind
        state.value = value
        state.muted = muted
        state.visible = true

        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.4, settings.hudDuration),
            execute: work
        )
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        state.visible = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, !self.state.visible else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func ensurePanel() -> HUDPanel? {
        guard let geometry = IslandGeometry.resolve() else { return nil }

        let size = NSSize(width: 200, height: 20)
        let notchBottom = geometry.screen.frame.maxY - geometry.notchHeight
        let frame = NSRect(
            x: (geometry.collapsedFrame.midX - size.width / 2).rounded(),
            y: notchBottom - 11,
            width: size.width,
            height: size.height
        )

        if let panel {
            panel.setFrame(frame, display: false)
            return panel
        }

        let panel = HUDPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        let host = NSHostingView(rootView: HUDView(state: state))
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host

        self.panel = panel
        return panel
    }
}
