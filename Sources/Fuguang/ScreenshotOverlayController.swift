import AppKit
import SwiftUI

@MainActor
final class ScreenshotOverlayController {
    static let shared = ScreenshotOverlayController()

    static var isActive = false

    private var window: NSWindow?
    private var store: ShortcutStore?

    private init() {}

    func show(store: ShortcutStore) {
        guard window == nil else { return }

        Self.isActive = true
        self.store = store

        guard let screen = NSScreen.main else {
            close()
            store.lastMessage = "截图失败：未找到屏幕"
            return
        }

        let screenFrame = screen.frame
        let primaryScreenFrame = NSScreen.screens.first?.frame ?? screenFrame
        let quartzScreenOrigin = CGPoint(
            x: screenFrame.minX,
            y: primaryScreenFrame.maxY - screenFrame.maxY
        )
        // 菜单栏高度偏移：visibleFrame.top 通常比 frame.top 小（菜单栏占用的空间）
        let menuBarHeight = screenFrame.height - screen.visibleFrame.height - (screenFrame.origin.y - screen.visibleFrame.origin.y)

        let view = ScreenshotOverlayView(
            screenSize: screenFrame.size,
            quartzScreenOrigin: quartzScreenOrigin,
            menuBarOffset: menuBarHeight,
            onSave: { [weak self] rect, annotations in
                self?.saveScreenshot(selection: rect, quartzScreenOrigin: quartzScreenOrigin, annotations: annotations)
            },
            onCopy: { [weak self] rect, annotations in
                self?.copyScreenshot(selection: rect, quartzScreenOrigin: quartzScreenOrigin, annotations: annotations)
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.identifier = AppWindowController.screenshotOverlayIdentifier
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    private func saveScreenshot(selection: CGRect, quartzScreenOrigin: CGPoint, annotations: [ScreenshotAnnotation]) {
        captureScreenshot(selection: selection, quartzScreenOrigin: quartzScreenOrigin, annotations: annotations, shouldSaveToDesktop: true)
    }

    private func copyScreenshot(selection: CGRect, quartzScreenOrigin: CGPoint, annotations: [ScreenshotAnnotation]) {
        captureScreenshot(selection: selection, quartzScreenOrigin: quartzScreenOrigin, annotations: annotations, shouldSaveToDesktop: false)
    }

    private func captureScreenshot(selection: CGRect, quartzScreenOrigin: CGPoint, annotations: [ScreenshotAnnotation], shouldSaveToDesktop: Bool) {
        // CGWindowListCreateImage 和 CGWindowListCopyWindowInfo 使用同一套 Quartz 坐标：
        // 全局原点在主屏左上角，选区是覆盖窗口内的左上角坐标，所以只需要加上当前屏幕的 Quartz 原点。
        let cgRect = CGRect(
            x: quartzScreenOrigin.x + selection.origin.x,
            y: quartzScreenOrigin.y + selection.origin.y,
            width: selection.width,
            height: selection.height
        )

        // 先隐藏截图覆盖窗口，避免截到半透明遮罩
        window?.orderOut(nil)

        // 等待窗口消失后再截图
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let cgImage = LegacyScreenshotCapture.capture(
                cgRect,
                CGWindowListOption(rawValue: 1),
                CGWindowID(0),
                .bestResolution
            ) else {
                self?.store?.lastMessage = "截图失败：无法捕获屏幕内容"
                self?.close()
                return
            }

            let outputImage = self?.renderAnnotations(annotations, on: cgImage, selection: selection) ?? cgImage
            self?.handleCapturedImage(cgImage: outputImage, shouldSaveToDesktop: shouldSaveToDesktop)
        }
    }

    private func handleCapturedImage(cgImage: CGImage, shouldSaveToDesktop: Bool) {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:])
        else {
            store?.lastMessage = "截图失败：图片编码失败"
            close()
            return
        }

        saveToClipboard(data: data)

        guard shouldSaveToDesktop else {
            store?.lastMessage = "已复制截图到粘贴板"
            close()
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "浮光截图_\(timestamp).png"

        guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            store?.lastMessage = "截图失败：无法访问桌面"
            close()
            return
        }

        do {
            let fileURL = desktopURL.appending(path: filename)
            try data.write(to: fileURL)
            store?.lastMessage = "已保存截图到桌面并复制到粘贴板"
        } catch {
            store?.lastMessage = "截图保存失败：\(error.localizedDescription)"
        }

        close()
    }

