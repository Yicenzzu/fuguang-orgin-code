import AppKit
import SwiftUI

@MainActor
final class PermissionStatusWindowController {
    static let shared = PermissionStatusWindowController()

    private var window: NSWindow?
    private let manager = PermissionManager.shared

    func show(guide: PermissionGuide? = nil) {
        if let window {
            manager.refresh()
            window.contentView = NSHostingView(rootView: PermissionStatusView(initialGuide: guide, manager: manager) { [weak self] in
                self?.window?.close()
            })
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PermissionStatusView(initialGuide: guide, manager: manager) { [weak self] in
            self?.window?.close()
        }
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: PermissionStatusLayout.scaledSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.identifier = AppWindowController.permissionWindowIdentifier
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
