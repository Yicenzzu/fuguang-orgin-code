import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct KeyConfigurationView: View {
    @EnvironmentObject private var store: ShortcutStore
    let key: String
    @Binding var preferredKind: ShortcutActionKind?
    var onClose: () -> Void = {}
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }

    @State private var draftKind: ShortcutActionKind = .none
    @State private var draftTitle = ""
    @State private var draftTarget = ""
    @State private var appSearchText = ""
    @State private var folderSearchText = ""
    @State private var availableApplications: [ApplicationCandidate] = []
    @State private var isLoadingApplications = false
    @State private var didLoadApplications = false
    @State private var selectedSection: ShortcutMenuSection?

    var body: some View {
        panelContent
            .padding(selectedSection == nil ? 8 : 16)
            .background {
                panelBackground
            }
            .onAppear {
                syncFromStore()
                onDetailVisibilityChange(selectedSection != nil)
            }
            .onChange(of: key) { _, _ in
                syncFromStore()
                selectedSection = nil
                onDetailVisibilityChange(false)
            }
            .onChange(of: preferredKind) { _, newValue in
                guard let newValue else { return }
                draftKind = newValue
                selectedSection = ShortcutMenuSection(kind: newValue)
                if !newValue.requiresTarget {
                    draftTarget = ""
                }
                preferredKind = nil
            }
            .onChange(of: selectedSection) { _, newValue in
                onDetailVisibilityChange(newValue != nil)
                if newValue == .application {
                    Task { @MainActor in
                        await Task.yield()
                        loadApplicationsIfNeeded()
                    }
                }
            }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: selectedSection == nil ? 0 : 18) {
            if let selectedSection {
                detailHeader
                detailMenu(for: selectedSection)
            } else {
                primaryMenu
            }

            detailFooter
        }
    }

    private var panelBackground: some View {
        let cornerRadius: CGFloat = selectedSection == nil ? 12 : 20

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(selectedSection == nil ? 0.18 : 0.22))
            }
            .shadow(color: Color.black.opacity(0.20), radius: 16, y: 8)
    }

    @ViewBuilder
    private var detailFooter: some View {
        let binding = store.binding(for: key)

        if selectedSection == nil, binding.isConfigured {
            Divider()
                .overlay(.white.opacity(0.12))
                .padding(.vertical, 6)

            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                    store.clear(key)
                    syncFromStore()
                    onClose()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 18)

                    Text("取消绑定")
                        .font(.system(size: 13, weight: .semibold))

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())
            .foregroundStyle(.red.opacity(0.92))
        } else if selectedSection != nil {
            if selectedSection == .website {
                Button {
                    save()
                    onClose()
                } label: {
                    Label("保存网页到 \(key)", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSave)
            }
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .top) {
            Label(selectedSection?.title ?? "功能", systemImage: selectedSection?.systemImage ?? "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.65))
            .help("关闭")
        }
    }

    @ViewBuilder
    private var primaryMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
                ForEach(ShortcutMenuSection.allCases) { section in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                            selectedSection = section
                            draftKind = section.defaultKind
                            draftTitle = ""
                            draftTarget = ""
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.74))
                                .frame(width: 18)

                            Text(section.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
        }
    }

    @ViewBuilder
    private func detailMenu(for section: ShortcutMenuSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch section {
            case .application:
                applicationPicker
            case .folder:
                folderPicker
            case .website:
                websiteEditor
            case .fuguang:
                fuguangActionPicker
            }
        }
    }

    private var canSave: Bool {
        switch draftKind {
        case .none:
            return true
        case .openApplication:
            return !draftTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openFolder:
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: draftTarget, isDirectory: &isDirectory) && isDirectory.boolValue
        case .openWebsite:
            return ActionRunner.normalizedURL(from: draftTarget) != nil
        case .imageQuickLook:
            return FileManager.default.fileExists(atPath: draftTarget)
        case .showDesktop, .screenshot, .imageResize, .clipboard, .lockScreen:
            return true
        }
    }

    private var currentDraftBinding: ShortcutBinding {
        ShortcutBinding(
            key: key,
            kind: draftKind,
            title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            target: draftTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func darkTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
    }

    private var applicationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                darkTextField("搜索应用", text: $appSearchText)

                Button {
                    chooseApplication()
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 30, height: 30)
                }
                .help("手动选择应用")
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    if isLoadingApplications {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)

                            Text("正在载入应用")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                    } else {
                        ForEach(filteredApplications) { app in
                            Button {
                                saveBinding(kind: .openApplication, title: app.name, target: app.url.path)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(nsImage: app.icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)

                                    Text(app.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .lineLimit(1)

                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 38)
                            }
                            .buttonStyle(GlassPressButtonStyle())
                        }
                    }
                }
            }
            .frame(maxHeight: 178)
        }
    }

    private var filteredApplications: [ApplicationCandidate] {
        let query = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableApplications }
        return availableApplications.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var folderPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                darkTextField("搜索文件夹", text: $folderSearchText)

                Button {
                    chooseDirectory()
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 30, height: 30)
                }
                .help("选择文件夹")
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredFolders) { folder in
                        selectableRow(
                            title: folder.name,
                            subtitle: folder.url.path,
                            systemImage: "folder"
                        ) {
                            saveBinding(kind: .openFolder, title: folder.name, target: folder.url.path)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private var filteredFolders: [FolderCandidate] {
        let query = folderSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return commonFolders }
        return commonFolders.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.url.path.localizedCaseInsensitiveContains(query)
        }
    }

    private var websiteEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            darkTextField("输入网页地址或搜索词", text: $draftTarget)
            darkTextField("显示名称，可不填", text: $draftTitle)

            Text("例如 github.com、https://apple.com，保存时会自动补全 https://")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
        }
    }

    private var fuguangActionPicker: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(ShortcutActionKind.fuguangActions) { kind in
                    fuguangActionRow(kind)
                }
            }
        }
        .frame(maxHeight: 220)
    }

    private func fuguangActionRow(_ kind: ShortcutActionKind) -> some View {
        Button {
            saveBinding(kind: kind, title: kind.title, target: "")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)

                    Text(kind.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    private func selectableRow(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    private func syncFromStore() {
        let binding = store.binding(for: key)
        draftKind = binding.kind
        draftTitle = binding.title
        draftTarget = binding.target
    }

    private func save() {
        if draftKind == .none {
            store.clear(key)
        } else {
            store.save(currentDraftBinding)
        }
    }

    private func saveBinding(kind: ShortcutActionKind, title: String, target: String) {
        draftKind = kind
        draftTitle = title
        draftTarget = target
        store.save(
            ShortcutBinding(
                key: key,
                kind: kind,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                target: target.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        onClose()
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择要启动的应用"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        if panel.runModal() == .OK, let url = panel.url {
            saveBinding(kind: .openApplication, title: url.deletingPathExtension().lastPathComponent, target: url.path)
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择要打开的文件夹"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK, let url = panel.url {
            saveBinding(kind: .openFolder, title: url.lastPathComponent, target: url.path)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "选择图片"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        if panel.runModal() == .OK, let url = panel.url {
            saveBinding(kind: .imageQuickLook, title: url.deletingPathExtension().lastPathComponent, target: url.path)
        }
    }

    private func loadApplicationsIfNeeded() {
        guard !didLoadApplications, !isLoadingApplications else { return }
        isLoadingApplications = true

        Task.detached(priority: .userInitiated) {
            let candidates = Self.scanApplications()

            await MainActor.run {
                availableApplications = candidates
                didLoadApplications = true
                isLoadingApplications = false
            }
        }
    }

    nonisolated private static func scanApplications() -> [ApplicationCandidate] {
        let applicationDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
        ]

        var seen = Set<String>()
        var candidates: [ApplicationCandidate] = []

        for directory in applicationDirectories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey, .localizedNameKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app", !seen.contains(url.path) else { continue }
                enumerator.skipDescendants()
                seen.insert(url.path)
                let resourceValues = try? url.resourceValues(forKeys: [.localizedNameKey])
                let rawName = resourceValues?.localizedName ?? url.deletingPathExtension().lastPathComponent
                let name = rawName.hasSuffix(".app") ? String(rawName.dropLast(4)) : rawName
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 24, height: 24)
                candidates.append(ApplicationCandidate(name: name, url: url, icon: icon))
            }
        }

        return candidates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private enum ShortcutMenuSection: String, CaseIterable, Identifiable {
    case application
    case folder
    case website
    case fuguang

    var id: String { rawValue }

    init?(kind: ShortcutActionKind) {
        switch kind {
        case .openApplication:
            self = .application
        case .openFolder:
            self = .folder
        case .openWebsite:
            self = .website
        case .showDesktop, .screenshot, .imageResize, .imageQuickLook, .clipboard, .lockScreen:
            self = .fuguang
        case .none:
            return nil
        }
    }

    var title: String {
        switch self {
        case .application:
            return "应用"
        case .folder:
            return "文件夹"
        case .website:
            return "网页"
        case .fuguang:
            return "浮光操作"
        }
    }

    var subtitle: String {
        switch self {
        case .application:
            return "搜索并绑定具体应用"
        case .folder:
            return "选择常用文件夹"
        case .website:
            return "输入具体网页地址"
        case .fuguang:
            return "选择截图、改图等功能"
        }
    }

    var systemImage: String {
        switch self {
        case .application:
            return "app.dashed"
        case .folder:
            return "folder"
        case .website:
            return "globe"
        case .fuguang:
            return "switch.2"
        }
    }

    var defaultKind: ShortcutActionKind {
        switch self {
        case .application:
            return .openApplication
        case .folder:
            return .openFolder
        case .website:
            return .openWebsite
        case .fuguang:
            return .showDesktop
        }
    }
}

private struct ApplicationCandidate: Identifiable, @unchecked Sendable {
    let name: String
    let url: URL
    let icon: NSImage

    var id: String { url.path }
}

private struct FolderCandidate: Identifiable {
    let name: String
    let url: URL

    var id: String { url.path }
}

private struct GlassPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AnimatedGlassRow(configuration: configuration)
    }
}

private struct AnimatedGlassRow: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovering ? Color.white.opacity(0.10) : Color.white.opacity(0.001))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isHovering ? Color.white.opacity(0.16) : Color.clear, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.965 : (isHovering ? 1.018 : 1.0))
            .brightness(configuration.isPressed ? 0.08 : (isHovering ? 0.04 : 0))
            .shadow(color: .black.opacity(isHovering ? 0.16 : 0), radius: 8, y: 4)
            .animation(.spring(response: 0.20, dampingFraction: 0.74), value: configuration.isPressed)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

private extension KeyConfigurationView {
    var commonFolders: [FolderCandidate] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let urls = [
            home,
            home.appending(path: "Desktop", directoryHint: .isDirectory),
            home.appending(path: "Documents", directoryHint: .isDirectory),
            home.appending(path: "Downloads", directoryHint: .isDirectory),
            home.appending(path: "Pictures", directoryHint: .isDirectory),
            home.appending(path: "Movies", directoryHint: .isDirectory),
            URL(fileURLWithPath: "/Applications", isDirectory: true)
        ]

        return urls
            .filter { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
            .map { FolderCandidate(name: $0.lastPathComponent.isEmpty ? "个人目录" : $0.lastPathComponent, url: $0) }
    }
}
