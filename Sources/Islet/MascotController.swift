import AppKit
import Combine
import SwiftUI
import os

final class MascotPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class MascotHostingView<Content: View>: NSHostingView<Content> {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

final class MascotController {
    private let island: IslandController
    private let model = MascotModel()
    private var panel: MascotPanel?
    private var positionTimer: Timer?
    private var behaviorTimer: Timer?
    private var blinkTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private var enabled: Bool
    private var currentAction: MascotAction = .sit
    private var walkPhase: CGFloat = 0
    private var expandedPerch: ExpandedPerch = .header
    private var lastFrame = NSRect.zero
    private var sleeping = false
    private var idleSince: Date?
    private var peekEndWork: DispatchWorkItem?
    private var sitWork: DispatchWorkItem?

    private enum ExpandedPerch {
        case header
        case bottom
    }

    init(island: IslandController) {
        self.island = island
        self.enabled = UserDefaults.standard.object(forKey: "showMascot") as? Bool ?? true
        island.mascotEnabled = enabled
    }

    var isEnabled: Bool { enabled }

    // MARK: - Lifecycle

    func start() {
        guard enabled else { return }
        createPanel()
        startPositionTimer()
        scheduleBehavior()
        scheduleBlink()
        observeMedia()
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        UserDefaults.standard.set(enabled, forKey: "showMascot")
        island.mascotEnabled = enabled

        if enabled {
            if panel == nil { createPanel() }
            panel?.orderFrontRegardless()
            startPositionTimer()
            scheduleBehavior()
            scheduleBlink()
        } else {
            panel?.orderOut(nil)
            behaviorTimer?.invalidate()
            behaviorTimer = nil
            blinkTimer?.invalidate()
            blinkTimer = nil
            peekEndWork?.cancel()
            sitWork?.cancel()
        }
    }

    // MARK: - Panel

    private func createPanel() {
        guard panel == nil else { return }

        let panel = MascotPanel(
            contentRect: NSRect(x: 0, y: 0, width: 34, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        let host = MascotHostingView(rootView: MascotView(model: model))
        host.onClick = { [weak self] in self?.handleClick() }
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)

        self.panel = panel
        updatePosition()
    }

    private func startPositionTimer() {
        guard positionTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
    }

    private func updatePosition() {
        guard enabled, island.hasNotchedScreen, let panel else {
            self.panel?.orderOut(nil)
            return
        }

        let frame = island.currentPanelFrame
        guard frame.width > 0 else {
            panel.orderOut(nil)
            return
        }

        let expanded = island.isExpanded
        let playing = island.mediaService.isPlaying

        if expanded || playing {
            idleSince = nil
            sleeping = false
            if expanded && currentAction == .peek {
                cancelPeek()
            }
        } else if idleSince == nil {
            idleSince = Date()
        } else if Date().timeIntervalSince(idleSince!) > 45 {
            sleeping = true
        }

        let mood: MascotMood
        if expanded {
            mood = .expanded
        } else if playing {
            mood = .playing
        } else if sleeping {
            mood = .sleeping
        } else {
            mood = .idle
        }
        if model.mood != mood {
            model.mood = mood
        }

        if sleeping && currentAction != .peek {
            currentAction = .sleep
        }
        if model.action != currentAction {
            model.action = currentAction
        }

        let size: CGFloat = 34
        let half = size / 2
        var center: CGPoint
        var amplitude: CGFloat

        switch currentAction {
        case .peek:
            center = CGPoint(x: frame.midX, y: frame.minY - 2)
            amplitude = 0

        case .walk:
            if expanded {
                switch expandedPerch {
                case .header:
                    center = CGPoint(x: frame.minX + 92, y: frame.maxY - 17)
                    amplitude = 18
                case .bottom:
                    center = CGPoint(x: frame.maxX - 70, y: frame.minY)
                    amplitude = 26
                }
            } else {
                center = CGPoint(x: frame.maxX - 20, y: frame.minY)
                amplitude = 12
            }

        case .sit, .groom, .sleep:
            if expanded {
                switch expandedPerch {
                case .header:
                    center = CGPoint(x: frame.minX + 92, y: frame.maxY - 17)
                case .bottom:
                    center = CGPoint(x: frame.maxX - 70, y: frame.minY)
                }
                amplitude = 0
            } else {
                center = CGPoint(x: frame.maxX - 14, y: frame.minY + frame.height / 2)
                amplitude = 0
            }
        }

        walkPhase += 0.05
        let offset = sin(walkPhase) * amplitude
        if amplitude > 0.5 {
            let velocity = cos(walkPhase) * amplitude
            if abs(velocity) > 0.2 {
                model.direction = velocity > 0 ? 1 : -1
            }
        }

        let rect = NSRect(
            x: (center.x + offset - half).rounded(),
            y: (center.y - half).rounded(),
            width: size,
            height: size
        )

        if rect != lastFrame {
            panel.setFrame(rect, display: false)
            lastFrame = rect
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Interactions

    private func handleClick() {
        Haptics.select()
        if island.isExpanded {
            hop()
        } else {
            island.expand()
        }
    }

    private func hop() {
        model.hop = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.model.hop = false
        }
    }

    private func observeMedia() {
        island.mediaService.$title
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] title in
                guard !title.isEmpty else { return }
                self?.hop()
            }
            .store(in: &cancellables)
    }

