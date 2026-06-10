import SwiftUI

struct PermissionStatusView: View {
    @ObservedObject var manager: PermissionManager
    let onClose: () -> Void
    @State private var selectedGuide: PermissionGuide?

    init(initialGuide: PermissionGuide? = nil, manager: PermissionManager, onClose: @escaping () -> Void) {
        self.manager = manager
        self.onClose = onClose
        _selectedGuide = State(initialValue: initialGuide)
    }

    var body: some View {
        content
            .frame(width: PermissionStatusLayout.baseSize.width, height: PermissionStatusLayout.baseSize.height)
            .scaleEffect(PermissionStatusLayout.scale)
            .frame(width: PermissionStatusLayout.scaledSize.width, height: PermissionStatusLayout.scaledSize.height)
            .onAppear {
                manager.refresh()
            }
    }

    private var content: some View {
        ZStack {
            background

            if let selectedGuide {
                PermissionGuideView(
                    guide: selectedGuide,
                    manager: manager,
                    onBack: {
                        returnToList()
                    },
                    onRefresh: {
                        manager.refreshAfterUserAction()
                        returnToList()
                    },
                    onClose: onClose
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            } else {
                permissionList
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: selectedGuide)
    }

    private var permissionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Spacer().frame(height: 42)

            VStack(spacing: 17) {
                PermissionStatusRow(
                    icon: .system("figure.wave"),
                    iconColor: Color(red: 0.23, green: 0.78, blue: 0.58),
                    title: "辅助功能",
                    subtitle: "用于让浮光响应全局快捷动作。",
                    statusText: manager.accessibilityStatus.title,
                    statusColor: manager.accessibilityStatus.isReady ? PermissionPalette.primaryText.opacity(0.72) : .blue,
                    actionTitle: "管理",
                    actionIcon: "slider.horizontal.3",
                    isActionDisabled: false,
                    action: { showGuide(.accessibility) }
                )

                PermissionStatusRow(
                    icon: .system("keyboard"),
                    iconColor: Color(red: 0.20, green: 0.82, blue: 0.56),
                    title: "输入监控",
                    subtitle: "用于识别 Control 单击和全局快捷键。",
                    statusText: manager.inputMonitoringStatus.title,
                    statusColor: manager.inputMonitoringStatus.isReady ? PermissionPalette.primaryText.opacity(0.72) : .blue,
                    actionTitle: "管理",
                    actionIcon: "slider.horizontal.3",
                    isActionDisabled: false,
                    action: { showGuide(.inputMonitoring) }
                )

                PermissionStatusRow(
                    icon: .dashedRectangle,
                    iconColor: Color(red: 0.23, green: 0.80, blue: 0.57),
                    title: "屏幕与系统音频录制",
                    subtitle: "用于截图选区、窗口预览和截图标注。",
                    statusText: manager.screenRecordingStatus.title,
                    statusColor: manager.screenRecordingStatus.isReady ? PermissionPalette.primaryText.opacity(0.72) : .blue,
                    actionTitle: "管理",
                    actionIcon: "slider.horizontal.3",
                    isActionDisabled: false,
                    action: { showGuide(.screenRecording) }
                )

                PermissionStatusRow(
                    icon: .system("power"),
                    iconColor: Color(red: 0.22, green: 0.80, blue: 0.58),
                    title: "开机启动",
                    subtitle: "让浮光开机后自动待命。",
                    statusText: manager.loginItemStatus.title,
                    statusColor: manager.loginItemStatus.isReady ? PermissionPalette.primaryText.opacity(0.72) : .blue,
                    actionTitle: manager.loginItemStatus.isReady ? "关闭" : "开启",
                    actionIcon: "power",
                    isActionDisabled: false,
                    action: { showGuide(.loginItem) }
                )

                PermissionStatusRow(
                    icon: .system("doc.on.clipboard"),
                    iconColor: Color(red: 0.39, green: 0.55, blue: 1.00),
                    title: "剪贴板访问",
                    subtitle: "用于剪贴板历史，系统会在需要时提示。",
                    statusText: "无需预先开启",
                    statusColor: Color(red: 0.24, green: 0.53, blue: 1.00),
                    actionTitle: "无需操作",
                    actionIcon: "checkmark",
                    isActionDisabled: true,
                    action: {}
                )
            }

            if let loginItemError = manager.loginItemError {
                Text("开机启动设置失败：\(loginItemError)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.top, 14)
                    .padding(.leading, 16)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }

    private var header: some View {
        HStack(spacing: 14) {
            FuguangMark()
                .frame(width: 26, height: 26)

                Text("权限与状态")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(PermissionPalette.primaryText.opacity(0.82))

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(PermissionPalette.primaryText.opacity(0.50))
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var background: some View {
        ZStack {
            FrostedGlassView(material: .hudWindow)

            LinearGradient(
                colors: [
                    Color(red: 0.82, green: 0.91, blue: 1.00).opacity(0.34),
                    Color.white.opacity(0.24),
                    Color(red: 0.72, green: 0.78, blue: 0.86).opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func showGuide(_ guide: PermissionGuide) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            selectedGuide = guide
        }
    }

    private func returnToList() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            selectedGuide = nil
        }
    }
}

private struct PermissionGuideView: View {
    let guide: PermissionGuide
    @ObservedObject var manager: PermissionManager
    let onBack: () -> Void
    let onRefresh: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(PermissionPalette.primaryText.opacity(0.48))
                        .frame(width: 42, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(PermissionPalette.surface)
                        )
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(guide.iconColor.opacity(0.16))

                        PermissionIconView(icon: guide.icon, color: guide.iconColor, size: 24)
                    }
                    .frame(width: 42, height: 42)

                    Text(guide.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(PermissionPalette.primaryText.opacity(0.82))
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(PermissionPalette.primaryText.opacity(0.50))
                        .frame(width: 42, height: 42)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Spacer().frame(height: 50)

            VStack(spacing: 17) {
                PermissionGuideStep(
                    number: 1,
                    title: guide.openSettingsTitle,
                    subtitle: guide.openSettingsSubtitle,
                    trailing: .button(title: guide.primaryButtonTitle, icon: guide.primaryButtonIcon) {
                        guide.performPrimaryAction(manager)
                    }
                )

                if guide == .loginItem {
                    PermissionGuideStep(
                        number: 2,
                        title: guide.findAppTitle,
                        subtitle: guide.findAppSubtitle,
                        trailing: .appHint
                    )
                } else {
                    PermissionGuideStep(
                        number: 2,
                        title: guide.findAppTitle,
                        subtitle: guide.findAppSubtitle,
                        trailing: .button(title: guide.addButtonTitle, icon: "plus") {
                            guide.addToPermissionList(manager)
                        }
                    )
                }

                PermissionGuideStep(
                    number: 3,
                    title: guide.finishTitle,
                    subtitle: guide.finishSubtitle,
                    trailing: .button(title: "重新检测", icon: "arrow.clockwise") {
                        onRefresh()
                    }
                )
            }

            if guide == .loginItem, let loginItemError = manager.loginItemError {
                Text("开机启动设置失败：\(loginItemError)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.top, 14)
                    .padding(.leading, 16)
            }

            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 22)
        .padding(.bottom, 28)
    }
}

private struct PermissionGuideStep: View {
    let number: Int
    let title: String
    let subtitle: String
    let trailing: PermissionGuideTrailing

    var body: some View {
        HStack(spacing: 17) {
            Text("\(number)")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(red: 0.12, green: 0.70, blue: 0.96)))

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(PermissionPalette.primaryText.opacity(0.78))

                Text(subtitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PermissionPalette.primaryText.opacity(0.50))
                    .lineLimit(2)
            }

            Spacer(minLength: 18)

            trailingView
        }
        .padding(.horizontal, 15)
        .frame(height: 118)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PermissionPalette.surface)
        )
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case let .button(title, icon, action):
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))

                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(width: 168, height: 42)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.21, green: 0.50, blue: 1.00),
                            Color(red: 0.12, green: 0.78, blue: 0.82)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .buttonStyle(.plain)

        case .appHint:
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(PermissionPalette.surface)
                        .frame(width: 98, height: 98)

                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(.white.opacity(0.78))
                        .frame(width: 58, height: 58)

                    FuguangMark()
                        .frame(width: 38, height: 38)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(PermissionPalette.primaryText.opacity(0.55))

                    Text("找到浮光")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(PermissionPalette.primaryText.opacity(0.62))

                    Text("在列表中打开")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PermissionPalette.primaryText.opacity(0.42))
                }
            }
            .frame(width: 238, alignment: .trailing)
        }
    }
}

