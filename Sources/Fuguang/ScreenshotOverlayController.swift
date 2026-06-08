import AppKit
import CoreGraphics
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
final class ScreenshotOverlayController: NSObject {
    static let shared = ScreenshotOverlayController()

    /// 设置后截图开始/结束时会自动暂停/恢复快捷键
    static weak var hotKeys: GlobalHotKeyManager?

    private var overlayWindow: NSWindow?
    private weak var store: ShortcutStore?
    private(set) var isActive = false

    func begin(store: ShortcutStore) {
        self.store = store

        guard overlayWindow == nil else {
            store.lastMessage = "截图工具已打开"
            return
        }
        isActive = true

        // 截图时注销所有快捷键，防止干扰
        Self.hotKeys?.suspendForScreenshot()

        AppWindowController.mainWindow?.orderOut(nil)

        let screenFrames = NSScreen.screens.map(\.frame)
        guard var unionFrame = screenFrames.first else {
            isActive = false
            store.lastMessage = "未找到可截图的屏幕"
            return
        }
        for frame in screenFrames.dropFirst() {
            unionFrame = unionFrame.union(frame)
        }
        let screenSnapshots = ScreenSnapshot.captureAll()

        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        let window = ScreenshotOverlayWindow(
            contentRect: unionFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        let contentView = ScreenshotOverlayView(frame: NSRect(origin: .zero, size: unionFrame.size))
        contentView.windowFrame = unionFrame
        contentView.screenSnapshots = screenSnapshots
        contentView.onCancel = { [weak self] in
            self?.finish(message: "已取消截图")
        }
        contentView.onCopy = { [weak self, weak contentView] in
            guard let contentView else { return }
            Task {
                await self?.copySelection(from: contentView)
            }
        }
        contentView.onSave = { [weak self, weak contentView] in
            guard let contentView else { return }
            Task {
                await self?.saveSelection(from: contentView)
            }
        }

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(contentView)
        overlayWindow = window
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(contentView)
            contentView.refreshHoverSelectionFromCurrentMouse()
        }
        store.lastMessage = "已打开浮光截图，Enter 保存到剪贴板，Esc 退出"
    }

    private func copySelection(from view: ScreenshotOverlayView) async {
        guard let image = await image(from: view) else {
            store?.lastMessage = "截图失败：没有可保存的区域"
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        finish(message: "截图已保存到粘贴板")
    }

    private func saveSelection(from view: ScreenshotOverlayView) async {
        guard let image = await image(from: view), let data = image.tiffRepresentation else {
            store?.lastMessage = "截图失败：没有可保存的区域"
            return
        }

        overlayWindow?.orderOut(nil)
        let panel = NSSavePanel()
        panel.title = "保存截图"
        panel.nameFieldStringValue = "Fuguang Screenshot.png"
        panel.allowedContentTypes = [.png]

        if panel.runModal() == .OK, let url = panel.url {
            guard
                let bitmap = NSBitmapImageRep(data: data),
                let pngData = bitmap.representation(using: .png, properties: [:])
            else {
                store?.lastMessage = "截图保存失败：图片转换失败"
                return
            }

            do {
                try pngData.write(to: url, options: [.atomic])
                finish(message: "截图已保存")
            } catch {
                overlayWindow?.orderFront(nil)
                store?.lastMessage = "截图保存失败：\(error.localizedDescription)"
            }
        } else {
            overlayWindow?.orderFront(nil)
        }
    }

    private func image(from view: ScreenshotOverlayView) async -> NSImage? {
        guard let window = overlayWindow, let selection = view.selectionRectForCapture else { return nil }

        window.orderOut(nil)
        defer { window.orderFront(nil) }

        let captureRect = view.captureRectInQuartzCoordinates(selection)
        guard let cgImage = await ScreenCaptureKitRegionCapturer.capture(rect: captureRect, preferredScale: view.backingScale(for: selection)) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: selection.size)
        view.drawAnnotations(on: image)
        return image
    }