    // MARK: - Behavior

    private func scheduleBehavior() {
        behaviorTimer?.invalidate()
        let timer = Timer(timeInterval: Double.random(in: 3.0...6.0), repeats: false) { [weak self] _ in
            guard let self, self.enabled else { return }
            self.behaviorTick()
            self.scheduleBehavior()
        }
        RunLoop.main.add(timer, forMode: .common)
        behaviorTimer = timer
    }

    private func behaviorTick() {
        if currentAction == .peek {
            return
        }

        if island.isExpanded {
            expandedPerch = expandedPerch == .header ? .bottom : .header
            currentAction = Bool.random() ? .walk : .sit
            hop()
        } else if island.mediaService.isPlaying {
            let roll = Int.random(in: 0..<10)
            if roll < 2 {
                startPeek()
            } else {
                currentAction = Bool.random() ? .walk : .sit
                if Bool.random() { hop() }
                model.look = CGFloat.random(in: -1...1)
            }
        } else if sleeping {
            currentAction = .sleep
        } else {
            model.look = CGFloat.random(in: -1...1)
            let roll = Int.random(in: 0..<10)
            if roll < 3 {
                currentAction = .walk
                scheduleSit(after: 4)
            } else if roll < 6 {
                currentAction = .sit
            } else if roll < 8 {
                startPeek()
            } else {
                currentAction = .groom
                scheduleSit(after: 3)
            }
        }
    }

    private func scheduleSit(after seconds: TimeInterval) {
        sitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.currentAction != .peek,
                  !self.island.isExpanded,
                  !self.island.mediaService.isPlaying else { return }
            self.currentAction = .sit
        }
        sitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Peek-a-boo from the notch

    private func startPeek(force: Bool = false) {
        guard !island.isExpanded else { return }
        guard force || !sleeping else { return }

        sitWork?.cancel()
        peekEndWork?.cancel()

        currentAction = .peek
        model.action = .peek
        model.peekOffset = 9
        model.direction = 1
        model.look = CGFloat.random(in: -1...1)
        Haptics.select()
        Logger.app.info("cat: peek-a-boo")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.currentAction == .peek else { return }
            self.model.peekOffset = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self, self.currentAction == .peek else { return }
            self.model.peekOffset = 9
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.currentAction == .peek else { return }
            self.currentAction = .sit
            self.model.action = .sit
            self.model.peekOffset = 0
        }
        peekEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: work)
    }

    private func cancelPeek() {
        peekEndWork?.cancel()
        peekEndWork = nil
        if currentAction == .peek {
            currentAction = .sit
        }
        model.peekOffset = 0
    }

    /// Manual trigger from the menu, so you can always see the notch peek.
    func forcePeek() {
        sleeping = false
        idleSince = nil

        if island.isExpanded {
            island.collapse()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.startPeek(force: true)
            }
        } else {
            startPeek(force: true)
        }
    }

    // MARK: - Blink

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        let timer = Timer(timeInterval: Double.random(in: 3.0...6.0), repeats: false) { [weak self] _ in
            guard let self, self.enabled else { return }
            self.model.blink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.model.blink = false
            }
            self.scheduleBlink()
        }
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }
}