private enum PermissionGuideTrailing {
    case button(title: String, icon: String, action: () -> Void)
    case appHint
}

enum PermissionGuide: Equatable {
    case accessibility
    case inputMonitoring
    case screenRecording
    case loginItem

    var title: String {
        switch self {
        case .accessibility:
            return "开启辅助功能"
        case .inputMonitoring:
            return "开启输入监控"
        case .screenRecording:
            return "开启屏幕录制"
        case .loginItem:
            return "开启开机启动"
        }
    }

    var icon: PermissionIcon {
        switch self {
        case .accessibility:
            return .system("figure.wave")
        case .inputMonitoring:
            return .system("keyboard")
        case .screenRecording:
            return .dashedRectangle
        case .loginItem:
            return .system("power")
        }
    }

    var iconColor: Color {
        switch self {
        case .accessibility, .inputMonitoring, .screenRecording, .loginItem:
            return Color(red: 0.22, green: 0.80, blue: 0.58)
        }
    }

    var openSettingsTitle: String {
        switch self {
        case .loginItem:
            return "开启开机启动"
        default:
            return "打开系统设置"
        }
    }

    var openSettingsSubtitle: String {
        switch self {
        case .accessibility:
            return "进入系统设置里的辅助功能。"
        case .inputMonitoring:
            return "进入系统设置里的输入监控。"
        case .screenRecording:
            return "进入系统设置里的屏幕录制。"
        case .loginItem:
            return "允许浮光登录时自动打开。"
        }
    }

