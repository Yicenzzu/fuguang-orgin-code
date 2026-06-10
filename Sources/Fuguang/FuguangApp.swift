import SwiftUI

@main
struct FuguangApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("backgroundAppearance") private var backgroundAppearanceRawValue = BackgroundAppearance.automatic.rawValue
    @AppStorage("hotKeyModifier") private var hotKeyModifierRawValue = HotKeyModifier.control.rawValue
    @StateObject private var store = ShortcutStore()
    @StateObject private var hotKeys = GlobalHotKeyManager()
    @StateObject private var permissions = PermissionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(hotKeys)
                .frame(minWidth: 1000, minHeight: 500)
                .task {
                    permissions.refresh()
                    hotKeys.configure(with: store)
                }
                .onChange(of: store.bindings) { _, _ in
                    hotKeys.refresh()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("主题") {
                themeMenuItems
            }
        }

        MenuBarExtra("Fuguang", systemImage: hotKeys.isEnabled ? "keyboard" : "keyboard.badge.ellipsis") {
            Button("打开 Fuguang") {
                AppWindowController.showMainWindow()
            }

            Divider()

            Button("权限与状态") {
                PermissionStatusWindowController.shared.show()
            }

            Divider()

            Toggle("启用快捷键", isOn: $hotKeys.isEnabled)

            Divider()

            Menu("组合键") {
                modifierMenuItems
            }

            Menu("主题") {
                themeMenuItems
            }

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private var themeMenuItems: some View {
        ForEach(BackgroundAppearance.allCases) { appearance in
            Button {
                backgroundAppearanceRawValue = appearance.rawValue
            } label: {
                Text("\(backgroundAppearanceRawValue == appearance.rawValue ? "✓ " : "")\(appearance.title)")
            }
        }
    }

    @ViewBuilder
    private var modifierMenuItems: some View {
        ForEach(HotKeyModifier.allCases) { modifier in
            Button {
                hotKeyModifierRawValue = modifier.rawValue
                hotKeys.modifier = modifier
            } label: {
                Text("\(hotKeyModifierRawValue == modifier.rawValue ? "✓ " : "")\(modifier.title)")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        DispatchQueue.main.async {
            if let mainWindow = AppWindowController.mainWindow {
                AppWindowController.prepare(mainWindow)
                mainWindow.orderOut(nil)
            }
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "Fuguang")
        let themeMenu = NSMenu(title: "主题")
        let modifierMenu = NSMenu(title: "组合键")
        let currentValue = UserDefaults.standard.string(forKey: "backgroundAppearance") ?? BackgroundAppearance.automatic.rawValue
        let currentModifier = UserDefaults.standard.string(forKey: "hotKeyModifier") ?? HotKeyModifier.control.rawValue

        let openItem = NSMenuItem(title: "打开 Fuguang", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let permissionItem = NSMenuItem(title: "权限与状态", action: #selector(openPermissionStatus), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(.separator())

        for appearance in BackgroundAppearance.allCases {
            let title = "\(currentValue == appearance.rawValue ? "✓ " : "")\(appearance.title)"
            let item = NSMenuItem(title: title, action: #selector(setThemeFromDockMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = appearance.rawValue
            themeMenu.addItem(item)
        }

        let parentItem = NSMenuItem(title: "主题", action: nil, keyEquivalent: "")
        menu.addItem(parentItem)
        menu.setSubmenu(themeMenu, for: parentItem)

        for modifier in HotKeyModifier.allCases {
            let title = "\(currentModifier == modifier.rawValue ? "✓ " : "")\(modifier.title)"
            let item = NSMenuItem(title: title, action: #selector(setModifierFromDockMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = modifier.rawValue
            modifierMenu.addItem(item)
        }

        let modifierParentItem = NSMenuItem(title: "组合键", action: nil, keyEquivalent: "")
        menu.addItem(modifierParentItem)
        menu.setSubmenu(modifierMenu, for: modifierParentItem)
        return menu
    }

    @objc private func openMainWindow() {
        Task { @MainActor in
            AppWindowController.showMainWindow()
        }
    }

    @objc private func openPermissionStatus() {
        Task { @MainActor in
            PermissionStatusWindowController.shared.show()
        }
    }

    @objc private func setThemeFromDockMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else { return }
        UserDefaults.standard.set(rawValue, forKey: "backgroundAppearance")
    }

    @objc private func setModifierFromDockMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else { return }
        UserDefaults.standard.set(rawValue, forKey: "hotKeyModifier")
    }
}
