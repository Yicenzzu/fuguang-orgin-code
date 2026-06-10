import Foundation

enum ShortcutActionKind: String, Codable, CaseIterable, Identifiable {
    case none
    case openApplication
    case openFolder
    case openWebsite
    case showDesktop
    case screenshot
    case imageResize
    case imageQuickLook
    case clipboard
    case lockScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "未设置"
        case .openApplication:
            return "打开应用"
        case .openFolder:
            return "打开文件夹"
        case .openWebsite:
            return "打开网站"
        case .showDesktop:
            return "浮光回桌"
        case .screenshot:
            return "浮光截图"
        case .imageResize:
            return "浮光改图"
        case .imageQuickLook:
            return "浮光图鉴"
        case .clipboard:
            return "浮光剪贴"
        case .lockScreen:
            return "浮光锁屏"
        }
    }

    var subtitle: String {
        switch self {
        case .none:
            return "选择一个动作"
        case .openApplication:
            return "绑定应用，按键直接启动"
        case .openFolder:
            return "打开常用文件夹"
        case .openWebsite:
            return "打开网页或工作台"
        case .showDesktop:
            return "切回桌面空间"
        case .screenshot:
            return "智能 / 手动选区并输出 PNG"
        case .imageResize:
            return "批量压缩、转格式并调整尺寸"
        case .imageQuickLook:
            return "设置当前图片快捷预览"
        case .clipboard:
            return "复制最近重新编辑的文本、图片与文件"
        case .lockScreen:
            return "锁定屏幕并关闭显示器"
        }
    }

    var systemImage: String {
        switch self {
        case .none:
            return "plus"
        case .openApplication:
            return "app.dashed"
        case .openFolder:
            return "folder"
        case .openWebsite:
            return "globe"
        case .showDesktop:
            return "house"
        case .screenshot:
            return "camera.viewfinder"
        case .imageResize:
            return "photo.on.rectangle.angled"
        case .imageQuickLook:
            return "photo"
        case .clipboard:
            return "doc.on.clipboard"
        case .lockScreen:
            return "lock"
        }
    }

    var requiresTarget: Bool {
        switch self {
        case .none, .showDesktop, .screenshot, .imageResize, .clipboard, .lockScreen:
            return false
        case .openApplication, .openFolder, .openWebsite, .imageQuickLook:
            return true
        }
    }
}

struct ShortcutBinding: Codable, Equatable, Identifiable {
    var key: String
    var kind: ShortcutActionKind
    var title: String
    var target: String

    var id: String { key }

    static func empty(key: String) -> ShortcutBinding {
        ShortcutBinding(key: key, kind: .none, title: "", target: "")
    }

    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        switch kind {
        case .none:
            return "点击设置"
        case .openApplication, .openFolder, .imageQuickLook:
            return URL(fileURLWithPath: target).deletingPathExtension().lastPathComponent
        case .openWebsite:
            return target
        case .showDesktop, .screenshot, .imageResize, .clipboard, .lockScreen:
            return kind.title
        }
    }

    var isConfigured: Bool {
        guard kind != .none else { return false }
        return !kind.requiresTarget || !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum KeyboardLayout {
    static let rows: [[String]] = [
        Array("1234567890-=").map(String.init),
        Array("QWERTYUIOP").map(String.init),
        Array("ASDFGHJKL").map(String.init),
        Array("ZXCVBNM").map(String.init)
    ]

    static let keys = rows.flatMap { $0 }
    static let letters = keys
}

extension ShortcutActionKind {
    static let fuguangActions: [ShortcutActionKind] = [
        .showDesktop,
        .screenshot,
        .imageResize,
        .clipboard,
        .lockScreen
    ]
}