    private func finish(message: String) {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        isActive = false
        // 截图结束后重新注册快捷键
        Self.hotKeys?.resumeFromScreenshot()
        store?.lastMessage = message
        store = nil
    }
}

private struct ScreenSnapshot {
    let frame: CGRect
    let scale: CGFloat
    let image: CGImage

    static func captureAll() -> [ScreenSnapshot] {
        NSScreen.screens.compactMap { screen in
            guard
                let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                let image = CGDisplayCreateImage(displayID)
            else {
                return nil
            }

            return ScreenSnapshot(frame: screen.frame, scale: screen.backingScaleFactor, image: image)
        }
    }

    func imagePoint(for globalPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (globalPoint.x - frame.minX) * scale,
            y: (frame.maxY - globalPoint.y) * scale
        )
    }
}

private enum ScreenCaptureKitRegionCapturer {
    static func capture(rect: CGRect, preferredScale: CGFloat) async -> CGImage? {
        if #available(macOS 15.2, *) {
            return await withCheckedContinuation { continuation in
                SCScreenshotManager.captureImage(in: rect) { image, _ in
                    continuation.resume(returning: image)
                }
            }
        }

        return await captureDisplayRegion(rect: rect, preferredScale: preferredScale)
    }

    private static func captureDisplayRegion(rect: CGRect, preferredScale: CGFloat) async -> CGImage? {
        await withCheckedContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
                guard
                    let content,
                    let display = content.displays
                        .filter({ $0.frame.intersects(rect) })
                        .max(by: { $0.frame.intersection(rect).area < $1.frame.intersection(rect).area })
                else {
                    continuation.resume(returning: nil)
                    return
                }

                let sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.sourceRect = sourceRect
                configuration.width = max(1, Int(sourceRect.width * preferredScale))
                configuration.height = max(1, Int(sourceRect.height * preferredScale))
                configuration.scalesToFit = true
                configuration.showsCursor = true
                configuration.shouldBeOpaque = true
                configuration.captureResolution = .best

                SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
                    continuation.resume(returning: image)
                }
            }
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull else { return 0 }
        return width * height
    }
}

private final class ScreenshotOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ScreenshotOverlayView: NSView {
    var windowFrame: CGRect = .zero
    fileprivate var screenSnapshots: [ScreenSnapshot] = []
    var onCancel: () -> Void = {}
    var onCopy: () -> Void = {}
    var onSave: () -> Void = {}

    private var selectionRect: CGRect?
    private var dragStart: CGPoint?
    private var didDragSelection = false
    private var pendingHoverSelection: CGRect?
    private var mouseLocation: CGPoint?
    private var hasManualSelection = false
    private var activeTool: AnnotationTool?
    private var annotationStart: CGPoint?
    private var currentStroke: [CGPoint] = []
    private var currentShape: CGRect?
    private var currentArrow: (start: CGPoint, end: CGPoint)?
    private var annotations: [ScreenshotAnnotation] = []
    private var activeTextField: NSTextField?
    private var activeTextOrigin: CGPoint?
    private var annotationColorIndex = 0
    private var renderColor: NSColor?
    private var trackingArea: NSTrackingArea?
    private let toolbarHeight: CGFloat = 44
    private let annotationColors: [NSColor] = [.systemRed, .systemBlue, .systemYellow, .systemGreen, .white]

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var selectionRectForCapture: CGRect? {
        guard let selectionRect else { return nil }
        let rect = selectionRect.standardized.intersection(bounds)
        guard rect.width >= 6, rect.height >= 6 else { return nil }
        return rect
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        // NSEvent.mouseLocation 和 windowFrame 都是屏幕坐标系（top-left 原点），直接平移
        mouseLocation = CGPoint(
            x: NSEvent.mouseLocation.x - windowFrame.minX,
            y: NSEvent.mouseLocation.y - windowFrame.minY
        )
        updateHoverSelection()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        updateHoverSelection()
        setNeedsDisplay(bounds)
    }

