import AppKit
import Combine
import SwiftUI

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
    private var walkPhase: CGFloat = 0
    private var expandedPerch: ExpandedPerch = .header
    private var lastFrame = NSRect.zero
    private var sleeping = false
    private var idleSince: Date?

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
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
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
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
    }

    private func updatePosition() {
        guard enabled, island.hasNotchedScreen, let panel else {
            panel?.orderOut(nil)
            return
        }

        let frame = island.currentPanelFrame
        guard frame.width > 0 else {
            panel.orderOut(nil)
            return
        }

        let expanded = island.isExpanded
        let playing = island.mediaService.isPlaying
        let peeking = island.isPeeking

        if expanded || playing {
            idleSince = nil
            sleeping = false
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

        let size: CGFloat = 34
        let half = size / 2
        var center: CGPoint
        var amplitude: CGFloat

        if expanded {
            switch expandedPerch {
            case .header:
                center = CGPoint(x: frame.minX + 92, y: frame.maxY - 17)
                amplitude = 18
            case .bottom:
                center = CGPoint(x: frame.maxX - 70, y: frame.minY)
                amplitude = 26
            }
        } else if peeking {
            center = CGPoint(x: frame.minX + 18, y: frame.minY)
            amplitude = 4
        } else if playing {
            center = CGPoint(x: frame.maxX - 20, y: frame.minY)
            amplitude = 12
        } else {
            center = CGPoint(x: frame.maxX - 14, y: frame.minY + frame.height / 2)
            amplitude = 2
        }

        walkPhase += 0.1
        let offset = sin(walkPhase) * amplitude
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

    // MARK: - Idle behavior

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
        if island.isExpanded {
            expandedPerch = expandedPerch == .header ? .bottom : .header
            hop()
        } else if island.mediaService.isPlaying {
            if Bool.random() { hop() }
            model.look = CGFloat.random(in: -1...1)
        } else if sleeping {
            model.look = 0
        } else {
            model.look = CGFloat.random(in: -1...1)
            if Bool.random() { hop() }
        }
    }

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
