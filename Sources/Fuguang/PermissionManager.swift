import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid
import ScreenCaptureKit
import ServiceManagement
import AppKit

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published private(set) var accessibilityStatus: PermissionAuthorizationStatus = .unknown
    @Published private(set) var inputMonitoringStatus: PermissionAuthorizationStatus = .unknown
    @Published private(set) var screenRecordingStatus: PermissionAuthorizationStatus = .unknown
    @Published private(set) var loginItemStatus: PermissionAuthorizationStatus = .unknown
    @Published private(set) var loginItemError: String?

    init() {
        refresh()
    }

    func refresh() {
        accessibilityStatus = AXIsProcessTrusted() ? .enabled : .needsAction
        inputMonitoringStatus = Self.currentInputMonitoringStatus()
        screenRecordingStatus = Self.currentScreenRecordingStatus()
        loginItemStatus = Self.currentLoginItemStatus()
    }

    func refreshAfterUserAction() {
        refresh()
        refreshScreenRecordingStatusWithScreenCaptureKit()
    }

    func status(for guide: PermissionGuide) -> PermissionAuthorizationStatus {
        switch guide {
        case .accessibility:
            return accessibilityStatus
        case .inputMonitoring:
            return inputMonitoringStatus
        case .screenRecording:
            return screenRecordingStatus
        case .loginItem:
            return loginItemStatus
        }
    }

    func manageAccessibility() {
        openPrivacyPane("Privacy_Accessibility")
        refreshSoon()
    }

    func manageInputMonitoring() {
        openPrivacyPane("Privacy_ListenEvent")
        refreshSoon()
    }

    func manageScreenRecording() {
        openPrivacyPane("Privacy_ScreenCapture")
        refreshSoon()
    }

    func addAccessibilityToPermissionList() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshSoon()
    }

    func addInputMonitoringToPermissionList() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshSoon()
    }

    func addScreenRecordingToPermissionList() {
        _ = CGRequestScreenCaptureAccess()
        refreshSoon()
    }

    func toggleLoginItem() {
        loginItemError = nil

        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            default:
                try SMAppService.mainApp.register()
            }
        } catch {
            loginItemError = error.localizedDescription
            openSettingsPane("com.apple.LoginItems-Settings.extension")
        }

        refresh()
    }

    func openLoginItemSettings() {
        openSettingsPane("com.apple.LoginItems-Settings.extension")
    }

    private func refreshSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            refreshAfterUserAction()
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        openSettingsPane("com.apple.preference.security?\(anchor)")
    }

    private func openSettingsPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func currentInputMonitoringStatus() -> PermissionAuthorizationStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return .enabled
        case kIOHIDAccessTypeDenied:
            return .needsAction
        default:
            return .unknown
        }
    }

    private static func currentLoginItemStatus() -> PermissionAuthorizationStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .needsAction
        default:
            return .disabled
        }
    }

    private static func currentScreenRecordingStatus() -> PermissionAuthorizationStatus {
        CGPreflightScreenCaptureAccess() ? .enabled : .needsAction
    }

    private func refreshScreenRecordingStatusWithScreenCaptureKit() {
        Task { @MainActor in
            guard screenRecordingStatus != .enabled else { return }

            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                if !content.displays.isEmpty {
                    screenRecordingStatus = .enabled
                }
            } catch {
                if screenRecordingStatus == .unknown {
                    screenRecordingStatus = .needsAction
                }
            }
        }
    }
}

enum PermissionAuthorizationStatus {
    case enabled
    case disabled
    case needsAction
    case unknown

    var title: String {
        switch self {
        case .enabled:
            return "已开启"
        case .disabled:
            return "未开启"
        case .needsAction:
            return "需开启"
        case .unknown:
            return "待确认"
        }
    }

    var isReady: Bool {
        self == .enabled
    }
}
