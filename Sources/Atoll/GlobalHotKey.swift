import Carbon
import Combine
import Foundation
import os

final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x41544C4C), id: 1)

    var onPressed: (() -> Void)?

    func register(_ shortcut: KeyboardShortcut) -> Bool {
        unregister()
        installHandlerIfNeeded()

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            hotKeyRef = nil
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }

            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &identifier
            )
            guard status == noErr else { return status }

            let manager = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            if identifier.signature == manager.hotKeyID.signature,
               identifier.id == manager.hotKeyID.id {
                manager.onPressed?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

final class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()

    @Published private(set) var registered = false
    @Published private(set) var errorMessage: String?

    var onToggleCat: (() -> Void)?

    private let hotKey = GlobalHotKey()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        hotKey.onPressed = { [weak self] in
            self?.onToggleCat?()
        }
    }

    func start() {
        AtollSettings.shared.$catShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.apply(shortcut)
            }
            .store(in: &cancellables)
    }

    private func apply(_ shortcut: KeyboardShortcut) {
        let success = hotKey.register(shortcut)
        registered = success
        errorMessage = success ? nil : "That shortcut is already in use."

        Logger.app.info(
            "shortcut: \(shortcut.display, privacy: .public) registered=\(success, privacy: .public)"
        )
    }
}
