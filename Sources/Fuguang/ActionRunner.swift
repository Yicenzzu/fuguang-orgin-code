import AppKit
import Foundation

enum ActionRunner {
    @MainActor
    static func run(_ binding: ShortcutBinding, store: ShortcutStore) {
        guard binding.isConfigured else {
            store.lastMessage = "\(binding.key) 尚未设置动作"
            return
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
        case .screenshot:
            runInteractiveScreenshot(store: store)
        case .imageResize:
            ImageToolWindowController.shared.show(store: store)
            store.lastMessage = "已打开浮光改图"
        case .imageQuickLook:
            quickLookImage(binding, store: store)
        case .clipboard:
            store.lastMessage = "浮光剪贴已预留：下一步接入历史剪贴板"
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
    private static func runInteractiveScreenshot(store: ShortcutStore) {
        ScreenshotOverlayController.shared.begin(store: store)
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