    var findAppTitle: String {
        switch self {
        case .loginItem:
            return "确认浮光已加入"
        default:
            return "添加浮光"
        }
    }

    var findAppSubtitle: String {
        switch self {
        case .loginItem:
            return "如果系统要求确认，请在登录项列表中允许浮光。"
        default:
            return "点击右侧按钮，只把浮光加入当前这一项权限列表。"
        }
    }

    var addButtonTitle: String {
        switch self {
        case .accessibility:
            return "添加到辅助功能"
        case .inputMonitoring:
            return "添加到输入监控"
        case .screenRecording:
            return "添加到屏幕录制"
        case .loginItem:
            return "添加到登录项"
        }
    }

    var finishTitle: String {
        switch self {
        case .loginItem:
            return "确认状态"
        default:
            return "打开开关"
        }
    }

    var finishSubtitle: String {
        switch self {
        case .loginItem:
            return "回到浮光后重新检测开机启动状态。"
        default:
            return "允许后回到浮光，重新检测状态。"
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .loginItem:
            return "开启"
        default:
            return "打开系统设置"
        }
    }

    var primaryButtonIcon: String {
        switch self {
        case .loginItem:
            return "power"
        default:
            return "gearshape"
        }
    }

    @MainActor
    func performPrimaryAction(_ manager: PermissionManager) {
        switch self {
        case .accessibility:
            manager.manageAccessibility()
        case .inputMonitoring:
            manager.manageInputMonitoring()
        case .screenRecording:
            manager.manageScreenRecording()
        case .loginItem:
            if manager.loginItemStatus.isReady {
                manager.openLoginItemSettings()
            } else {
                manager.toggleLoginItem()
            }
        }
    }

    @MainActor
    func addToPermissionList(_ manager: PermissionManager) {
        switch self {
        case .accessibility:
            manager.addAccessibilityToPermissionList()
        case .inputMonitoring:
            manager.addInputMonitoringToPermissionList()
        case .screenRecording:
            manager.addScreenRecordingToPermissionList()
        case .loginItem:
            manager.toggleLoginItem()
        }
    }
}

enum PermissionStatusLayout {
    static let scale: CGFloat = 0.8
    static let baseSize = NSSize(width: 884, height: 608)
    static let scaledSize = NSSize(width: baseSize.width * scale, height: baseSize.height * scale)
}

private enum PermissionPalette {
    static let primaryText = Color.black
    static let surface = Color.black.opacity(0.045)
}

private struct PermissionStatusRow: View {
    let icon: PermissionIcon
    let iconColor: Color
    let title: String
    let subtitle: String
    let statusText: String
    let statusColor: Color
    let actionTitle: String
    let actionIcon: String
    let isActionDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 17) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.16))

                PermissionIconView(icon: icon, color: iconColor, size: 24)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(PermissionPalette.primaryText.opacity(0.78))

                Text(subtitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PermissionPalette.primaryText.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer(minLength: 18)

            Text(statusText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .frame(minWidth: 104, alignment: .trailing)

            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 15, weight: .bold))
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(PermissionPalette.primaryText.opacity(isActionDisabled ? 0.38 : 0.74))
                .frame(width: 136, height: 38)
                .background(
                    Capsule(style: .continuous)
                        .fill(PermissionPalette.surface)
                )
            }
            .buttonStyle(.plain)
            .disabled(isActionDisabled)
        }
        .padding(.horizontal, 14)
        .frame(height: 71)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(PermissionPalette.surface)
        )
    }
}

enum PermissionIcon: Equatable {
    case system(String)
    case dashedRectangle
}

private struct PermissionIconView: View {
    let icon: PermissionIcon
    let color: Color
    let size: CGFloat

    var body: some View {
        switch icon {
        case let .system(name):
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)

        case .dashedRectangle:
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: max(2, size * 0.12), lineCap: .round, dash: [size * 0.22, size * 0.16])
                )
                .frame(width: size * 1.05, height: size * 0.74)
        }
    }
}

private struct FuguangMark: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            CurvedShard()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.57, green: 0.76, blue: 1.00),
                            Color(red: 0.84, green: 0.69, blue: 1.00)
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .frame(width: 24, height: 12)
                .rotationEffect(.degrees(-12))
                .offset(x: 2, y: 1)

            CurvedShard()
                .fill(Color(red: 0.42, green: 0.58, blue: 1.00).opacity(0.70))
                .frame(width: 15, height: 7)
                .rotationEffect(.degrees(-32))
                .offset(x: 2, y: 14)
        }
    }
}

private struct CurvedShard: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.78))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.width * 0.22, y: rect.height * 0.30),
            control2: CGPoint(x: rect.width * 0.70, y: rect.height * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.88),
            control1: CGPoint(x: rect.width * 0.92, y: rect.height * 0.58),
            control2: CGPoint(x: rect.width * 0.84, y: rect.height * 0.80)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY * 0.78),
            control1: CGPoint(x: rect.width * 0.44, y: rect.height * 0.70),
            control2: CGPoint(x: rect.width * 0.20, y: rect.height * 0.72)
        )
        return path
    }
}
