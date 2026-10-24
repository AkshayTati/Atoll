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
    var onHover: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

final class MascotController {
    private let island: IslandController
    private let model = MascotModel()
    private var panel: MascotPanel?
    private var host: MascotHostingView<MascotView>?
    private var positionTimer: Timer?
    private var behaviorTimer: Timer?
    private var actionWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var islandMoveWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private var enabled: Bool
    private var currentCenter: CGPoint?
    private var targetCenter: CGPoint?
    private var moveAction: CatAction = .walk
    private var moveSpeed: CGFloat = 30
    private var pendingCompletion: (() -> Void)?
    private var lastFrame = NSRect.zero
    private var lastTick = Date()
    private var lastExpanded = false
    private var sleeping = false
    private var idleSince: Date?
    private var lastPeekSide: PeekSide = .right
    private var isPeeking = false
    private var wasHovered = false

    private enum PeekSide {
        case left
        case right
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
        CatSpriteLibrary.shared.preload()
        createPanel()
        startPositionTimer()
        scheduleBehavior()
        observeMedia()
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        UserDefaults.standard.set(enabled, forKey: "showMascot")
        island.mascotEnabled = enabled

        if enabled {
            CatSpriteLibrary.shared.preload()
            if panel == nil { createPanel() }
            panel?.orderFrontRegardless()
            startPositionTimer()
            scheduleBehavior()
        } else {
            panel?.orderOut(nil)
            positionTimer?.invalidate()
            positionTimer = nil
            behaviorTimer?.invalidate()
            behaviorTimer = nil
            islandMoveWork?.cancel()
            islandMoveWork = nil
            cancelAction()
            cancelMovement()
            cancelPeek()
        }
    }

    // MARK: - Panel

    private func createPanel() {
        guard panel == nil else { return }

        let panel = MascotPanel(
            contentRect: NSRect(x: 0, y: 0, width: 48, height: 48),
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
        host.onHover = { [weak self] inside in self?.handleHover(inside) }
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)

        self.host = host
        self.panel = panel
        self.lastTick = Date()
        updatePosition()
    }

    private func startPositionTimer() {
        guard positionTimer == nil else { return }
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
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

        let now = Date()
        let dt = min(0.1, max(0.0, now.timeIntervalSince(lastTick)))
        lastTick = now

        let expanded = island.isExpanded
        let playing = island.mediaService.isPlaying

        if expanded || playing {
            idleSince = nil
            if sleeping {
                wake()
            }
        } else if idleSince == nil {
            idleSince = now
        } else if now.timeIntervalSince(idleSince!) > 45,
                  !sleeping,
                  !isBusy,
                  !isPeeking {
            startSleep(frame)
        }

        if expanded != lastExpanded {
            lastExpanded = expanded
            cancelPeek()
            scheduleIslandPerchMove()
        }

        if currentCenter == nil {
            currentCenter = expanded ? headerPerch(frame) : rightWingPerch(frame)
        }

        if let target = targetCenter, let current = currentCenter {
            let dx = target.x - current.x
            let dy = target.y - current.y
            let distance = sqrt(dx * dx + dy * dy)
            let step = max(0.5, moveSpeed * CGFloat(dt))

            if distance <= step {
                currentCenter = target
                targetCenter = nil
                if abs(dx) > 0.2 {
                    model.facing = dx > 0 ? .east : .west
                }
                setAction(moveAction)
                let completion = pendingCompletion
                pendingCompletion = nil
                completion?()
            } else {
                let factor = step / distance
                currentCenter = CGPoint(x: current.x + dx * factor, y: current.y + dy * factor)
                if abs(dx) > 0.2 {
                    model.facing = dx > 0 ? .east : .west
                }
                setAction(moveAction)
            }
        }

        if let center = currentCenter {
            let rect = NSRect(
                x: (center.x - 24).rounded(),
                y: (center.y - 24).rounded(),
                width: 48,
                height: 48
            )
            if rect != lastFrame {
                panel.setFrame(rect, display: false)
                lastFrame = rect
            }
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        }
    }

