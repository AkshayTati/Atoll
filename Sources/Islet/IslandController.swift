import AppKit
import QuartzCore
import SwiftUI
import os

final class IslandController {
    private let state = IslandState()
    private let media = MediaService()
    private let audio = AudioService()
    private var panel: IslandPanel?
    private var geometry: IslandGeometry?

    private var mouseMonitor: Any?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var collapseWorkItem: DispatchWorkItem?
    private var holdUntil: Date?
    private var screenObserver: Any?
    private var wakeObserver: Any?
    private var started = false

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        media.start()
        audio.start()
        rebuild()
        installMonitors()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        }
    }

    // MARK: - Public controls

    func toggleExpanded() {
        if state.expanded {
            collapse()
        } else {
            expand()
        }
    }

    func expand(temporarilyFor seconds: TimeInterval? = nil) {
        guard let geometry else { return }
        collapseWorkItem?.cancel()

        if let seconds {
            let deadline = Date().addingTimeInterval(seconds)
            holdUntil = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self,
                      self.state.expanded,
                      let hold = self.holdUntil,
                      Date() >= hold else { return }
                if let frame = self.panel?.frame, frame.contains(NSEvent.mouseLocation) {
                    return
                }
                self.collapse()
            }
        }

        guard !state.expanded else { return }
        state.expanded = true
        media.refresh()
        audio.refresh()
        animatePanel(to: geometry.expandedFrame)
        print("island expanded")
        Logger.app.info("island expanded")
    }

    func collapse() {
        guard let geometry, state.expanded else { return }
        collapseWorkItem?.cancel()
        holdUntil = nil
        state.expanded = false
        animatePanel(to: geometry.collapsedFrame)
        print("island collapsed")
        Logger.app.info("island collapsed")
    }

    // MARK: - Panel

    private func rebuild() {
        guard let geometry = IslandGeometry.resolve() else {
            print("no notched display found; island hidden")
            Logger.app.info("no notched display found; island hidden")
            panel?.orderOut(nil)
            self.geometry = nil
            return
        }

        self.geometry = geometry
        state.notchHeight = geometry.notchHeight

        let panel = ensurePanel(with: geometry)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        let target = state.expanded ? geometry.expandedFrame : geometry.collapsedFrame
        panel.setFrame(target, display: true)
        panel.orderFrontRegardless()

        print(
            "panel: frame=\(NSStringFromRect(panel.frame)) "
                + "level=\(panel.level.rawValue) "
                + "collapsed=\(NSStringFromRect(geometry.collapsedFrame)) "
                + "expanded=\(NSStringFromRect(geometry.expandedFrame)) "
                + "screen=\(NSStringFromRect(geometry.screen.frame)) "
                + "notch=\(geometry.notchWidth)x\(geometry.notchHeight)"
        )
        Logger.app.info(
            "panel collapsed=\(NSStringFromRect(geometry.collapsedFrame), privacy: .public) expanded=\(NSStringFromRect(geometry.expandedFrame), privacy: .public) notch=\(geometry.notchWidth, privacy: .public)x\(geometry.notchHeight, privacy: .public)"
        )
    }

    private func ensurePanel(with geometry: IslandGeometry) -> IslandPanel {
        if let panel {
            return panel
        }

        let panel = IslandPanel(
            contentRect: geometry.collapsedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Islet"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false

        let host = NSHostingView(rootView: IslandRootView(state: state, media: media, audio: audio))
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host

        self.panel = panel
        return panel
    }

    private func animatePanel(to frame: NSRect) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - Hover / clicks

    private func installMonitors() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.handleMouseMoved()
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.state.expanded else { return }
            let point = NSEvent.mouseLocation
            if let frame = self.geometry?.expandedFrame,
               !frame.insetBy(dx: -8, dy: -8).contains(point) {
                self.collapse()
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if !self.state.expanded {
                self.expand()
            }
            return event
        }
    }

    private func handleMouseMoved() {
        guard let geometry else { return }
        let point = NSEvent.mouseLocation

        if state.expanded {
            let frame = geometry.expandedFrame.insetBy(dx: -8, dy: -8)
            if !frame.contains(point) {
                scheduleCollapse()
            }
        } else if geometry.hotZone.contains(point) {
            expand()
        }
    }

    private func scheduleCollapse() {
        guard state.expanded else { return }
        if let holdUntil, Date() < holdUntil { return }

        collapseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state.expanded else { return }
            if let frame = self.geometry?.expandedFrame.insetBy(dx: -8, dy: -8),
               frame.contains(NSEvent.mouseLocation) {
                return
            }
            self.collapse()
        }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }
}
