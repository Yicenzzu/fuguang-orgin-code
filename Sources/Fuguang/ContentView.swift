import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ShortcutStore
    @EnvironmentObject private var hotKeys: GlobalHotKeyManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("backgroundAppearance") private var backgroundAppearanceRawValue = BackgroundAppearance.automatic.rawValue
    @State private var selectedKey = ""
    @State private var editingKey: String?
    @State private var preferredKind: ShortcutActionKind?
    @State private var isDetailPanelShown = false

    var body: some View {
        ZStack {
            glassBackground
                .ignoresSafeArea()

            if editingKey != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeMenus()
                    }
                    .zIndex(1)
            }

            mainPanel
                .frame(minWidth: 1000, minHeight: 500)
                .padding(.horizontal, 20)
                .padding(.vertical, 1)
                .zIndex(2)
        }
        .animation(.easeInOut(duration: 0.18), value: resolvedIsDarkBackground)
        .background {
            KeyEventMonitor { key in
                handleKeyDown(key)
            } onEscape: {
                closeMenus()
            }
            .frame(width: 0, height: 0)
        }
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .contentShape(Rectangle())
                .onTapGesture {
                    closeMenus()
                }
                .frame(height: 48)

            Spacer().frame(height: 2)

            KeyboardView(selectedKey: $selectedKey) { key in
                if editingKey == key {
                    closeMenus()
                } else {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        selectedKey = key
                        editingKey = key
                        preferredKind = nil
                        isDetailPanelShown = false
                    }
                }
            } onConfigure: { key, kind in
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    selectedKey = key
                    editingKey = key
                    preferredKind = kind
                    isDetailPanelShown = kind != nil
                }
            } onBackgroundTap: {
                closeMenus()
            }
        }
        .padding(.horizontal, 24)
        .contentShape(RoundedRectangle(cornerRadius: 100, style: .continuous))
        .overlayPreferenceValue(KeyBoundsPreferenceKey.self) { preferences in
            GeometryReader { proxy in
                if let editingKey, let anchor = preferences[editingKey] {
                    inlineConfigurationPanel(for: editingKey, keyFrame: proxy[anchor], containerSize: proxy.size)
                }
            }
        }
    }

    private func closeMenus() {
        guard editingKey != nil else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            editingKey = nil
            isDetailPanelShown = false
            selectedKey = ""
        }
    }

    private func handleKeyDown(_ key: String) {
        guard editingKey == nil else { return }
        guard KeyboardLayout.keys.contains(key) else { return }

        let binding = store.binding(for: key)
        guard binding.isConfigured else { return }

        ActionRunner.run(binding, store: store)
        if binding.kind != .screenshot {
            AppWindowController.hideMainWindow()
        }
    }

    private func inlineConfigurationPanel(for key: String, keyFrame: CGRect, containerSize: CGSize) -> some View {
        let panelWidth: CGFloat = isDetailPanelShown ? 360 : 178
        let isConfigured = store.binding(for: key).isConfigured
        let panelHeight: CGFloat = isDetailPanelShown ? 560 : (isConfigured ? 208 : 154)
        let sideSpacing: CGFloat = 12
        let rightX = keyFrame.maxX + sideSpacing + panelWidth / 2
        let leftX = keyFrame.minX - sideSpacing - panelWidth / 2
        let prefersLeft = rightX + panelWidth / 2 > containerSize.width - 18
        let rawX = prefersLeft ? leftX : rightX
        let x = min(max(rawX, panelWidth / 2 + 18), containerSize.width - panelWidth / 2 - 18)
        let y = min(max(keyFrame.midY, panelHeight / 2 + 18), containerSize.height - panelHeight / 2 - 18)

        return KeyConfigurationView(
            key: key,
            preferredKind: $preferredKind,
            onClose: {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                    editingKey = nil
                    isDetailPanelShown = false
                    selectedKey = ""
                }
            },
            onDetailVisibilityChange: { isVisible in
                withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                    isDetailPanelShown = isVisible
                }
            }
        )
        .frame(width: panelWidth, height: panelHeight)
        .position(x: x, y: y)
        .transition(.scale(scale: 0.94, anchor: prefersLeft ? .trailing : .leading).combined(with: .opacity))
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: key)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isDetailPanelShown)
        .zIndex(10)
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                Text("浮光")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("一切都很快")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .cyan.opacity(0.95), .white.opacity(0.70)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .cyan.opacity(0.35), radius: 7, y: 2)
            }

            Spacer()

            Button {
                AppWindowController.hideMainWindow()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white.opacity(0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)
        }
        .padding(.leading, 8)
    }

    private var backgroundAppearance: BackgroundAppearance {
        BackgroundAppearance(rawValue: backgroundAppearanceRawValue) ?? .automatic
    }

    private var resolvedIsDarkBackground: Bool {
        switch backgroundAppearance {
        case .automatic:
            return colorScheme == .dark
        case .light:
            return false
        case .dark:
            return true
        }
    }

    private var glassBackground: some View {
        ZStack {
            FrostedGlassView(material: resolvedIsDarkBackground ? .hudWindow : .underWindowBackground)

            LinearGradient(
                colors: resolvedIsDarkBackground
                    ? [
                        Color(red: 0.03, green: 0.16, blue: 0.26).opacity(0.30),
                        Color(red: 0.02, green: 0.04, blue: 0.10).opacity(0.26),
                        Color(red: 0.16, green: 0.18, blue: 0.20).opacity(0.18)
                    ]
                    : [
                        Color(red: 0.82, green: 0.93, blue: 1.00).opacity(0.24),
                        Color(red: 1.00, green: 1.00, blue: 1.00).opacity(0.18),
                        Color(red: 0.72, green: 0.84, blue: 0.96).opacity(0.16)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

}

private struct KeyEventMonitor: NSViewRepresentable {
    let onKeyDown: (String) -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitor()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
        context.coordinator.onEscape = onEscape
        context.coordinator.installMonitor()
    }

    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown, onEscape: onEscape)
    }

    final class Coordinator {
        var onKeyDown: (String) -> Void
        var onEscape: () -> Void
        private var monitor: Any?

        init(onKeyDown: @escaping (String) -> Void, onEscape: @escaping () -> Void) {
            self.onKeyDown = onKeyDown
            self.onEscape = onEscape
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            if event.window?.contentView is ScreenshotOverlayView {
                return event
            }

            if event.keyCode == 53 {
                onEscape()
                return nil
            }

            guard
                event.modifierFlags.intersection([.command, .option, .control]) == [],
                let characters = event.charactersIgnoringModifiers?.uppercased(),
                let character = characters.first
            else {
                return event
            }

            onKeyDown(String(character))
            return event
        }

        func removeMonitor() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
