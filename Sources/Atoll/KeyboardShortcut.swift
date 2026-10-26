import Carbon
import Foundation

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String

    var display: String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + keyLabel
    }

    static let defaultCatToggle = KeyboardShortcut(
        keyCode: 8,
        modifiers: UInt32(controlKey | optionKey),
        keyLabel: "C"
    )
}
