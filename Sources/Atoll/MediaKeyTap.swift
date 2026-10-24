import AppKit
import ApplicationServices
import CoreGraphics
import os

/// Intercepts the volume/brightness/mute media keys so the native OSD never
/// appears. Requires Accessibility permission.
final class MediaKeyTap {
    var shouldHandle: (() -> Bool)?
    var brightnessAvailable: (() -> Bool)?
    var onVolumeUp: ((Bool) -> Void)?
    var onVolumeDown: ((Bool) -> Void)?
    var onMute: (() -> Void)?
    var onBrightnessUp: ((Bool) -> Void)?
    var onBrightnessDown: ((Bool) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() -> Bool {
        guard AXIsProcessTrusted() else {
            Logger.app.info("hud: Accessibility not granted")
            return false
        }

        let systemDefinedType = CGEventType(rawValue: 14)!
        let mask = CGEventMask(1 << systemDefinedType.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.app.info("hud: event tap creation failed")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8,
              shouldHandle?() == true else {
            return Unmanaged.passUnretained(event)
        }

        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF0000) >> 16
        let keyState = (data & 0x0000FF00) >> 8
        guard keyState == 0x0A else {
            return Unmanaged.passUnretained(event)
        }

        let fine = nsEvent.modifierFlags.contains(.option)

        switch keyCode {
        case 0:
            onVolumeUp?(fine)
            return nil
        case 1:
            onVolumeDown?(fine)
            return nil
        case 2:
            guard brightnessAvailable?() == true else {
                return Unmanaged.passUnretained(event)
            }
            onBrightnessUp?(fine)
            return nil
        case 3:
            guard brightnessAvailable?() == true else {
                return Unmanaged.passUnretained(event)
            }
            onBrightnessDown?(fine)
            return nil
        case 7:
            onMute?()
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