    private func scheduleIslandPerchMove() {
        islandMoveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled, !self.isPeeking else { return }
            let frame = self.island.currentPanelFrame
            guard frame.width > 0 else { return }
            if self.island.isExpanded {
                self.travel(to: self.headerPerch(frame), action: .walk, speed: 44, frame: frame)
            } else {
                self.travel(to: self.rightWingPerch(frame), action: .walk, speed: 32, frame: frame)
            }
        }
        islandMoveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - Perches

    private func headerPerch(_ frame: NSRect, x: CGFloat? = nil) -> CGPoint {
        CGPoint(x: x ?? (frame.maxX - 80), y: frame.maxY - 10)
    }

    private func rightWingPerch(_ frame: NSRect) -> CGPoint {
        CGPoint(x: frame.maxX - 14, y: frame.minY + 22)
    }

    private func leftWingPerch(_ frame: NSRect) -> CGPoint {
        CGPoint(x: frame.minX + 14, y: frame.minY + 22)
    }

    private func belowPerch(_ frame: NSRect, x: CGFloat) -> CGPoint {
        CGPoint(x: x, y: frame.minY - 18)
    }

    private func outerLeftPerch(_ frame: NSRect) -> CGPoint {
        CGPoint(x: frame.minX - 14, y: frame.minY + 22)
    }

    private func outerRightPerch(_ frame: NSRect) -> CGPoint {
        CGPoint(x: frame.maxX + 14, y: frame.minY + 22)
    }

    private func notchLeft(_ frame: NSRect) -> CGFloat {
        frame.midX - island.notchWidth / 2
    }

    private func notchRight(_ frame: NSRect) -> CGFloat {
        frame.midX + island.notchWidth / 2
    }

    private func peekBase(_ frame: NSRect, side: PeekSide) -> CGPoint {
        let x = side == .left ? notchLeft(frame) - 8 : notchRight(frame) + 8
        return CGPoint(x: x, y: frame.minY - 18)
    }

    private func peekTop(_ frame: NSRect, side: PeekSide) -> CGPoint {
        let x = side == .left ? notchLeft(frame) - 8 : notchRight(frame) + 8
        return CGPoint(x: x, y: frame.maxY - island.notchHeight / 2 - 2)
    }

    // MARK: - Actions

    private func setAction(_ action: CatAction, facing: CatFacing? = nil, restart: Bool = false) {
        if let facing {
            model.facing = facing
        }
        if model.action != action || restart {
            model.action = action
            model.actionEpoch = Date()
        }
    }

    private func perform(
        _ action: CatAction,
        duration: TimeInterval? = nil,
        facing: CatFacing? = nil,
        then: (() -> Void)? = nil
    ) {
        cancelAction()
        setAction(action, facing: facing, restart: true)

        guard let duration = duration ?? action.duration else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.actionWork = nil
            if let then {
                then()
            } else {
                self.setAction(.idle)
            }
        }
        actionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func cancelAction() {
        actionWork?.cancel()
        actionWork = nil
    }

    private func moveTo(
        _ target: CGPoint,
        action: CatAction,
        speed: CGFloat,
        completion: (() -> Void)? = nil
    ) {
        cancelAction()

        guard let current = currentCenter else {
            currentCenter = target
            completion?()
            return
        }

        if abs(target.x - current.x) > 0.2 {
            model.facing = target.x > current.x ? .east : .west
        }

        targetCenter = target
        moveAction = action
        moveSpeed = max(1, speed)
        pendingCompletion = completion
        setAction(action, restart: true)
    }

    private func cancelMovement() {
        targetCenter = nil
        pendingCompletion = nil
    }

