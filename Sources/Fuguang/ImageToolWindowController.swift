import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ImageToolWindowController {
    static let shared = ImageToolWindowController()

    private var window: NSWindow?

    func show(store: ShortcutStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = ImageToolView()
            .environmentObject(store)
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "浮光改图"
        window.minSize = NSSize(width: 980, height: 620)
        window.maxSize = NSSize(width: 980, height: 620)
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct ImageToolView: View {
    @EnvironmentObject private var store: ShortcutStore
    @State private var imageURLs: [URL] = []
    @State private var outputDirectory: URL?
    @State private var maxWidth = "1600"
    @State private var maxHeight = "1600"
    @State private var quality = 0.82
    @State private var format: OutputImageFormat = .jpeg
    @State private var isExporting = false
    @State private var resultText = "添加图片后开始批量处理"
    @State private var selectedImageURL: URL?

    var body: some View {
        HStack(spacing: 0) {
            previewPane
                .frame(width: 640)

            Divider()

            controlPane
                .frame(width: 339)
        }
        .frame(width: 980, height: 620)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("预览")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                Button {
                    chooseImages()
                } label: {
                    Label("添加图片", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    imageURLs.removeAll()
                    selectedImageURL = nil
                } label: {
                    Image(systemName: "trash")
                }
                .help("清空")
                .disabled(imageURLs.isEmpty)
            }
            .padding(18)

            Divider()

            if let selectedImageURL, let image = NSImage(contentsOf: selectedImageURL) {
                VStack(spacing: 14) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 560, maxHeight: 390)
                        .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(selectedImageURL.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("还没有图片", systemImage: "photo.stack", description: Text("添加图片后会在这里显示预览。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(imageURLs, id: \.path) { url in
                        thumbnailButton(for: url)
                    }
                }
                .padding(14)
            }
            .frame(height: 92)
        }
    }

    private var controlPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("功能区")
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    chooseOutputDirectory()
                } label: {
                    Label(outputDirectory?.lastPathComponent ?? "选择输出目录", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("尺寸")
                    .font(.headline)

                HStack {
                    TextField("最大宽度", text: $maxWidth)
                    Text("x")
                    TextField("最大高度", text: $maxHeight)
                }
                .textFieldStyle(.roundedBorder)

                Text("按比例缩放，不会放大小图。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("输出")
                    .font(.headline)

                Picker("格式", selection: $format) {
                    ForEach(OutputImageFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("质量")
                        Spacer()
                        Text("\(Int(quality * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $quality, in: 0.35...1.0)
                        .disabled(format == .png)
                }
            }

            Spacer()

            Text(resultText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button {
                exportImages()
            } label: {
                Label(isExporting ? "处理中" : "批量导出", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(imageURLs.isEmpty || outputDirectory == nil || isExporting)
        }
            .padding(22)
    }

    private func thumbnailButton(for url: URL) -> some View {
        Button {
            selectedImageURL = url
        } label: {
            VStack(spacing: 6) {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 44)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .frame(width: 58, height: 44)
                }

                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: 70)
            }
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(
            selectedImageURL == url ? Color.accentColor.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.title = "选择图片"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        if panel.runModal() == .OK {
            let existing = Set(imageURLs.map(\.path))
            let newURLs = panel.urls.filter { !existing.contains($0.path) }
            imageURLs.append(contentsOf: newURLs)
            if selectedImageURL == nil {
                selectedImageURL = newURLs.first ?? imageURLs.first
            }
            resultText = "已添加 \(imageURLs.count) 张图片"
        }
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择输出目录"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK {
            outputDirectory = panel.url
        }
    }

    private func exportImages() {
        guard let outputDirectory else { return }
        let widthLimit = CGFloat(Double(maxWidth) ?? 0)
        let heightLimit = CGFloat(Double(maxHeight) ?? 0)
        let urls = imageURLs
        let selectedFormat = format
        let selectedQuality = quality

        isExporting = true
        resultText = "正在处理 \(urls.count) 张图片..."

        Task.detached {
            var successCount = 0

            for url in urls {
                guard let image = NSImage(contentsOf: url) else { continue }
                let resized = image.resizedToFit(maxWidth: widthLimit, maxHeight: heightLimit)
                let outputURL = outputDirectory
                    .appending(path: url.deletingPathExtension().lastPathComponent + "_fuguang")
                    .appendingPathExtension(selectedFormat.fileExtension)

                if resized.write(to: outputURL, format: selectedFormat, quality: selectedQuality) {
                    successCount += 1
                }
            }

            let message = "已导出 \(successCount)/\(urls.count) 张图片"
            await MainActor.run {
                isExporting = false
                resultText = message
                store.lastMessage = resultText
            }
        }
    }
}

private enum OutputImageFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg
    case png

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg:
            return "JPEG"
        case .png:
            return "PNG"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg:
            return "jpg"
        case .png:
            return "png"
        }
    }

    var bitmapFileType: NSBitmapImageRep.FileType {
        switch self {
        case .jpeg:
            return .jpeg
        case .png:
            return .png
        }
    }
}

private extension NSImage {
    func resizedToFit(maxWidth: CGFloat, maxHeight: CGFloat) -> NSImage {
        guard maxWidth > 0 || maxHeight > 0 else { return self }

        let widthRatio = maxWidth > 0 ? maxWidth / size.width : 1
        let heightRatio = maxHeight > 0 ? maxHeight / size.height : 1
        let ratio = min(1, widthRatio, heightRatio)
        let targetSize = NSSize(width: size.width * ratio, height: size.height * ratio)

        guard targetSize != size else { return self }

        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        image.unlockFocus()
        return image
    }

    func write(to url: URL, format: OutputImageFormat, quality: Double) -> Bool {
        guard
            let tiff = tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(
                using: format.bitmapFileType,
                properties: format == .jpeg ? [.compressionFactor: quality] : [:]
            )
        else {
            return false
        }

        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}