    private func renderAnnotations(_ annotations: [ScreenshotAnnotation], on image: CGImage, selection: CGRect) -> CGImage {
        let width = image.width
        let height = image.height
        let imageSize = CGSize(width: width, height: height)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

        NSImage(cgImage: image, size: imageSize).draw(in: CGRect(origin: .zero, size: imageSize))

        for annotation in annotations {
            draw(annotation, selection: selection)
        }

        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage ?? image
    }

    private func draw(_ annotation: ScreenshotAnnotation, selection: CGRect) {
        switch annotation.kind {
        case .text:
            let local = renderRect(annotation.rect, selection: selection)
            let text = NSString(string: annotation.text)
            text.draw(
                at: CGPoint(x: local.minX + 6, y: local.minY + 4),
                withAttributes: [
                    .font: NSFont.boldSystemFont(ofSize: 22),
                    .foregroundColor: annotation.color.nsColor
                ]
            )

        case .arrow:
            let s = renderPoint(annotation.start, selection: selection)
            let e = renderPoint(annotation.end, selection: selection)
            let path = NSBezierPath()
            path.move(to: s)
            path.line(to: e)
            annotation.color.nsColor.setStroke()
            path.lineWidth = 4
            path.stroke()

            let angle = atan2(e.y - s.y, e.x - s.x)
            let arrowLength: CGFloat = 14
            let arrowAngle: CGFloat = .pi / 7
            let p1 = CGPoint(x: e.x - arrowLength * cos(angle - arrowAngle), y: e.y - arrowLength * sin(angle - arrowAngle))
            let p2 = CGPoint(x: e.x - arrowLength * cos(angle + arrowAngle), y: e.y - arrowLength * sin(angle + arrowAngle))
            let head = NSBezierPath()
            head.move(to: e)
            head.line(to: p1)
            head.move(to: e)
            head.line(to: p2)
            head.lineWidth = 4
            head.stroke()

        case .rectangle:
            let local = renderRect(annotation.rect, selection: selection)
            annotation.color.nsColor.setStroke()
            let path = NSBezierPath(rect: local)
            path.lineWidth = 3
            path.stroke()

        case .oval:
            let local = renderRect(annotation.rect, selection: selection)
            annotation.color.nsColor.setStroke()
            let path = NSBezierPath(ovalIn: local)
            path.lineWidth = 3
            path.stroke()

        case .pen:
            guard let first = annotation.points.first else { return }
            let path = NSBezierPath()
            path.move(to: renderPoint(first, selection: selection))
            for point in annotation.points.dropFirst() {
                path.line(to: renderPoint(point, selection: selection))
            }
            annotation.color.nsColor.setStroke()
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

        case .mosaic:
            let local = renderRect(annotation.rect, selection: selection)
            NSColor.white.withAlphaComponent(0.38).setFill()
            NSBezierPath(rect: local).fill()
            NSColor.black.withAlphaComponent(0.18).setStroke()
            let step: CGFloat = 8
            var x = local.minX
            while x <= local.maxX {
                let path = NSBezierPath()
                path.move(to: CGPoint(x: x, y: local.minY))
                path.line(to: CGPoint(x: x, y: local.maxY))
                path.stroke()
                x += step
            }
            var y = local.minY
            while y <= local.maxY {
                let path = NSBezierPath()
                path.move(to: CGPoint(x: local.minX, y: y))
                path.line(to: CGPoint(x: local.maxX, y: y))
                path.stroke()
                y += step
            }
        }
    }

    private func renderPoint(_ point: CGPoint, selection: CGRect) -> CGPoint {
        CGPoint(
            x: point.x - selection.minX,
            y: selection.height - (point.y - selection.minY)
        )
    }

    private func renderRect(_ rect: CGRect, selection: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - selection.minX,
            y: selection.height - (rect.maxY - selection.minY),
            width: rect.width,
            height: rect.height
        )
    }

    private func saveToClipboard(data: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }

    func close() {
        Self.isActive = false
        window?.orderOut(nil)
        window = nil
        store = nil
    }
}

private enum LegacyScreenshotCapture {
    static func capture(
        _ screenBounds: CGRect,
        _ listOption: CGWindowListOption,
        _ windowID: CGWindowID,
        _ imageOption: CGWindowImageOption
    ) -> CGImage? {
        fuguangCGWindowListCreateImage(screenBounds, listOption, windowID, imageOption)
    }
}

@_silgen_name("CGWindowListCreateImage")
private func fuguangCGWindowListCreateImage(
    _ screenBounds: CGRect,
    _ listOption: CGWindowListOption,
    _ windowID: CGWindowID,
    _ imageOption: CGWindowImageOption
) -> CGImage?
