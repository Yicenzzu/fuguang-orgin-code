import Foundation

@MainActor
final class ShortcutStore: ObservableObject {
    @Published private(set) var bindings: [String: ShortcutBinding] = [:]
    @Published var lastMessage: String?

    private let storageURL: URL

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = baseURL.appending(path: "Fuguang", directoryHint: .isDirectory)
        storageURL = directoryURL.appending(path: "bindings.json")
        load()
    }

    func binding(for key: String) -> ShortcutBinding {
        bindings[key] ?? .empty(key: key)
    }

    func save(_ binding: ShortcutBinding) {
        bindings[binding.key] = binding
        persist()
        lastMessage = "\(binding.key) 已保存"
    }

    func clear(_ key: String) {
        bindings[key] = .empty(key: key)
        persist()
        lastMessage = "\(key) 已清除"
    }

    func configuredBindings() -> [ShortcutBinding] {
        KeyboardLayout.letters
            .map { binding(for: $0) }
            .filter(\.isConfigured)
    }

    private func load() {
        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode([String: ShortcutBinding].self, from: data)
            bindings = decoded
        } catch {
            bindings = Dictionary(uniqueKeysWithValues: KeyboardLayout.letters.map { ($0, ShortcutBinding.empty(key: $0)) })
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.pretty.encode(bindings)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            lastMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
