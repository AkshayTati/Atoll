import AppKit
import Combine
import QuartzCore
import SwiftUI
import os

final class IslandController {
    private let state = IslandState()
    private let media = MediaService()
    private let audio = AudioService()
    private let calendar = CalendarService()
    private let multiMedia = MultiMediaService()
    private var panel: IslandPanel?
    private var geometry: IslandGeometry?

    private var mouseMonitor: Any?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var collapseWorkItem: DispatchWorkItem?
    private var holdUntil: Date?
    private var screenObserver: Any?
    private var wakeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var sourcesTimer: Timer?
    private var isAnimatingPanel = false
    private var animationGeneration = 0
    private var peekWorkItem: DispatchWorkItem?
    private var lastPeekTitle = ""
    private var lastPeekAt = Date.distantPast
    private var started = false

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        media.start()
        audio.start()
        calendar.start()
        multiMedia.start()
        rebuild()
        installMonitors()
        observeMedia()

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

    var audioService: AudioService { audio }
    var mediaService: MediaService { media }
    var isExpanded: Bool { state.expanded }
    var isPeeking: Bool { state.peeking }
    var hasNotchedScreen: Bool { geometry != nil }
    var currentPanelFrame: NSRect { panel?.frame ?? .zero }
    var notchWidth: CGFloat { geometry?.notchWidth ?? 179 }
    var notchHeight: CGFloat { geometry?.notchHeight ?? 32 }
    var onExpand: (() -> Void)?

    var mascotEnabled = true {
        didSet {
            guard let geometry, !state.expanded else { return }
            animatePanel(to: collapsedTarget(for: geometry))
        }
    }

    func stop() {
        stopSourcesTimer()
        media.stop()
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
        peekWorkItem?.cancel()
        peekWorkItem = nil
        state.peeking = false
        onExpand?()
        state.expanded = true
        media.refresh()
        audio.refresh()
        multiMedia.refresh()
        startSourcesTimer()
        Haptics.open()
        animatePanel(to: expandedTarget(for: geometry))
        print("island expanded")
        Logger.app.info("island expanded")
    }

    func collapse() {
        guard let geometry, state.expanded else { return }
        collapseWorkItem?.cancel()
        holdUntil = nil
        state.expanded = false
        peekWorkItem?.cancel()
        peekWorkItem = nil
        state.peeking = false
        stopSourcesTimer()
        Haptics.close()
        animatePanel(to: collapsedTarget(for: geometry))
        print("island collapsed")
        Logger.app.info("island collapsed")
    }

    private func startSourcesTimer() {
        stopSourcesTimer()
        multiMedia.refresh()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.multiMedia.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        sourcesTimer = timer
    }

    private func stopSourcesTimer() {
        sourcesTimer?.invalidate()
        sourcesTimer = nil
    }

    private func collapsedTarget(for geometry: IslandGeometry) -> NSRect {
        if state.peeking {
            return geometry.peekFrame
        }
        return (media.isPlaying || calendar.hasCollapsedEvent || mascotEnabled)
            ? geometry.activeCollapsedFrame
            : geometry.collapsedFrame
    }

    private func observeMedia() {
        media.$title
            .combineLatest(media.$isPlaying)
            .sink { [weak self] _, _ in
                self?.mediaStateChanged()
            }
            .store(in: &cancellables)

        multiMedia.$sources
            .sink { [weak self] _ in
                self?.multiSourcesChanged()
            }
            .store(in: &cancellables)

        calendar.$nextEvent
            .sink { [weak self] _ in
                self?.collapsedContentChanged()
            }
            .store(in: &cancellables)
    }

    private func peek() {
        guard let geometry, !state.expanded else { return }

        // Never start a peek while the island is mid-expand/collapse, or it
        // looks like a wide flash rather than a deliberate side reveal.
        guard !isAnimatingPanel else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, !self.state.expanded else { return }
                self.peek()
            }
            return
        }

        peekWorkItem?.cancel()
        state.peeking = true
        Haptics.select()
        animatePanel(to: geometry.peekFrame)

        let work = DispatchWorkItem { [weak self] in
            self?.endPeek()
        }
        peekWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    private func endPeek() {
        guard state.peeking else { return }
        peekWorkItem?.cancel()
        peekWorkItem = nil
        state.peeking = false
        if let geometry, !state.expanded {
            animatePanel(to: collapsedTarget(for: geometry))
        }
    }

    private func collapsedContentChanged() {
        guard !isAnimatingPanel,
              let geometry,
              !state.expanded,
              let panel else { return }
        let target = collapsedTarget(for: geometry)
        guard panel.frame != target else { return }
        animatePanel(to: target)
    }

    private func multiSourcesChanged() {
        guard !isAnimatingPanel,
              let geometry,
              state.expanded,
              let panel else { return }
        let target = expandedTarget(for: geometry)
        guard panel.frame != target else { return }
        animatePanel(to: target)
    }

    private func expandedTarget(for geometry: IslandGeometry) -> NSRect {
        geometry.expandedFrame(forClientCount: multiMedia.sources.count)
    }

    private func mediaStateChanged() {
        collapsedContentChanged()
    }

    // MARK: - Panel

    private func rebuild() {
        guard let geometry = IslandGeometry.resolve() else {
            print("no notched display found; island hidden")
            Logger.app.info("no notched display found; island hidden")
            panel?.orderOut(nil)
            self.geometry = nil
            stopSourcesTimer()
            return
        }

        self.geometry = geometry
        state.notchHeight = geometry.notchHeight
        state.notchWidth = geometry.notchWidth

        let panel = ensurePanel(with: geometry)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        animationGeneration += 1
        isAnimatingPanel = false
        let target = state.expanded ? expandedTarget(for: geometry) : collapsedTarget(for: geometry)
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
        panel.title = "Atoll"
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

        let host = NSHostingView(
            rootView: IslandRootView(
                state: state,
                media: media,
                audio: audio,
                calendar: calendar,
                multiMedia: multiMedia
            )
        )
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host

        self.panel = panel
        return panel
    }

    private func animatePanel(to frame: NSRect) {
        guard let panel else { return }
        animationGeneration += 1
        let generation = animationGeneration
        isAnimatingPanel = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.0)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            self.isAnimatingPanel = false
            self.settlePanelSize()
        }
    }

    private func settlePanelSize() {
        guard !isAnimatingPanel, let geometry, let panel else { return }
        let target = state.expanded
            ? expandedTarget(for: geometry)
            : collapsedTarget(for: geometry)
        guard panel.frame != target else { return }
        animatePanel(to: target)
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
            let frame = (panel?.frame ?? geometry.expandedFrame).insetBy(dx: -8, dy: -8)
            if !frame.contains(point) {
                scheduleCollapse()
            }
        } else if geometry.activeHotZone.contains(point) {
            expand()
        }
    }

    private func scheduleCollapse() {
        guard state.expanded else { return }
        if let holdUntil, Date() < holdUntil { return }

        collapseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state.expanded else { return }
            let frame = (self.panel?.frame ?? self.geometry?.expandedFrame ?? .zero).insetBy(dx: -8, dy: -8)
            if frame.contains(NSEvent.mouseLocation) {
                return
            }
            self.collapse()
        }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }
}
