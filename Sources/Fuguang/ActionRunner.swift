import AppKit
import Foundation

enum ActionRunner {
    /// 是否在执行动作前检测权限
    static var checkPermissionBeforeRun = true

    @MainActor
    static func run(_ binding: ShortcutBinding, store: ShortcutStore) {
        guard binding.isConfigured else {
            store.lastMessage = "\(binding.key) 尚未设置动作"
            return
        }

        if Self.checkPermissionBeforeRun {
            PermissionManager.shared.refresh()
            if let guide = binding.kind.requiredPermissionGuide,
               !PermissionManager.shared.status(for: guide).isReady {
                store.lastMessage = "\(binding.kind.title) 需要先开启权限"
                PermissionStatusWindowController.shared.show(guide: guide)
                return
            }
        }

        switch binding.kind {
        case .none:
            store.lastMessage = "\(binding.key) 尚未设置动作"
        case .openApplication:
            openFileURL(binding, store: store, missingMessage: "应用不存在")
        case .openFolder:
            openFileURL(binding, store: store, missingMessage: "文件夹不存在")
        case .openWebsite:
            openWebsite(binding, store: store)
        case .showDesktop:
            showDesktop(store: store)
        case .screenshot:
            takeScreenshot(store: store)
        case .imageResize:
            ImageToolWindowController.shared.show(store: store)
            store.lastMessage = "已打开浮光改图"
        case .imageQuickLook:
            quickLookImage(binding, store: store)
        case .clipboard:
            showClipboard(store: store)
        case .lockScreen:
            lockScreen(store: store)
        }
    }

    @MainActor
    private static func openFileURL(_ binding: ShortcutBinding, store: ShortcutStore, missingMessage: String) {
        let url = URL(fileURLWithPath: binding.target)
        guard FileManager.default.fileExists(atPath: url.path) else {
            store.lastMessage = "\(missingMessage)：\(binding.displayTitle)"
            return
        }

        NSWorkspace.shared.open(url)
        store.lastMessage = "已打开 \(binding.displayTitle)"
    }

    @MainActor
    private static func openWebsite(_ binding: ShortcutBinding, store: ShortcutStore) {
        guard let url = normalizedURL(from: binding.target) else {
            store.lastMessage = "网址无效：\(binding.target)"
            return
        }

        NSWorkspace.shared.open(url)
        store.lastMessage = "已打开 \(binding.displayTitle)"
    }

    @MainActor
    private static func quickLookImage(_ binding: ShortcutBinding, store: ShortcutStore) {
        let url = URL(fileURLWithPath: binding.target)
        guard FileManager.default.fileExists(atPath: url.path) else {
            store.lastMessage = "图片不存在：\(binding.displayTitle)"
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
        store.lastMessage = "已在访达定位 \(binding.displayTitle)"
    }

    @MainActor
    private static func showDesktop(store: ShortcutStore) {
        let script = NSAppleScript(source: #"tell application "System Events" to key code 103"#)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)

        if let error {
            store.lastMessage = "回桌失败：\(error["NSAppleScriptErrorMessage"] as? String ?? "需要辅助功能权限")"
        } else {
            store.lastMessage = "已切回桌面"
        }
    }

    @MainActor
    private static func takeScreenshot(store: ShortcutStore) {
        AppWindowController.hideMainWindow()
        ScreenshotOverlayController.shared.show(store: store)
    }

    @MainActor
    private static func showClipboard(store: ShortcutStore) {
        let pasteboard = NSPasteboard.general
        let message: String

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            message = String(string.prefix(800))
        } else if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !fileURLs.isEmpty {
            message = fileURLs.map(\.path).joined(separator: "\n")
        } else if pasteboard.canReadObject(forClasses: [NSImage.self]) {
            message = "剪贴板中有图片内容。"
        } else {
            message = "剪贴板暂无可预览内容。"
        }

        let alert = NSAlert()
        alert.messageText = "浮光剪贴"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        alert.runModal()
        store.lastMessage = "已查看剪贴板"
    }

    @MainActor
    private static func lockScreen(store: ShortcutStore) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession")
        process.arguments = ["-suspend"]

        do {
            try process.run()
            store.lastMessage = "已锁定屏幕"
        } catch {
            store.lastMessage = "锁屏失败：\(error.localizedDescription)"
        }
    }

    static func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        return URL(string: "https://\(trimmed)")
    }
}

private extension ShortcutActionKind {
    var requiredPermissionGuide: PermissionGuide? {
        switch self {
        case .showDesktop:
            return .accessibility
        case .screenshot:
            return .screenRecording
        default:
            return nil
        }
    }
}
