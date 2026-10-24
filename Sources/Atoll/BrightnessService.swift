import Combine
import CoreGraphics
import Foundation
import os

/// Internal-display brightness via the private DisplayServices framework.
final class BrightnessService: ObservableObject {
    @Published private(set) var value: Double = 0
    @Published private(set) var available = false

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var handle: UnsafeMutableRawPointer?
    private var getBrightness: GetBrightnessFn?
    private var setBrightness: SetBrightnessFn?

    func start() {
        guard CGDisplayIsBuiltin(CGMainDisplayID()) != 0 else {
            Logger.app.info("brightness: no built-in display")
            return
        }

        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW) else {
            Logger.app.info("brightness: DisplayServices unavailable")
            return
        }
        self.handle = handle

        guard let getPointer = dlsym(handle, "DisplayServicesGetBrightness"),
              let setPointer = dlsym(handle, "DisplayServicesSetBrightness") else {
            Logger.app.info("brightness: DisplayServices symbols missing")
            return
        }

        getBrightness = unsafeBitCast(getPointer, to: GetBrightnessFn.self)
        setBrightness = unsafeBitCast(setPointer, to: SetBrightnessFn.self)
        available = true
        refresh()
        Logger.app.info("brightness: DisplayServices ready")
    }

    func refresh() {
        guard let getBrightness else { return }
        var current: Float = 0
        if getBrightness(CGMainDisplayID(), &current) == 0 {
            value = Double(current)
            available = true
        } else {
            available = false
            Logger.app.info("brightness: read failed")
        }
    }

    @discardableResult
    func adjust(by delta: Double) -> Double {
        let next = min(max(value + delta, 0), 1)
        set(next)
        return next
    }

    func set(_ newValue: Double) {
        guard let setBrightness else { return }
        let clamped = Float(min(max(newValue, 0), 1))
        if setBrightness(CGMainDisplayID(), clamped) == 0 {
            value = Double(clamped)
        } else {
            Logger.app.info("brightness: write failed")
        }
    }
}