    /// Moves around the notch instead of through it. The notch is a physical
    /// cutout, so anything drawn over it disappears. The cat therefore goes
    /// down below the island, crosses underneath, and climbs back up.
    private func travel(
        to target: CGPoint,
        action: CatAction,
        speed: CGFloat,
        frame: NSRect,
        completion: (() -> Void)? = nil
    ) {
        guard let current = currentCenter else {
            currentCenter = target
            completion?()
            return
        }

        let belowY = frame.minY - 18
        let highThreshold = belowY + 10
        let currentHigh = current.y > highThreshold
        let targetHigh = target.y > highThreshold
        let left = notchLeft(frame)
        let right = notchRight(frame)
        let sameSide = (current.x < left && target.x < left)
            || (current.x > right && target.x > right)
        let closeX = abs(target.x - current.x) < 24

        if !currentHigh && !targetHigh {
            moveTo(target, action: action, speed: speed, completion: completion)
        } else if currentHigh && targetHigh && (sameSide || closeX) {
            moveTo(target, action: action, speed: speed, completion: completion)
        } else if currentHigh && !targetHigh {
            let down = CGPoint(x: current.x, y: belowY)
            moveTo(down, action: action, speed: speed) { [weak self] in
                self?.moveTo(target, action: action, speed: speed, completion: completion)
            }
        } else if !currentHigh && targetHigh {
            let across = CGPoint(x: target.x, y: belowY)
            moveTo(across, action: action, speed: speed) { [weak self] in
                self?.moveTo(target, action: action, speed: speed, completion: completion)
            }
        } else {
            let down = CGPoint(x: current.x, y: belowY)
            let across = CGPoint(x: target.x, y: belowY)
            moveTo(down, action: action, speed: speed) { [weak self] in
                self?.moveTo(across, action: action, speed: speed) { [weak self] in
                    self?.moveTo(target, action: action, speed: speed, completion: completion)
                }
            }
        }
    }

    private var isBusy: Bool {
        targetCenter != nil || actionWork != nil || isPeeking
    }

    // MARK: - Interactions

    private func handleClick() {
        Haptics.select()
        idleSince = nil

        if sleeping {
            wake()
        }

        if island.isExpanded {
            perform(.love, duration: 1.3)
        } else {
            if isPeeking {
                cancelPeek()
            }
            island.expand()
        }
    }

    private func handleHover(_ inside: Bool) {
        model.hovered = inside

        if inside {
            guard !wasHovered else { return }
            wasHovered = true
            idleSince = nil

            if sleeping {
                wake()
                return
            }
            guard !isBusy, !isPeeking else { return }
            perform(.greet, duration: 1.3)
        } else {
            wasHovered = false
        }
    }

