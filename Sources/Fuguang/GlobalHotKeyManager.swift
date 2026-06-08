import Carbon
import AppKit
import Foundation

@MainActor
final class GlobalHotKeyManager: ObservableObject {
    @Published var modifier: HotKeyModifier = .control {
        didSet {
            UserDefaults.standard.set(modifier.rawValue, forKey: Self.modifierDefaultsKey)
            refresh()
        }
    }
    @Published var isEnabled = true {
        didSet { refresh() }
    }
    @Published private(set) var statusText = "快捷键准备中"

    private weak var store: ShortcutStore?
    private var hotKeyRefs: [String: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var flagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var defaultsMonitor: NSObjectProtocol?
    private var isModifierPressedForToggle = false
    private var didUseKeyDuringModifierPress = false
    private var shouldCloseMainWindowOnModifierRelease = false

    func configure(with store: ShortcutStore) {
        self.store = store
        if let rawValue = UserDefaults.standard.string(forKey: Self.modifierDefaultsKey),
           let savedModifier = HotKeyModifier(rawValue: rawValue) {
            modifier = savedModifier
        }
        installHandlerIfNeeded()
        installFlagsMonitorIfNeeded()
        installKeyDownMonitorIfNeeded()
        installDefaultsMonitorIfNeeded()
        refresh()
    }

    func refresh() {
        unregisterAll()

        guard isEnabled else {
            statusText = "快捷键已暂停"
            return
        }

        var successCount = 0

        for key in KeyboardLayout.keys {
            guard let keyCode = Self.keyCodes[key] else { continue }

            var hotKeyRef: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(key.unicodeScalars.first!.value))
            let status = RegisterEventHotKey(
                UInt32(keyCode),
                UInt32(modifier.carbonModifier),
                id,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr, let hotKeyRef {
                hotKeyRefs[key] = hotKeyRef
                successCount += 1
            }
        }

        statusText = successCount == KeyboardLayout.keys.count
            ? "\(modifier.title) + 全键位已启用"
            : "部分快捷键注册失败"
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr, hotKeyID.signature == GlobalHotKeyManager.signature else {
                    return noErr
                }

                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                let scalar = UnicodeScalar(hotKeyID.id)
                let key = scalar.map { String(Character($0)) } ?? ""

                Task { @MainActor in
                    manager.trigger(key)
                }

                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )
    }

    private func trigger(_ key: String) {
        guard isEnabled, let store, !ScreenshotOverlayController.shared.isActive else { return }
        didUseKeyDuringModifierPress = true
        let binding = store.binding(for: key)
        ActionRunner.run(binding, store: store)
        if binding.kind != .screenshot {
            AppWindowController.hideMainWindow()
        }
    }

    private func installFlagsMonitorIfNeeded() {
        guard flagsMonitor == nil, localFlagsMonitor == nil else { return }

        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }
    }

    private func installKeyDownMonitorIfNeeded() {
        guard keyDownMonitor == nil, localKeyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDownDuringModifierPress(event)
            }
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDownDuringModifierPress(event)
            }
            return event
        }
    }

    private func installDefaultsMonitorIfNeeded() {
        guard defaultsMonitor == nil else { return }
        defaultsMonitor = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard
                let rawValue = UserDefaults.standard.string(forKey: Self.modifierDefaultsKey),
                let modifier = HotKeyModifier(rawValue: rawValue)
            else {
                return
            }

            Task { @MainActor in
                if self?.modifier != modifier {
                    self?.modifier = modifier
                }
            }
        }
    }

    /// 截图开始时调用，注销所有热键
    func suspendForScreenshot() {
        unregisterAll()
        resetModifierToggleState()
        statusText = "截图模式"
    }

    /// 截图结束时调用，重新注册热键
    func resumeFromScreenshot() {
        refresh()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard isEnabled else {
            resetModifierToggleState()
            return
        }

        let activeFlags = event.modifierFlags.intersection([.option, .control, .command, .shift, .capsLock])
        let isOnlyConfiguredModifierPressed = activeFlags == modifier.eventModifierFlag

        if isOnlyConfiguredModifierPressed {
            if !isModifierPressedForToggle {
                isModifierPressedForToggle = true
                didUseKeyDuringModifierPress = false
                shouldCloseMainWindowOnModifierRelease = AppWindowController.isMainWindowVisible
            }
            return
        }

        guard isModifierPressedForToggle else { return }

        if !didUseKeyDuringModifierPress, !ScreenshotOverlayController.shared.isActive {
            if shouldCloseMainWindowOnModifierRelease {
                AppWindowController.hideMainWindow()
            } else {
                AppWindowController.showMainWindow()
            }
        }
        resetModifierToggleState()
    }

    private func handleKeyDownDuringModifierPress(_ event: NSEvent) {
        guard isModifierPressedForToggle, !ScreenshotOverlayController.shared.isActive else { return }
        let activeFlags = event.modifierFlags.intersection([.option, .control, .command, .shift, .capsLock])
        if activeFlags.contains(modifier.eventModifierFlag) {
            didUseKeyDuringModifierPress = true
        }
    }

    private func resetModifierToggleState() {
        isModifierPressedForToggle = false
        didUseKeyDuringModifierPress = false
        shouldCloseMainWindowOnModifierRelease = false
    }

    private func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    deinit {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
        }
        if let defaultsMonitor {
            NotificationCenter.default.removeObserver(defaultsMonitor)
        }
    }

    nonisolated private static let modifierDefaultsKey = "hotKeyModifier"
    private static let signature: OSType = 0x46474748

    private static let keyCodes: [String: Int] = [
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
        "0": 29, "-": 27, "=": 24,
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
        "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32,
        "I": 34, "P": 35, "L": 37, "J": 38, "K": 40, "N": 45, "M": 46
    ]
}
