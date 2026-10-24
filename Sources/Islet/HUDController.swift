import AppKit
import ApplicationServices
import SwiftUI
import os

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class HUDController {
    private let audio: AudioService
    private let brightness = BrightnessService()
    private let state = HUDState()
    private let isIslandExpanded: () -> Bool

    private var panel: HUDPanel?
    private var tap: MediaKeyTap?
    private var hideWorkItem: DispatchWorkItem?

    init(audio: AudioService, isIslandExpanded: @escaping () -> Bool) {
        self.audio = audio
        self.isIslandExpanded = isIslandExpanded
    }

    var isEnabled: Bool {
        tap != nil
    }

    // MARK: - Lifecycle

    func start() {
        brightness.start()
        if AXIsProcessTrusted() {
            installTap()
        } else {
            Logger.app.info("hud: waiting for Accessibility permission")
        }
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
                self?.installTapIfPossible()
            }
        }
    }

    func showTest() {
        show(kind: .volume, value: 0.62, muted: false)
    }

    private func installTapIfPossible() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        installTap()
    }

    private func installTap() {
        let tap = MediaKeyTap()
        tap.shouldHandle = { [weak self] in
            guard let self else { return false }
            return self.tap != nil && !self.isIslandExpanded()
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
            Logger.app.info("hud: key tap installed")
        } else {
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
        guard !isIslandExpanded() else { return }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
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