    private func observeMedia() {
        island.mediaService.$title
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] title in
                guard let self,
                      !title.isEmpty,
                      !self.sleeping,
                      !self.isPeeking,
                      !self.isBusy else { return }
                self.perform(.surprised, duration: 1.0)
            }
            .store(in: &cancellables)
    }

    // MARK: - Behavior

    private func scheduleBehavior() {
        behaviorTimer?.invalidate()
        let timer = Timer(timeInterval: Double.random(in: 4.0...8.0), repeats: false) { [weak self] _ in
            guard let self, self.enabled else { return }
            self.behaviorTick()
            self.scheduleBehavior()
        }
        RunLoop.main.add(timer, forMode: .common)
        behaviorTimer = timer
    }

    private func behaviorTick() {
        guard enabled, !isBusy, !sleeping, !isPeeking else { return }
        let frame = island.currentPanelFrame
        guard frame.width > 0 else { return }

        if island.isExpanded {
            let roll = Int.random(in: 0..<12)
            if roll < 5 {
                let lower = max(frame.minX + 80, notchRight(frame) + 40)
                let upper = frame.maxX - 60
                let x = upper > lower ? CGFloat.random(in: lower...upper) : frame.maxX - 80
                let gait = randomTravelAction()
                travel(to: headerPerch(frame, x: x), action: gait.0, speed: gait.1, frame: frame)
            } else if roll < 8 {
                perform(.sit, duration: Double.random(in: 4...7))
            } else if roll < 10 {
                perform(.groom, duration: 3)
            } else if roll < 11 {
                perform(.chase, duration: 3.5)
            } else {
                perform(.stretch, duration: 1.4)
            }
        } else if island.mediaService.isPlaying {
            let roll = Int.random(in: 0..<14)
            if roll < 5 {
                let gait = randomTravelAction()
                wander(frame, action: gait.0, speed: gait.1)
            } else if roll < 7 {
                startPeek()
            } else if roll < 9 {
                perform(.play, duration: 3.5)
            } else if roll < 10 {
                perform(.pounce, duration: 0.7)
            } else if roll < 12 {
                perform(.sit, duration: 4)
            } else {
                perform(.groom, duration: 3)
            }
        } else {
            let roll = Int.random(in: 0..<16)
            if roll < 5 {
                let gait = randomTravelAction()
                wander(frame, action: gait.0, speed: gait.1)
            } else if roll < 7 {
                startPeek()
            } else if roll < 9 {
                perform(.groom, duration: 3)
            } else if roll < 10 {
                perform(.stretch, duration: 1.4)
            } else if roll < 11 {
                perform(.yawn, duration: 1.4)
            } else if roll < 12 {
                perform(.chase, duration: 3.5)
            } else if roll < 13 {
                perform(.pounce, duration: 0.7)
            } else if roll < 14 {
                perform(.flat, duration: 6)
            } else {
                perform(.sit, duration: 5)
            }
        }
    }

    private func wander(_ frame: NSRect, action: CatAction, speed: CGFloat) {
        let roll = Int.random(in: 0..<10)
        let target: CGPoint

        if roll < 4 {
            let lower = notchLeft(frame) + 50
            let upper = notchRight(frame) - 50
            let x = upper > lower ? CGFloat.random(in: lower...upper) : frame.midX
            target = belowPerch(frame, x: x)
        } else if roll < 7 {
            target = Bool.random() ? leftWingPerch(frame) : rightWingPerch(frame)
        } else {
            target = Bool.random() ? outerLeftPerch(frame) : outerRightPerch(frame)
        }

        travel(to: target, action: action, speed: speed, frame: frame)
    }

    private func randomTravelAction() -> (CatAction, CGFloat) {
        switch Int.random(in: 0..<10) {
        case 0..<5:
            return (.walk, 30)
        case 5..<8:
            return (.sneak, 18)
        default:
            return (.run, 70)
        }
    }

    // MARK: - Sleep

    private func startSleep(_ frame: NSRect) {
        guard !isBusy, !isPeeking else { return }
        sleeping = true
        cancelAction()
        let perch = island.isExpanded
            ? headerPerch(frame, x: frame.maxX - 80)
            : rightWingPerch(frame)
        travel(to: perch, action: .walk, speed: 26, frame: frame) { [weak self] in
            guard let self, self.sleeping else { return }
            self.setAction(.sleep)
        }
    }

    private func wake() {
        guard sleeping else { return }
        sleeping = false
        idleSince = Date()
        cancelMovement()
        perform(.wake, duration: 1.0) { [weak self] in
            guard let self, !self.sleeping else { return }
            self.setAction(.idle)
        }
    }

    // MARK: - Peek-a-boo from the notch sides

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

    private func startPeek(force: Bool = false) {
        guard !island.isExpanded, !sleeping else { return }
        if isPeeking && !force { return }
        if force {
            cancelPeek()
        }
        let frame = island.currentPanelFrame
        guard frame.width > 0 else { return }

        let side: PeekSide = lastPeekSide == .left ? .right : .left
        lastPeekSide = side
        let facing: CatFacing = side == .left ? .east : .west

        isPeeking = true
        cancelAction()
        cancelMovement()

        let sideName = side == .left ? "left" : "right"
        Logger.app.info("cat: peek side=\(sideName, privacy: .public)")

        let base = peekBase(frame, side: side)
        let top = peekTop(frame, side: side)
        let distance = hypot(base.x - (currentCenter?.x ?? base.x), base.y - (currentCenter?.y ?? base.y))
        let approachAction: CatAction = distance > 120 ? .run : .walk
        let approachSpeed: CGFloat = distance > 120 ? 110 : 42

        travel(to: base, action: approachAction, speed: approachSpeed, frame: frame) { [weak self] in
            guard let self, self.isPeeking else { return }
            self.model.facing = facing
            self.moveTo(top, action: .peek, speed: 55) { [weak self] in
                guard let self, self.isPeeking else { return }
                self.setAction(.peek, facing: facing)

                let hold = DispatchWorkItem { [weak self] in
                    guard let self, self.isPeeking else { return }
                    self.moveTo(base, action: .peek, speed: 45) { [weak self] in
                        guard let self else { return }
                        self.isPeeking = false
                        self.setAction(.idle)
                    }
                }
                self.peekWork = hold
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: hold)
            }
        }
    }

    private func cancelPeek() {
        isPeeking = false
        peekWork?.cancel()
        peekWork = nil
        cancelMovement()
        cancelAction()
        if !sleeping {
            setAction(.idle)
        }
    }
}
