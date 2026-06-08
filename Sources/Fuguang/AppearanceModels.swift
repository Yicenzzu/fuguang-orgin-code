import SwiftUI

enum BackgroundAppearance: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "自动"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }
}
