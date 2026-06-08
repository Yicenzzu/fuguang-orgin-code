import AppKit

@MainActor
enum AppWindowController {
    private static let fixedSize = NSSize(width: 1000, height: 500)

    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow {
            window.level = .floating
            window.setContentSize(fixedSize)
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func hideMainWindow() {
        mainWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    static var mainWindow: NSWindow? {
        NSApp.windows.first { window in
            !(window.contentView is ScreenshotOverlayView)
                && window.className != "NSStatusBarWindow"
        }
    }

    static var isMainWindowVisible: Bool {
        mainWindow?.isVisible == true
    }

    static func prepare(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.delegate = WindowDelegate.shared
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.minSize = fixedSize
        window.maxSize = fixedSize
        window.setContentSize(fixedSize)
    }
}

final class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    // 彻底禁止拖拽改变窗口尺寸
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        return sender.frame.size
    }

    // 禁止双击标题栏缩放
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor in
            AppWindowController.hideMainWindow()
        }
        return false
    }
}
