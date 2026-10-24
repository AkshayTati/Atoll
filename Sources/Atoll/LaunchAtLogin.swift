import Foundation
import ServiceManagement
import os

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Logger.app.info(
                "login item \(enabled ? "enabled" : "disabled", privacy: .public) status=\(SMAppService.mainApp.status.rawValue, privacy: .public)"
            )
        } catch {
            Logger.app.info("login item error: \(error.localizedDescription, privacy: .public)")
            print("login item error: \(error)")
        }
    }
}
