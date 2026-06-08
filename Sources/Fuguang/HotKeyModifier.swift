import Carbon
import AppKit
import Foundation

enum HotKeyModifier: String, CaseIterable, Identifiable {
    case option
    case control

    var id: String { rawValue }

    var title: String {
        switch self {
        case .option:
            return "Option"
        case .control:
            return "Control"
        }
    }

    var carbonModifier: Int {
        switch self {
        case .option:
            return optionKey
        case .control:
            return controlKey
        }
    }

    var eventModifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .option:
            return .option
        case .control:
            return .control
        }
    }
}