    func refreshHoverSelectionFromCurrentMouse() {
        // NSEvent.mouseLocation 和 windowFrame 都是屏幕坐标系（top-left 原点），直接平移
        mouseLocation = CGPoint(
            x: NSEvent.mouseLocation.x - windowFrame.minX,
            y: NSEvent.mouseLocation.y - windowFrame.minY
        )
        updateHoverSelection()
        setNeedsDisplay(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        if let rect = selectionRectForCapture {
            let overlayPath = NSBezierPath(rect: bounds)
            overlayPath.append(NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3))
            overlayPath.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.34).setFill()
            overlayPath.fill()

            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            NSColor.systemCyan.setStroke()
            path.lineWidth = 2
            path.stroke()

            drawAnnotationsPreview(offsetBy: rect.origin)
            if hasManualSelection {
                drawToolbar(for: rect)
            }
        } else {
            NSColor.black.withAlphaComponent(0.34).setFill()
            dirtyRect.fill()
            drawHint("拖拽选择截图区域")
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseLocation = point

        if let action = toolbarAction(at: point) {
            runToolbarAction(action)
            return
        }

        if let activeTool, let rect = selectionRectForCapture, rect.contains(point) {
            let relativePoint = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
            if activeTool == .text {
                addTextAnnotation(at: relativePoint)
                return
            }

            annotationStart = relativePoint
            switch activeTool {
            case .brush:
                currentStroke = [relativePoint]
            case .rectangle, .ellipse, .mosaic:
                currentShape = CGRect(origin: relativePoint, size: .zero)
            case .arrow:
                currentArrow = (relativePoint, relativePoint)
            case .text:
                break
            }
            return
        }

        dragStart = point
        didDragSelection = false
        pendingHoverSelection = !hasManualSelection ? selectionRectForCapture : nil
        hasManualSelection = true
        activeTool = nil
        annotations.removeAll()
        activeTextField?.removeFromSuperview()
        activeTextField = nil
        selectionRect = CGRect(origin: point, size: .zero)
        setNeedsDisplay(bounds)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseLocation = point

        if let activeTool, let rect = selectionRectForCapture, let annotationStart {
            let relativePoint = CGPoint(
                x: min(max(point.x - rect.minX, 0), rect.width),
                y: min(max(point.y - rect.minY, 0), rect.height)
            )

            switch activeTool {
            case .brush:
                currentStroke.append(relativePoint)
            case .rectangle, .ellipse, .mosaic:
                currentShape = CGRect(
                    x: min(annotationStart.x, relativePoint.x),
                    y: min(annotationStart.y, relativePoint.y),
                    width: abs(annotationStart.x - relativePoint.x),
                    height: abs(annotationStart.y - relativePoint.y)
                )
            case .arrow:
                currentArrow = (annotationStart, relativePoint)
            case .text:
                break
            }

            setNeedsDisplay(bounds)
            return
        }

        guard let dragStart else { return }
        didDragSelection = true
        pendingHoverSelection = nil
        selectionRect = CGRect(
            x: min(dragStart.x, point.x),
            y: min(dragStart.y, point.y),
            width: abs(point.x - dragStart.x),
            height: abs(point.y - dragStart.y)
        )
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        if let activeTool, annotationStart != nil {
            switch activeTool {
            case .brush:
                if currentStroke.count > 1 {
                    annotations.append(.stroke(currentStroke, color: annotationColor))
                }
            case .rectangle:
                if let rect = currentShape, rect.width > 4, rect.height > 4 {
                    annotations.append(.rectangle(rect, color: annotationColor))
                }
            case .ellipse:
                if let rect = currentShape, rect.width > 4, rect.height > 4 {
                    annotations.append(.ellipse(rect, color: annotationColor))
                }
            case .arrow:
                if let arrow = currentArrow, distance(arrow.start, arrow.end) > 6 {
                    annotations.append(.arrow(start: arrow.start, end: arrow.end, color: annotationColor))
                }
            case .mosaic:
                if let rect = currentShape, rect.width > 8, rect.height > 8 {
                    annotations.append(.mosaic(rect))
                }
            case .text:
                break
            }

            currentStroke = []
            currentShape = nil
            currentArrow = nil
            annotationStart = nil
            setNeedsDisplay(bounds)
            return
        }

        if !didDragSelection, let pendingHoverSelection {
            selectionRect = pendingHoverSelection
            hasManualSelection = true
        } else if !didDragSelection, selectionRectForCapture == nil {
            hasManualSelection = false
            updateHoverSelection()
        }
        dragStart = nil
        didDragSelection = false
        pendingHoverSelection = nil
        if selectionRectForCapture == nil {
            hasManualSelection = false
            updateHoverSelection()
        }
        setNeedsDisplay(bounds)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            commitActiveTextField()
            onCopy()
        case 53:
            activeTextField?.removeFromSuperview()
            onCancel()
        case 58, 61:
            cycleAnnotationColor()
        default:
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            cycleAnnotationColor()
        }
    }

    func captureRectInQuartzCoordinates(_ rect: CGRect) -> CGRect {
        // 视图坐标（top-left 原点）→ Quartz 坐标（bottom-left 原点）
        let screenMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let appKitY = screenMaxY - rect.maxY - windowFrame.minY
        return CGRect(
            x: rect.minX + windowFrame.minX,
            y: appKitY,
            width: rect.width,
            height: rect.height
        )
    }

    func backingScale(for rect: CGRect) -> CGFloat {
        // 视图坐标（top-left）→ AppKit 全局坐标（bottom-left）用于屏幕匹配
        let screenMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let appKitRect = CGRect(
            x: rect.minX + windowFrame.minX,
            y: screenMaxY - rect.maxY - windowFrame.minY,
            width: rect.width,
            height: rect.height
        )
        let center = CGPoint(x: appKitRect.midX, y: appKitRect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }?.backingScaleFactor ?? 2
    }

    func drawAnnotations(on image: NSImage) {
        commitActiveTextField()
        guard !annotations.isEmpty else { return }

        image.lockFocus()

        for annotation in annotations {
            switch annotation {
            case .stroke(let points, let color):
                renderColor = color
                drawStroke(points, imageHeight: image.size.height)
            case .rectangle(let rect, let color):
                renderColor = color
                drawBox(rect, imageHeight: image.size.height)
            case .ellipse(let rect, let color):
                renderColor = color
                drawEllipse(rect, imageHeight: image.size.height)
            case .arrow(let start, let end, let color):
                renderColor = color
                drawArrow(start: start, end: end, imageHeight: image.size.height)
            case .text(let text, let point, let color):
                renderColor = color
                drawText(text, at: point, imageHeight: image.size.height)
            case .mosaic(let rect):
                drawMosaic(rect, imageHeight: image.size.height)
            }
        }
        renderColor = nil

        image.unlockFocus()
    }

    private func imagePoint(_ point: CGPoint, imageHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: imageHeight - point.y)
    }

    private var annotationColor: NSColor {
        annotationColors[annotationColorIndex % annotationColors.count]
    }

    private func cycleAnnotationColor() {
        annotationColorIndex = (annotationColorIndex + 1) % annotationColors.count
        activeTextField?.textColor = annotationColor
        setNeedsDisplay(bounds)
    }

    private func updateHoverSelection() {
        guard !hasManualSelection, let mouseLocation else { return }
        selectionRect = recommendedWindowFrame(containing: mouseLocation)
    }

    private func recommendedWindowFrame(containing point: CGPoint) -> CGRect? {
        // point 是视图坐标（top-left 原点，isFlipped = true）
        // 屏幕坐标系也是 top-left 原点，直接平移即可
        let globalPoint = CGPoint(x: point.x + windowFrame.minX, y: point.y + windowFrame.minY)

        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let excludedOwners: Set<String> = [
            "Fuguang",
            "Window Server",
            "Dock",
            "Control Center",
            "Notification Center",
            "Spotlight"
        ]

        let candidates = infoList.compactMap { info -> CGRect? in
            guard
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let alpha = info[kCGWindowAlpha as String] as? Double,
                alpha >= 0.9,
                let owner = info[kCGWindowOwnerName as String] as? String,
                !excludedOwners.contains(owner),
                let boundsInfo = info[kCGWindowBounds as String] as? [String: Any],
                let x = boundsInfo["X"] as? CGFloat,
                let y = boundsInfo["Y"] as? CGFloat,
                let width = boundsInfo["Width"] as? CGFloat,
                let height = boundsInfo["Height"] as? CGFloat,
                width > 60,
                height > 60
            else {
                return nil
            }

            let rect = CGRect(x: x, y: y, width: width, height: height)
            return rect.contains(globalPoint) ? rect : nil
        }

        // 取面积最小的窗口（最上层、最具体的窗口）
        guard let matchedRect = candidates.min(by: { $0.width * $0.height < $1.width * $1.height }) else { return nil }

        // 转回视图坐标（top-left 原点）
        let viewRect = CGRect(
            x: matchedRect.minX - windowFrame.minX,
            y: matchedRect.minY - windowFrame.minY,
            width: matchedRect.width,
            height: matchedRect.height
        )
        return viewRect.insetBy(dx: -1, dy: -1)
    }

    private func drawAnnotationsPreview(offsetBy origin: CGPoint) {
        for annotation in annotations {
            drawAnnotation(annotation, offsetBy: origin)
        }

        if currentStroke.count > 1 {
            drawAnnotation(.stroke(currentStroke, color: annotationColor), offsetBy: origin)
        }

        if let currentShape, let activeTool {
            switch activeTool {
            case .rectangle:
                drawAnnotation(.rectangle(currentShape, color: annotationColor), offsetBy: origin)
            case .ellipse:
                drawAnnotation(.ellipse(currentShape, color: annotationColor), offsetBy: origin)
            case .mosaic:
                drawAnnotation(.mosaic(currentShape), offsetBy: origin)
            case .brush, .arrow, .text:
                break
            }
        }

        if let currentArrow {
            drawAnnotation(.arrow(start: currentArrow.start, end: currentArrow.end, color: annotationColor), offsetBy: origin)
        }
    }

    private func drawAnnotation(_ annotation: ScreenshotAnnotation, offsetBy origin: CGPoint) {
        switch annotation {
        case .stroke(let points, let color):
            renderColor = color
            drawStroke(points.map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) })
        case .rectangle(let rect, let color):
            renderColor = color
            drawBox(rect.offsetBy(dx: origin.x, dy: origin.y))
        case .ellipse(let rect, let color):
            renderColor = color
            drawEllipse(rect.offsetBy(dx: origin.x, dy: origin.y))
        case .arrow(let start, let end, let color):
            renderColor = color
            drawArrow(
                start: CGPoint(x: start.x + origin.x, y: start.y + origin.y),
                end: CGPoint(x: end.x + origin.x, y: end.y + origin.y)
            )
        case .text(let text, let point, let color):
            renderColor = color
            drawText(text, at: CGPoint(x: point.x + origin.x, y: point.y + origin.y))
        case .mosaic(let rect):
            drawMosaicPreview(rect.offsetBy(dx: origin.x, dy: origin.y))
        }
        renderColor = nil
    }

    private func drawStroke(_ points: [CGPoint]) {
        guard points.count > 1 else { return }
        (renderColor ?? annotationColor).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.stroke()
    }

    private func drawStroke(_ points: [CGPoint], imageHeight: CGFloat) {
        drawStroke(points.map { imagePoint($0, imageHeight: imageHeight) })
    }

    private func drawBox(_ rect: CGRect) {
        (renderColor ?? annotationColor).setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        path.lineWidth = 3
        path.stroke()
    }

    private func drawBox(_ rect: CGRect, imageHeight: CGFloat) {
        drawBox(imageRect(rect, imageHeight: imageHeight))
    }

    private func drawEllipse(_ rect: CGRect) {
        (renderColor ?? annotationColor).setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = 3
        path.stroke()
    }

    private func drawEllipse(_ rect: CGRect, imageHeight: CGFloat) {
        drawEllipse(imageRect(rect, imageHeight: imageHeight))
    }

    private func drawArrow(start: CGPoint, end: CGPoint) {
        (renderColor ?? annotationColor).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: start)
        path.line(to: end)
        path.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 13
        let headAngle: CGFloat = .pi / 7
        let p1 = CGPoint(x: end.x - headLength * cos(angle - headAngle), y: end.y - headLength * sin(angle - headAngle))
        let p2 = CGPoint(x: end.x - headLength * cos(angle + headAngle), y: end.y - headLength * sin(angle + headAngle))
        let headPath = NSBezierPath()
        headPath.lineWidth = 3
        headPath.lineCapStyle = .round
        headPath.move(to: p1)
        headPath.line(to: end)
        headPath.line(to: p2)
        headPath.stroke()
    }

    private func drawArrow(start: CGPoint, end: CGPoint, imageHeight: CGFloat) {
        drawArrow(start: imagePoint(start, imageHeight: imageHeight), end: imagePoint(end, imageHeight: imageHeight))
    }

    private func drawText(_ text: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: renderColor ?? annotationColor
        ]
        text.draw(at: point, withAttributes: attributes)
    }

    private func drawText(_ text: String, at point: CGPoint, imageHeight: CGFloat) {
        drawText(text, at: imagePoint(point, imageHeight: imageHeight))
    }

    private func drawMosaicPreview(_ rect: CGRect) {
        NSColor.white.withAlphaComponent(0.28).setFill()
        NSBezierPath(rect: rect).fill()

        NSColor.white.withAlphaComponent(0.42).setStroke()
        let grid = NSBezierPath()
        let step: CGFloat = 8
        var x = rect.minX
        while x <= rect.maxX {
            grid.move(to: CGPoint(x: x, y: rect.minY))
            grid.line(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }
        var y = rect.minY
        while y <= rect.maxY {
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.line(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }
        grid.lineWidth = 1
        grid.stroke()
    }

    private func drawMosaic(_ rect: CGRect, imageHeight: CGFloat) {
        let converted = imageRect(rect, imageHeight: imageHeight)
        NSColor(calibratedWhite: 0.72, alpha: 0.92).setFill()
        NSBezierPath(rect: converted).fill()

        NSColor(calibratedWhite: 0.52, alpha: 0.95).setStroke()
        let grid = NSBezierPath()
        let step: CGFloat = 10
        var x = converted.minX
        while x <= converted.maxX {
            grid.move(to: CGPoint(x: x, y: converted.minY))
            grid.line(to: CGPoint(x: x, y: converted.maxY))
            x += step
        }
        var y = converted.minY
        while y <= converted.maxY {
            grid.move(to: CGPoint(x: converted.minX, y: y))
            grid.line(to: CGPoint(x: converted.maxX, y: y))
            y += step
        }
        grid.lineWidth = 1
        grid.stroke()
    }

    private func imageRect(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: imageHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func addTextAnnotation(at point: CGPoint) {
        commitActiveTextField()
        guard let selectionRect = selectionRectForCapture else { return }

        let field = NSTextField(frame: NSRect(x: selectionRect.minX + point.x, y: selectionRect.minY + point.y, width: 180, height: 30))
        field.placeholderString = "输入文字"
        field.font = .systemFont(ofSize: 20, weight: .semibold)
        field.textColor = annotationColor
        field.backgroundColor = .clear
        field.isBordered = true
        field.focusRingType = .none
        field.target = self
        field.action = #selector(textFieldDidCommit(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
        activeTextOrigin = point
    }

    @objc private func textFieldDidCommit(_ sender: NSTextField) {
        commitActiveTextField()
    }

    private func commitActiveTextField() {
        guard let field = activeTextField, let origin = activeTextOrigin else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            annotations.append(.text(text, point: origin, color: annotationColor))
        }
        field.removeFromSuperview()
        activeTextField = nil
        activeTextOrigin = nil
        window?.makeFirstResponder(self)
        setNeedsDisplay(bounds)
    }

    private func drawToolbar(for rect: CGRect) {
        let toolbarRect = toolbarRect(for: rect)
        let path = NSBezierPath(roundedRect: toolbarRect, xRadius: 9, yRadius: 9)
        NSColor(calibratedWhite: 0.10, alpha: 0.94).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 1
        path.stroke()

        drawOptionColorIndicator(in: toolbarRect)

        let actions = toolbarActions
        for (index, action) in actions.enumerated() {
            let rect = buttonRect(index: index, in: toolbarRect)
            let buttonPath = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            actionBackground(action).setFill()
            buttonPath.fill()

            drawToolbarGlyph(action.glyph, in: rect, color: actionColor(action))

            if action == .undo || action == .save {
                let separatorX = rect.maxX + 5
                NSColor.white.withAlphaComponent(0.16).setStroke()
                let separator = NSBezierPath()
                separator.move(to: CGPoint(x: separatorX, y: toolbarRect.minY + 10))
                separator.line(to: CGPoint(x: separatorX, y: toolbarRect.maxY - 10))
                separator.lineWidth = 1
                separator.stroke()
            }
        }
    }

    private func drawOptionColorIndicator(in toolbarRect: CGRect) {
        let indicatorRect = CGRect(x: toolbarRect.minX + 8, y: toolbarRect.minY + 7, width: 72, height: toolbarRect.height - 14)
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: indicatorRect, xRadius: 6, yRadius: 6).fill()

        annotationColor.setFill()
        NSBezierPath(ovalIn: CGRect(x: indicatorRect.minX + 8, y: indicatorRect.midY - 6, width: 12, height: 12)).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86)
        ]
        "⌥ 颜色".draw(at: CGPoint(x: indicatorRect.minX + 26, y: indicatorRect.minY + 8), withAttributes: attributes)
    }

    private func actionBackground(_ action: ToolbarAction) -> NSColor {
        // 选中标注工具为蓝色；nil 工具按钮不参与选中态判断。
        if let tool = action.tool, tool == activeTool {
            return NSColor.systemBlue.withAlphaComponent(0.55)
        }
        if action == .undo && !annotations.isEmpty {
            return NSColor.systemBlue.withAlphaComponent(0.55)
        }

        // 完成复制按钮保持绿色
        if action == .copy {
            return NSColor.systemGreen.withAlphaComponent(0.82)
        }

        // 其他按钮统一背景
        return NSColor.white.withAlphaComponent(0.08)
    }

    private func actionColor(_ action: ToolbarAction) -> NSColor {
        NSColor.white.withAlphaComponent(0.88)
    }

    private func drawToolbarGlyph(_ glyph: String, in rect: CGRect, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        glyph.draw(in: rect.insetBy(dx: 4, dy: 5), withAttributes: attributes)
    }

    private func drawHint(_ text: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86),
            .paragraphStyle: paragraph
        ]
        text.draw(in: CGRect(x: 0, y: bounds.midY - 18, width: bounds.width, height: 36), withAttributes: attributes)
    }

    private func toolbarRect(for selection: CGRect) -> CGRect {
        let width = CGFloat(toolbarActions.count) * 34 + CGFloat(toolbarActions.count - 1) * 6 + 18 + 82
        let x = min(max(selection.midX - width / 2, bounds.minX + 16), bounds.maxX - width - 16)
        let preferredY = selection.maxY + 10
        let y = preferredY + toolbarHeight <= bounds.maxY - 16 ? preferredY : selection.minY - toolbarHeight - 10
        return CGRect(x: x, y: max(bounds.minY + 16, y), width: width, height: toolbarHeight)
    }

    private var toolbarActions: [ToolbarAction] {
        [.rectangle, .ellipse, .arrow, .brush, .text, .mosaic, .undo, .save, .copy, .cancel]
    }

    private func buttonRect(index: Int, in toolbarRect: CGRect) -> CGRect {
        let padding: CGFloat = 7
        let spacing: CGFloat = 6
        let width: CGFloat = 34
        return CGRect(
            x: toolbarRect.minX + padding + 82 + CGFloat(index) * (width + spacing),
            y: toolbarRect.minY + 6,
            width: width,
            height: toolbarRect.height - 12
        )
    }

    private func toolbarAction(at point: CGPoint) -> ToolbarAction? {
        guard let rect = selectionRectForCapture else { return nil }
        let toolbarRect = toolbarRect(for: rect)
        guard toolbarRect.contains(point) else { return nil }

        for (index, action) in toolbarActions.enumerated() where buttonRect(index: index, in: toolbarRect).contains(point) {
            return action
        }
        return nil
    }

    private func runToolbarAction(_ action: ToolbarAction) {
        if action.tool != .text {
            commitActiveTextField()
        }

        switch action {
        case .rectangle:
            activeTool = activeTool == .rectangle ? nil : .rectangle
            setNeedsDisplay(bounds)
        case .ellipse:
            activeTool = activeTool == .ellipse ? nil : .ellipse
            setNeedsDisplay(bounds)
        case .arrow:
            activeTool = activeTool == .arrow ? nil : .arrow
            setNeedsDisplay(bounds)
        case .brush:
            activeTool = activeTool == .brush ? nil : .brush
            setNeedsDisplay(bounds)
        case .text:
            activeTool = activeTool == .text ? nil : .text
            setNeedsDisplay(bounds)
        case .mosaic:
            activeTool = activeTool == .mosaic ? nil : .mosaic
            setNeedsDisplay(bounds)
        case .undo:
            if !annotations.isEmpty {
                annotations.removeLast()
                setNeedsDisplay(bounds)
            }
        case .copy:
            onCopy()
        case .save:
            onSave()
        case .cancel:
            onCancel()
        }
    }
}

