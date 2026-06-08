import AppKit
import SwiftUI

struct KeyboardView: View {
    @EnvironmentObject private var store: ShortcutStore
    @Binding var selectedKey: String
    @State private var hoveredKey: String?
    var onSelect: (String) -> Void = { _ in }
    var onConfigure: (String, ShortcutActionKind?) -> Void = { _, _ in }
    var onBackgroundTap: () -> Void = {}

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    onBackgroundTap()
                }

            VStack(spacing: 13) {
                ForEach(Array(KeyboardLayout.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 11) {
                        if index == 2 {
                            Spacer().frame(width: 30)
                        } else if index == 3 {
                            Spacer().frame(width: 68)
                        }

                        ForEach(row, id: \.self) { key in
                            KeyCapView(
                                binding: store.binding(for: key),
                                isSelected: selectedKey == key,
                                isHovered: hoveredKey == key
                            )
                            .onHover { isHovered in
                                hoveredKey = isHovered ? key : (hoveredKey == key ? nil : hoveredKey)
                            }
                            .onTapGesture {
                                selectedKey = key
                                onSelect(key)
                            }
                            .anchorPreference(key: KeyBoundsPreferenceKey.self, value: .bounds) { anchor in
                                [key: anchor]
                            }
                            .contextMenu {
                                Button {
                                    onConfigure(key, .openApplication)
                                } label: {
                                    Label("应用", systemImage: ShortcutActionKind.openApplication.systemImage)
                                }

                                Button {
                                    onConfigure(key, .openFolder)
                                } label: {
                                    Label("文件夹", systemImage: ShortcutActionKind.openFolder.systemImage)
                                }

                                Button {
                                    onConfigure(key, .openWebsite)
                                } label: {
                                    Label("网页", systemImage: ShortcutActionKind.openWebsite.systemImage)
                                }

                                Divider()

                                Menu("浮光操作") {
                                    ForEach([ShortcutActionKind.screenshot, .imageResize, .imageQuickLook, .clipboard, .lockScreen]) { kind in
                                        Button {
                                            onConfigure(key, kind)
                                        } label: {
                                            Label(kind.title, systemImage: kind.systemImage)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 22)
    }
}

struct KeyBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct KeyCapView: View {
    let binding: ShortcutBinding
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            keyContent
                .padding(9)

            if binding.isConfigured {
                Text(binding.key)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.trailing, 7)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: 68, height: 63)
        .scaleEffect(isSelected ? 1.055 : (isHovered ? 1.045 : 1.0))
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(background)
                }
                .shadow(color: .black.opacity(isSelected || isHovered ? 0.42 : 0.28), radius: isSelected || isHovered ? 16 : 8, y: 7)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(border, lineWidth: isSelected ? 1.3 : 0.9)
                }
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isSelected)
        .animation(.spring(response: 0.20, dampingFraction: 0.76), value: isHovered)
        .animation(.easeOut(duration: 0.16), value: binding)
    }

    @ViewBuilder
    private var keyContent: some View {
        if binding.isConfigured {
            configuredKeyContent
        } else {
            VStack(spacing: 6) {
                keyIcon
                    .frame(width: 27, height: 27)

                Text(binding.key)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var configuredKeyContent: some View {
        if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 37, height: 37)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if showsTitleInsideIcon {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.10))
                    .frame(width: 48, height: 38)

                Image(systemName: binding.kind.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.20))

                Text(binding.displayTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.52)
                    .frame(width: 46, height: 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            Image(systemName: binding.kind.systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var background: Color {
        if isSelected || isHovered {
            return Color.white.opacity(0.17)
        }

        return binding.isConfigured
            ? Color.cyan.opacity(0.16)
            : Color.white.opacity(0.08)
    }

    private var border: Color {
        if isSelected || isHovered {
            return .white.opacity(0.35)
        }

        return binding.isConfigured ? .cyan.opacity(0.38) : .white.opacity(0.08)
    }

    private var iconColor: Color {
        binding.isConfigured ? .white : .white.opacity(0.22)
    }

    private var showsTitleInsideIcon: Bool {
        binding.kind == .openFolder || binding.kind == .openWebsite
    }

    @ViewBuilder
    private var keyIcon: some View {
        if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        } else {
            Image(systemName: binding.kind.systemImage)
                .font(.system(size: binding.isConfigured ? 24 : 17, weight: .semibold))
                .foregroundStyle(iconColor)
        }
    }

    private var appIcon: NSImage? {
        guard binding.kind == .openApplication, binding.isConfigured else { return nil }
        guard FileManager.default.fileExists(atPath: binding.target) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: binding.target)
        icon.size = NSSize(width: 37, height: 37)
        return icon
    }
}