private enum ToolbarAction {
    case rectangle
    case ellipse
    case arrow
    case brush
    case text
    case mosaic
    case undo
    case copy
    case save
    case cancel

    var title: String {
        switch self {
        case .rectangle:
            return "矩形"
        case .ellipse:
            return "圆形"
        case .arrow:
            return "箭头"
        case .brush:
            return "画笔"
        case .text:
            return "文字"
        case .mosaic:
            return "马赛克"
        case .undo:
            return "撤销"
        case .copy:
            return "复制 Enter"
        case .save:
            return "保存"
        case .cancel:
            return "取消 Esc"
        }
    }

    var glyph: String {
        switch self {
        case .rectangle:
            return "□"
        case .ellipse:
            return "○"
        case .arrow:
            return "↗"
        case .brush:
            return "✎"
        case .text:
            return "T"
        case .mosaic:
            return "▦"
        case .undo:
            return "↶"
        case .copy:
            return "✓"
        case .save:
            return "⇩"
        case .cancel:
            return "×"
        }
    }

    var tool: AnnotationTool? {
        switch self {
        case .rectangle:
            return .rectangle
        case .ellipse:
            return .ellipse
        case .arrow:
            return .arrow
        case .brush:
            return .brush
        case .text:
            return .text
        case .mosaic:
            return .mosaic
        case .undo, .copy, .save, .cancel:
            return nil
        }
    }
}

private enum AnnotationTool {
    case rectangle
    case ellipse
    case arrow
    case brush
    case text
    case mosaic
}

private enum ScreenshotAnnotation {
    case stroke([CGPoint], color: NSColor)
    case rectangle(CGRect, color: NSColor)
    case ellipse(CGRect, color: NSColor)
    case arrow(start: CGPoint, end: CGPoint, color: NSColor)
    case text(String, point: CGPoint, color: NSColor)
    case mosaic(CGRect)
}
