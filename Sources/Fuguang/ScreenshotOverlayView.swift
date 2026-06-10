import AppKit
import SwiftUI

private enum ScreenshotToolMode: Equatable {
    case move
    case rectangle
    case oval
    case text
    case arrow
    case pen
    case mosaic
}

enum ScreenshotColorOption: CaseIterable, Equatable {
    case green, red, blue, yellow, white

    var color: Color {
        switch self {
        case .green: return .green
        case .red: return .red
        case .blue: return .blue
        case .yellow: return .yellow
        case .white: return .white
        }
    }

    var nsColor: NSColor {
        switch self {
        case .green: return .systemGreen
        case .red: return .systemRed
        case .blue: return .systemBlue
        case .yellow: return .systemYellow
        case .white: return .white
        }
    }
}

enum ScreenshotAnnotationKind: Equatable {
    case text
    case arrow
    case rectangle
    case oval
    case pen
    case mosaic
}

struct ScreenshotAnnotation: Identifiable, Equatable {
    let id: UUID
    var kind: ScreenshotAnnotationKind
    var rect: CGRect
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint]
    var text: String
    var color: ScreenshotColorOption

    init(
        id: UUID = UUID(),
        kind: ScreenshotAnnotationKind,
        rect: CGRect = .zero,
        start: CGPoint = .zero,
        end: CGPoint = .zero,
        points: [CGPoint] = [],
        text: String = "",
        color: ScreenshotColorOption = .green
    ) {
        self.id = id
        self.kind = kind
        self.rect = rect
        self.start = start
        self.end = end
        self.points = points
        self.text = text
        self.color = color
    }
}

struct ScreenshotOverlayView: View {
    let screenSize: CGSize
    let quartzScreenOrigin: CGPoint
    let menuBarOffset: CGFloat
    let onSave: (CGRect, [ScreenshotAnnotation]) -> Void
    let onCopy: (CGRect, [ScreenshotAnnotation]) -> Void
    let onCancel: () -> Void

    @State private var selectionRect: CGRect?
    @State private var hoveredWindowRect: CGRect?
    @State private var isDragging = false
    @State private var isEditing = false
    @State private var mouseDownPoint: CGPoint = .zero
    @State private var dragStart: CGPoint = .zero
    @State private var selectionAtDragStart: CGRect = .zero
    @State private var pendingHoveredWindow: CGRect?
    @State private var resizeEdge: EdgeSet = []
    @State private var activeTool: ScreenshotToolMode = .move
    @State private var activeColor: ScreenshotColorOption = .green
    @State private var annotations: [ScreenshotAnnotation] = []
    @State private var annotationHistory: [[ScreenshotAnnotation]] = []
    @State private var draftAnnotation: ScreenshotAnnotation?
    @State private var selectedAnnotationID: UUID?
    @State private var editingTextID: UUID?
    @State private var draggingAnnotationID: UUID?
    @State private var annotationResizeEdge: EdgeSet = []
    @State private var annotationsAtDragStart: [ScreenshotAnnotation] = []
    @State private var windowList: [WindowInfo] = []
    @State private var wasOptionPressed = false

    private let dragThreshold: CGFloat = 4
    private let edgeThreshold: CGFloat = 12

    init(screenSize: CGSize, quartzScreenOrigin: CGPoint = .zero, menuBarOffset: CGFloat = 0, onSave: @escaping (CGRect, [ScreenshotAnnotation]) -> Void, onCopy: @escaping (CGRect, [ScreenshotAnnotation]) -> Void, onCancel: @escaping () -> Void) {
        self.screenSize = screenSize
        self.quartzScreenOrigin = quartzScreenOrigin
        self.menuBarOffset = menuBarOffset
        self.onSave = onSave
        self.onCopy = onCopy
        self.onCancel = onCancel
    }

    private var activeRect: CGRect {
        selectionRect ?? hoveredWindowRect ?? .zero
    }

    private var hasActiveRect: Bool {
        selectionRect != nil || hoveredWindowRect != nil
    }

    private var isHover: Bool {
        selectionRect == nil && hoveredWindowRect != nil
    }

    var body: some View {
        ZStack {
            OverlayMaskView(hasActiveRect: hasActiveRect, activeRect: activeRect)
            AnnotationLayerView(
                annotations: $annotations,
                draftAnnotation: draftAnnotation,
                selectedAnnotationID: selectedAnnotationID,
                editingTextID: $editingTextID
            )
            SelectionBorderView(activeRect: activeRect, isHover: isHover, showHandles: !isHover)
            if hasActiveRect {
                SizeLabelView(rect: activeRect)
            }
            if isEditing, let rect = selectionRect {
                EditToolbarView(rect: rect, screenHeight: screenSize.height, activeTool: activeTool, activeColor: activeColor, onMove: {
                    switchTool(.move)
                }, onRectangle: {
                    switchTool(.rectangle)
                }, onOval: {
                    switchTool(.oval)
                }, onText: {
                    switchTool(.text)
                }, onArrow: {
                    switchTool(.arrow)
                }, onPen: {
                    switchTool(.pen)
                }, onMosaic: {
                    switchTool(.mosaic)
                }, onColor: {
                    cycleColor()
                }, onUndo: {
                    undoLastAnnotationChange()
                }, onSave: {
                    onSave(rect, annotations)
                }, onCopy: {
                    onCopy(rect, annotations)
                }, onCancel: {
                    onCancel()
                })
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onAppear {
            windowList = Self.fetchWindowList()
            setupEventMonitors()
        }
    }

    // MARK: - NSEvent Monitors

    private func setupEventMonitors() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleKeyEvent(event) ? nil : event
        }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [self] event in
            handleMouseMove(event)
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [self] event in
            handleMouseDown(event)
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [self] event in
            handleMouseDragged(event)
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [self] event in
            handleMouseUp(event)
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [self] event in
            handleFlagsChanged(event)
            return event
        }
    }

    // MARK: - Event Handlers

    private func toSwiftUIPoint(_ event: NSEvent) -> CGPoint {
        let loc = event.locationInWindow
        return CGPoint(x: loc.x, y: screenSize.height - loc.y)
    }

    private func handleMouseMove(_ event: NSEvent) {
        guard !isDragging else { return }
        let point = toSwiftUIPoint(event)

        if isEditing, let sr = selectionRect {
            if sr.contains(point), let annotationID = hitTestAnnotation(at: point), let annotation = annotations.first(where: { $0.id == annotationID }) {
                let edge = detectEdge(point, in: annotationHitRect(annotation))
                if !edge.isEmpty {
                    cursor(for: edge).set()
                } else if annotation.kind == .text {
                    NSCursor.iBeam.set()
                } else {
                    NSCursor.openHand.set()
                }
                return
            }

            if activeTool == .rectangle || activeTool == .oval || activeTool == .arrow || activeTool == .mosaic || activeTool == .pen {
                NSCursor.crosshair.set()
                return
            }
            if activeTool == .text {
                NSCursor.iBeam.set()
                return
            }
            updateCursor(at: point, in: sr)
            return
        }

        NSCursor.arrow.set()
        hoveredWindowRect = Self.findWindowRect(at: point, in: windowList, quartzScreenOrigin: quartzScreenOrigin)
    }

    private func handleMouseDown(_ event: NSEvent) {
        let point = toSwiftUIPoint(event)
        mouseDownPoint = point

        if isEditing, let sr = selectionRect, toolbarFrame(for: sr).contains(point) {
            return
        }

        if isEditing, let sr = selectionRect {
            if event.clickCount >= 2, sr.contains(point) {
                onCopy(sr, annotations)
                return
            }

            if sr.contains(point), let annotationID = hitTestAnnotation(at: point), let annotation = annotations.first(where: { $0.id == annotationID }) {
                let wasAlreadySelected = selectedAnnotationID == annotationID
                selectedAnnotationID = annotationID
                annotationsAtDragStart = annotations
                annotationResizeEdge = detectEdge(point, in: annotationHitRect(annotation))
                resizeEdge = []
                dragStart = point

                if !wasAlreadySelected {
                    editingTextID = nil
                    isDragging = false
                    return
                }

                if !annotationResizeEdge.isEmpty {
                    pushAnnotationHistory()
                    isDragging = true
                    draggingAnnotationID = annotationID
                    cursor(for: annotationResizeEdge).set()
                    return
                }

                if annotation.kind == .text {
                    editingTextID = annotationID
                    isDragging = false
                    NSCursor.iBeam.set()
                    return
                }

                pushAnnotationHistory()
                isDragging = true
                draggingAnnotationID = annotationID
                NSCursor.closedHand.set()
                return
            }

            if activeTool != .move, sr.contains(point) {
                editingTextID = nil
                selectedAnnotationID = nil
                resizeEdge = []
                isDragging = true
                dragStart = point
                draftAnnotation = makeDraftAnnotation(from: point, to: point)
                NSCursor.crosshair.set()
                return
            }

            let edge = detectEdge(point, in: sr)
            if !edge.isEmpty {
                // 点击边缘/角落 → 准备调整大小
                resizeEdge = edge
                isDragging = true
                dragStart = point
                selectionAtDragStart = sr
                cursor(for: edge).set()
            } else if sr.contains(point) {
                editingTextID = nil
                selectedAnnotationID = nil
                selectionAtDragStart = sr
                annotationsAtDragStart = annotations
                pushAnnotationHistory()
                annotationResizeEdge = []
                resizeEdge = []
                isDragging = true
                dragStart = point
                NSCursor.closedHand.set()
            } else {
                // 点击选区外部 → 退出编辑模式，自由框选
                isEditing = false
                selectionRect = nil
                isDragging = true
                dragStart = point
                resizeEdge = []
                activeTool = .move
                NSCursor.crosshair.set()
            }
        } else if selectionRect == nil, let hovered = hoveredWindowRect, hovered.contains(point) {
            // 点击预选窗口 → 暂存，等 mouseUp 判断是单击还是拖拽
            pendingHoveredWindow = hovered
        } else {
            // 点击空白处 → 退出编辑模式，准备自由框选
            isEditing = false
            hoveredWindowRect = nil
            selectionRect = nil
            isDragging = true
            dragStart = point
            resizeEdge = []
            NSCursor.crosshair.set()
        }
    }

    private func handleMouseDragged(_ event: NSEvent) {
        let point = toSwiftUIPoint(event)
        let dx = abs(point.x - mouseDownPoint.x)
        let dy = abs(point.y - mouseDownPoint.y)

        // 如果有暂存的预选窗口且开始拖拽 → 取消预选，进入自由框选
        if pendingHoveredWindow != nil, dx > dragThreshold || dy > dragThreshold {
            pendingHoveredWindow = nil
            hoveredWindowRect = nil
            isDragging = true
            dragStart = mouseDownPoint
            resizeEdge = []
            NSCursor.crosshair.set()
        }

        guard isDragging else { return }

        if isEditing, selectionRect != nil {
            let ddx = point.x - dragStart.x
            let ddy = point.y - dragStart.y

            if draftAnnotation != nil {
                draftAnnotation = makeDraftAnnotation(from: dragStart, to: point)
            } else if let draggingAnnotationID {
                annotations = annotationsAtDragStart.map { annotation in
                    guard annotation.id == draggingAnnotationID else { return annotation }
                    if annotationResizeEdge.isEmpty {
                        return offsetAnnotation(annotation, dx: ddx, dy: ddy)
                    } else {
                        return resizeAnnotation(annotation, edge: annotationResizeEdge, dx: ddx, dy: ddy)
                    }
                }
            } else if !resizeEdge.isEmpty {
                // 调整大小模式
                var newRect = selectionAtDragStart
                if resizeEdge.contains(.left) { newRect.origin.x += ddx; newRect.size.width -= ddx }
                if resizeEdge.contains(.right) { newRect.size.width += ddx }
                if resizeEdge.contains(.top) { newRect.origin.y += ddy; newRect.size.height -= ddy }
                if resizeEdge.contains(.bottom) { newRect.size.height += ddy }
                newRect = clampRect(newRect)
                selectionRect = newRect
            } else {
                // 移动模式
                var newRect = selectionAtDragStart.offsetBy(dx: ddx, dy: ddy)
                newRect = clampRect(newRect)
                let actualDx = newRect.origin.x - selectionAtDragStart.origin.x
                let actualDy = newRect.origin.y - selectionAtDragStart.origin.y
                selectionRect = newRect
                annotations = annotationsAtDragStart.isEmpty
                    ? annotations.map { offsetAnnotation($0, dx: actualDx, dy: actualDy) }
                    : annotationsAtDragStart.map { offsetAnnotation($0, dx: actualDx, dy: actualDy) }
            }
        } else {
            // 自由框选
            selectionRect = normalizeRect(from: dragStart, to: point)
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        // 如果有暂存的预选窗口且没有拖拽 → 单击，进入编辑模式
        if let pending = pendingHoveredWindow {
            pendingHoveredWindow = nil
            hoveredWindowRect = nil
            selectionRect = pending
            isEditing = true
            resizeEdge = []
            activeTool = .move
            NSCursor.openHand.set()
        } else if let rect = selectionRect, rect.width > dragThreshold, rect.height > dragThreshold {
            isEditing = true
        }

        if let draftAnnotation, isValidAnnotation(draftAnnotation) {
            pushAnnotationHistory()
            annotations.append(draftAnnotation)
            selectedAnnotationID = draftAnnotation.id
            if draftAnnotation.kind == .text {
                editingTextID = draftAnnotation.id
            }
        }
        draftAnnotation = nil

        isDragging = false
        resizeEdge = []
        annotationResizeEdge = []
        draggingAnnotationID = nil
        annotationsAtDragStart = []

        if isEditing, let sr = selectionRect {
            let point = toSwiftUIPoint(event)
            updateCursor(at: point, in: sr)
        } else {
            NSCursor.arrow.set()
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 6 {
            undoLastAnnotationChange()
            return true
        }

        if editingTextID != nil {
            switch event.keyCode {
            case 18, 83:
                switchTool(.move)
                return true
            case 19, 84:
                switchTool(.rectangle)
                return true
            case 20, 85:
                switchTool(.oval)
                return true
            case 21, 86:
                switchTool(.text)
                return true
            case 23, 87:
                switchTool(.arrow)
                return true
            case 22, 88:
                switchTool(.pen)
                return true
            case 26, 89:
                switchTool(.mosaic)
                return true
            case 53:
                editingTextID = nil
                return true
            case 36:
                editingTextID = nil
                return true
            case 51, 117:
                deleteTextCharacter()
                return true
            default:
                return insertTextCharacters(from: event)
            }
        }

        switch event.keyCode {
        case 18, 83:
            switchTool(.move)
            return true
        case 19, 84:
            switchTool(.rectangle)
            return true
        case 20, 85:
            switchTool(.oval)
            return true
        case 21, 86:
            switchTool(.text)
            return true
        case 23, 87:
            switchTool(.arrow)
            return true
        case 22, 88:
            switchTool(.pen)
            return true
        case 26, 89:
            switchTool(.mosaic)
            return true
        case 58, 61:
            cycleColor()
            return true
        case 36:
            if let rect = selectionRect { onCopy(rect, annotations) }
            return true
        case 53:
            onCancel()
            return true
        default:
            return false
        }
    }

    // MARK: - Window Detection

    private struct WindowInfo {
        let frame: CGRect
        let ownerName: String
        let layer: Int
    }

    private static func fetchWindowList() -> [WindowInfo] {
        let options: CGWindowListOption = CGWindowListOption(rawValue: 1)
        guard let windowList = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { info -> WindowInfo? in
            guard let bounds = info["kCGWindowBounds"] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat,
                  let layer = info["kCGWindowLayer"] as? Int,
                  layer == 0
            else {
                return nil
            }

            let owner = info["kCGWindowOwnerName"] as? String ?? ""
            guard !owner.contains("Fuguang") else { return nil }

            return WindowInfo(frame: CGRect(x: x, y: y, width: w, height: h), ownerName: owner, layer: layer)
        }
    }

    private static func findWindowRect(at point: CGPoint, in windows: [WindowInfo], quartzScreenOrigin: CGPoint) -> CGRect? {
        let quartzPoint = CGPoint(
            x: quartzScreenOrigin.x + point.x,
            y: quartzScreenOrigin.y + point.y
        )

        for window in windows {
            if window.frame.contains(quartzPoint) {
                return CGRect(
                    x: window.frame.origin.x - quartzScreenOrigin.x,
                    y: window.frame.origin.y - quartzScreenOrigin.y,
                    width: window.frame.width,
                    height: window.frame.height
                )
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func normalizeRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func cycleColor() {
        let colors = ScreenshotColorOption.allCases
        guard let index = colors.firstIndex(of: activeColor) else {
            activeColor = .green
            return
        }
        activeColor = colors[(index + 1) % colors.count]
    }

    private func pushAnnotationHistory() {
        guard annotationHistory.last != annotations else { return }
        annotationHistory.append(annotations)
        if annotationHistory.count > 50 {
            annotationHistory.removeFirst()
        }
    }

    private func undoLastAnnotationChange() {
        guard let previous = annotationHistory.popLast() else { return }
        annotations = previous
        selectedAnnotationID = nil
        editingTextID = nil
        draggingAnnotationID = nil
        annotationResizeEdge = []
        draftAnnotation = nil
    }

    private func insertTextCharacters(from event: NSEvent) -> Bool {
        guard let editingTextID,
              !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control),
              let characters = event.characters,
              !characters.isEmpty
        else {
            return false
        }

        pushAnnotationHistory()
        annotations = annotations.map { annotation in
            guard annotation.id == editingTextID else { return annotation }
            var copy = annotation
            copy.text.append(characters)
            return copy
        }
        return true
    }

    private func deleteTextCharacter() {
        guard let editingTextID else { return }
        pushAnnotationHistory()
        annotations = annotations.map { annotation in
            guard annotation.id == editingTextID else { return annotation }
            var copy = annotation
            if !copy.text.isEmpty {
                copy.text.removeLast()
            }
            return copy
        }
    }

    private func switchTool(_ tool: ScreenshotToolMode) {
        activeTool = tool
        resizeEdge = []
        annotationResizeEdge = []
        draftAnnotation = nil
        draggingAnnotationID = nil
        editingTextID = nil

        switch tool {
        case .move:
            NSCursor.openHand.set()
        case .rectangle, .oval, .arrow, .pen, .mosaic:
            NSCursor.crosshair.set()
        case .text:
            NSCursor.iBeam.set()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isOptionPressed = event.modifierFlags.contains(.option)
        if isOptionPressed && !wasOptionPressed {
            cycleColor()
        }
        wasOptionPressed = isOptionPressed
    }

    private func makeDraftAnnotation(from start: CGPoint, to end: CGPoint) -> ScreenshotAnnotation {
        let rect = normalizeRect(from: start, to: end)
        switch activeTool {
        case .rectangle:
            return ScreenshotAnnotation(kind: .rectangle, rect: rect, color: activeColor)
        case .oval:
            return ScreenshotAnnotation(kind: .oval, rect: rect, color: activeColor)
        case .arrow:
            return ScreenshotAnnotation(kind: .arrow, start: start, end: end, color: activeColor)
        case .pen:
            var points = draftAnnotation?.points ?? [start]
            points.append(end)
            return ScreenshotAnnotation(kind: .pen, points: points, color: activeColor)
        case .mosaic:
            return ScreenshotAnnotation(kind: .mosaic, rect: rect, color: activeColor)
        case .text:
            return ScreenshotAnnotation(kind: .text, rect: rect, text: "", color: activeColor)
        case .move:
            return ScreenshotAnnotation(kind: .rectangle, rect: rect, color: activeColor)
        }
    }

    private func isValidAnnotation(_ annotation: ScreenshotAnnotation) -> Bool {
        switch annotation.kind {
        case .text:
            return annotation.rect.width > dragThreshold && annotation.rect.height > dragThreshold
        case .arrow:
            return distance(from: annotation.start, to: annotation.end) > dragThreshold
        case .pen:
            return annotation.points.count > 2
        case .rectangle, .oval, .mosaic:
            return annotation.rect.width > dragThreshold && annotation.rect.height > dragThreshold
        }
    }

    private func offsetAnnotation(_ annotation: ScreenshotAnnotation, dx: CGFloat, dy: CGFloat) -> ScreenshotAnnotation {
        var copy = annotation
        copy.rect = copy.rect.offsetBy(dx: dx, dy: dy)
        copy.start = CGPoint(x: copy.start.x + dx, y: copy.start.y + dy)
        copy.end = CGPoint(x: copy.end.x + dx, y: copy.end.y + dy)
        copy.points = copy.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return copy
    }

    private func resizeAnnotation(_ annotation: ScreenshotAnnotation, edge: EdgeSet, dx: CGFloat, dy: CGFloat) -> ScreenshotAnnotation {
        let originalRect = annotationHitRect(annotation)
        let newRect = resizedRect(originalRect, edge: edge, dx: dx, dy: dy)
        var copy = annotation

        switch annotation.kind {
        case .text, .rectangle, .oval, .mosaic:
            copy.rect = newRect
        case .arrow:
            copy.start = mapPoint(annotation.start, from: originalRect, to: newRect)
            copy.end = mapPoint(annotation.end, from: originalRect, to: newRect)
            copy.rect = newRect
        case .pen:
            copy.points = annotation.points.map { mapPoint($0, from: originalRect, to: newRect) }
            copy.rect = newRect
        }

        return copy
    }

    private func resizedRect(_ rect: CGRect, edge: EdgeSet, dx: CGFloat, dy: CGFloat) -> CGRect {
        var newRect = rect
        if edge.contains(.left) {
            newRect.origin.x += dx
            newRect.size.width -= dx
        }
        if edge.contains(.right) {
            newRect.size.width += dx
        }
        if edge.contains(.top) {
            newRect.origin.y += dy
            newRect.size.height -= dy
        }
        if edge.contains(.bottom) {
            newRect.size.height += dy
        }

        if newRect.width < 8 {
            newRect.size.width = 8
        }
        if newRect.height < 8 {
            newRect.size.height = 8
        }
        return newRect
    }

    private func mapPoint(_ point: CGPoint, from oldRect: CGRect, to newRect: CGRect) -> CGPoint {
        let xRatio = oldRect.width > 0 ? (point.x - oldRect.minX) / oldRect.width : 0.5
        let yRatio = oldRect.height > 0 ? (point.y - oldRect.minY) / oldRect.height : 0.5
        return CGPoint(
            x: newRect.minX + xRatio * newRect.width,
            y: newRect.minY + yRatio * newRect.height
        )
    }

    private func hitTestAnnotation(at point: CGPoint) -> UUID? {
        for annotation in annotations.reversed() {
            if isPoint(point, hitting: annotation) {
                return annotation.id
            }
        }
        return nil
    }

    private func isPoint(_ point: CGPoint, hitting annotation: ScreenshotAnnotation) -> Bool {
        let tolerance: CGFloat = 8
        let rect = annotationHitRect(annotation)

        if selectedAnnotationID == annotation.id, annotation.kind == .text, rect.contains(point) {
            return true
        }

        switch annotation.kind {
        case .text, .rectangle, .mosaic:
            return isPointNearRectStroke(point, rect: rect, tolerance: tolerance)
        case .oval:
            return isPointNearOvalStroke(point, rect: rect, tolerance: tolerance)
        case .arrow:
            return distanceFromPoint(point, toSegmentStart: annotation.start, end: annotation.end) <= tolerance
        case .pen:
            guard annotation.points.count > 1 else { return false }
            for index in 1..<annotation.points.count {
                if distanceFromPoint(point, toSegmentStart: annotation.points[index - 1], end: annotation.points[index]) <= tolerance {
                    return true
                }
            }
            return false
        }
    }

    private func isPointNearRectStroke(_ point: CGPoint, rect: CGRect, tolerance: CGFloat) -> Bool {
        guard rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return false }
        let inner = rect.insetBy(dx: tolerance, dy: tolerance)
        return inner.isNull || !inner.contains(point)
    }

    private func isPointNearOvalStroke(_ point: CGPoint, rect: CGRect, tolerance: CGFloat) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2
        let ry = rect.height / 2
        let normalized = pow((point.x - center.x) / rx, 2) + pow((point.y - center.y) / ry, 2)
        let band = tolerance / max(min(rx, ry), 1)
        return abs(normalized - 1) <= band
    }

    private func distanceFromPoint(_ point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return distance(from: point, to: start)
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return distance(from: point, to: projection)
    }

    private func annotationHitRect(_ annotation: ScreenshotAnnotation) -> CGRect {
        switch annotation.kind {
        case .text, .rectangle, .oval, .mosaic:
            return annotation.rect
        case .arrow:
            return normalizeRect(from: annotation.start, to: annotation.end)
        case .pen:
            guard let first = annotation.points.first else { return .zero }
            return annotation.points.reduce(CGRect(origin: first, size: .zero)) { rect, point in
                rect.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
            }
        }
    }

    private func clampRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: max(0, min(rect.origin.x, screenSize.width - rect.width)),
            y: max(0, min(rect.origin.y, screenSize.height - rect.height)),
            width: rect.width,
            height: rect.height
        )
    }

    private func toolbarFrame(for rect: CGRect) -> CGRect {
        let width: CGFloat = 420
        let height: CGFloat = 48
        let preferredY = rect.maxY + 32
        let centerY = min(screenSize.height - height / 2 - 8, preferredY)
        return CGRect(
            x: rect.midX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }

    // MARK: - Edge Detection

    private struct EdgeSet: OptionSet {
        let rawValue: UInt
        static let left = EdgeSet(rawValue: 1 << 0)
        static let right = EdgeSet(rawValue: 1 << 1)
        static let top = EdgeSet(rawValue: 1 << 2)
        static let bottom = EdgeSet(rawValue: 1 << 3)
    }

    private func detectEdge(_ point: CGPoint, in rect: CGRect) -> EdgeSet {
        let t = edgeThreshold
        var edges = EdgeSet()
        if abs(point.x - rect.minX) < t && point.y >= rect.minY - t && point.y <= rect.maxY + t { edges.insert(.left) }
        if abs(point.x - rect.maxX) < t && point.y >= rect.minY - t && point.y <= rect.maxY + t { edges.insert(.right) }
        if abs(point.y - rect.minY) < t && point.x >= rect.minX - t && point.x <= rect.maxX + t { edges.insert(.top) }
        if abs(point.y - rect.maxY) < t && point.x >= rect.minX - t && point.x <= rect.maxX + t { edges.insert(.bottom) }
        return edges
    }

    // MARK: - Cursor

    private func updateCursor(at point: CGPoint, in rect: CGRect) {
        let edge = detectEdge(point, in: rect)
        if !edge.isEmpty {
            cursor(for: edge).set()
        } else if rect.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func cursor(for edge: EdgeSet) -> NSCursor {
        let isHorizontal = edge.contains(.left) || edge.contains(.right)
        let isVertical = edge.contains(.top) || edge.contains(.bottom)

        if isHorizontal && !isVertical {
            return .resizeLeftRight
        }

        if isVertical && !isHorizontal {
            return .resizeUpDown
        }

        // AppKit 没有公开的四角斜向 resize cursor，角落先使用十字光标作为调整大小提示。
        return .crosshair
    }
}

// MARK: - Subviews

private struct OverlayMaskView: View {
    let hasActiveRect: Bool
    let activeRect: CGRect

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            if hasActiveRect {
                let r = activeRect
                Rectangle()
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }
}

private struct SelectionBorderView: View {
    let activeRect: CGRect
    let isHover: Bool
    let showHandles: Bool

    private var handlePoints: [CGPoint] {
        let r = activeRect
        return [
            CGPoint(x: r.minX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.maxX, y: r.maxY),
            CGPoint(x: r.midX, y: r.minY),
            CGPoint(x: r.midX, y: r.maxY),
            CGPoint(x: r.minX, y: r.midY),
            CGPoint(x: r.maxX, y: r.midY)
        ]
    }

    var body: some View {
        ZStack {
            let r = activeRect
            let borderWidth: CGFloat = isHover ? 1 : 1.5
            let borderOpacity: Double = isHover ? 0.50 : 0.80

            Rectangle()
                .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: borderWidth)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)

            if showHandles {
                ForEach(Array(handlePoints.enumerated()), id: \.offset) { _, point in
                    HandleDotView()
                        .position(point)
                }
            }
        }
    }
}

private struct AnnotationLayerView: View {
    @Binding var annotations: [ScreenshotAnnotation]
    let draftAnnotation: ScreenshotAnnotation?
    let selectedAnnotationID: UUID?
    @Binding var editingTextID: UUID?

    var body: some View {
        ZStack {
            ForEach($annotations) { $annotation in
                annotationView($annotation)
            }

            if let draftAnnotation {
                staticAnnotationView(draftAnnotation, isSelected: false)
            }
        }
    }

    @ViewBuilder
    private func annotationView(_ annotation: Binding<ScreenshotAnnotation>) -> some View {
        let value = annotation.wrappedValue
        if value.kind == .text {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(editingTextID == value.id ? 0.28 : 0.10))
                    .stroke(value.id == selectedAnnotationID ? value.color.color : .clear, lineWidth: 1.5)

                HStack(spacing: 0) {
                    Text(value.text.isEmpty ? "请输入" : value.text)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(value.text.isEmpty ? value.color.color.opacity(0.45) : value.color.color)
                        .lineLimit(1)

                    if editingTextID == value.id {
                        Rectangle()
                            .fill(value.color.color)
                            .frame(width: 1.5, height: 22)
                            .padding(.leading, 2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
            }
            .frame(width: value.rect.width, height: value.rect.height)
            .position(x: value.rect.midX, y: value.rect.midY)
            .overlay { selectionOverlay(value, isSelected: value.id == selectedAnnotationID) }
        } else {
            staticAnnotationView(value, isSelected: value.id == selectedAnnotationID)
        }
    }

    @ViewBuilder
    private func staticAnnotationView(_ annotation: ScreenshotAnnotation, isSelected: Bool) -> some View {
        switch annotation.kind {
        case .text:
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .stroke(annotation.color.color.opacity(0.8), lineWidth: 1.5)

                Text(annotation.text.isEmpty ? "请输入" : annotation.text)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(annotation.text.isEmpty ? annotation.color.color.opacity(0.45) : annotation.color.color)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
            .frame(width: annotation.rect.width, height: annotation.rect.height)
            .position(x: annotation.rect.midX, y: annotation.rect.midY)
            .overlay { selectionOverlay(annotation, isSelected: isSelected) }
        case .arrow:
            ArrowAnnotationView(start: annotation.start, end: annotation.end, color: annotation.color.color)
                .overlay { selectionOverlay(annotation, isSelected: isSelected) }
        case .rectangle:
            Rectangle()
                .stroke(annotation.color.color, lineWidth: 3)
                .frame(width: annotation.rect.width, height: annotation.rect.height)
                .position(x: annotation.rect.midX, y: annotation.rect.midY)
                .overlay { selectionOverlay(annotation, isSelected: isSelected) }
        case .oval:
            Ellipse()
                .stroke(annotation.color.color, lineWidth: 3)
                .frame(width: annotation.rect.width, height: annotation.rect.height)
                .position(x: annotation.rect.midX, y: annotation.rect.midY)
                .overlay { selectionOverlay(annotation, isSelected: isSelected) }
        case .pen:
            PenAnnotationView(points: annotation.points, color: annotation.color.color)
                .overlay { selectionOverlay(annotation, isSelected: isSelected) }
        case .mosaic:
            MosaicAnnotationView(rect: annotation.rect)
                .overlay { selectionOverlay(annotation, isSelected: isSelected) }
        }
    }

    @ViewBuilder
    private func selectionOverlay(_ annotation: ScreenshotAnnotation, isSelected: Bool) -> some View {
        if isSelected {
            let rect = annotationVisualRect(annotation)
            ZStack {
                Rectangle()
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: max(rect.width, 20), height: max(rect.height, 20))
                    .position(x: rect.midX, y: rect.midY)

                ForEach(Array(handlePoints(for: rect).enumerated()), id: \.offset) { _, point in
                    HandleDotView()
                        .position(point)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func annotationVisualRect(_ annotation: ScreenshotAnnotation) -> CGRect {
        switch annotation.kind {
        case .text, .rectangle, .oval, .mosaic:
            return annotation.rect
        case .arrow:
            return CGRect(
                x: min(annotation.start.x, annotation.end.x),
                y: min(annotation.start.y, annotation.end.y),
                width: abs(annotation.end.x - annotation.start.x),
                height: abs(annotation.end.y - annotation.start.y)
            )
        case .pen:
            guard let first = annotation.points.first else { return .zero }
            return annotation.points.reduce(CGRect(origin: first, size: .zero)) { rect, point in
                rect.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
            }
        }
    }

    private func handlePoints(for rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY)
        ]
    }
}

private struct ArrowAnnotationView: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), lineWidth: 4)

            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowLength: CGFloat = 14
            let arrowAngle: CGFloat = .pi / 7
            let p1 = CGPoint(x: end.x - arrowLength * cos(angle - arrowAngle), y: end.y - arrowLength * sin(angle - arrowAngle))
            let p2 = CGPoint(x: end.x - arrowLength * cos(angle + arrowAngle), y: end.y - arrowLength * sin(angle + arrowAngle))
            var head = Path()
            head.move(to: end)
            head.addLine(to: p1)
            head.move(to: end)
            head.addLine(to: p2)
            context.stroke(head, with: .color(color), lineWidth: 4)
        }
    }
}

private struct PenAnnotationView: View {
    let points: [CGPoint]
    let color: Color

    var body: some View {
        Canvas { context, _ in
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct MosaicAnnotationView: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                Rectangle()
                    .fill(Color.white.opacity(0.20))
            }
            .overlay {
                GridPattern()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

private struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 8
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }
        return path
    }
}

private struct SizeLabelView: View {
    let rect: CGRect

    var body: some View {
        let w = Int(rect.width)
        let h = Int(rect.height)
        Text("\(w) × \(h)")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.55)))
            .position(x: rect.midX, y: rect.maxY + 18)
    }
}

private struct EditToolbarView: View {
    let rect: CGRect
    let screenHeight: CGFloat
    let activeTool: ScreenshotToolMode
    let activeColor: ScreenshotColorOption
    let onMove: () -> Void
    let onRectangle: () -> Void
    let onOval: () -> Void
    let onText: () -> Void
    let onArrow: () -> Void
    let onPen: () -> Void
    let onMosaic: () -> Void
    let onColor: () -> Void
    let onUndo: () -> Void
    let onSave: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void

    private var toolbarY: CGFloat {
        min(screenHeight - 27, rect.maxY + 32)
    }

    var body: some View {
        HStack(spacing: 1) {
            ToolbarItemButton(number: "1", title: "移动", systemImage: "arrow.up.and.down.and.arrow.left.and.right", isActive: activeTool == .move, action: onMove)
            ToolbarItemButton(number: "2", title: "方框", systemImage: "rectangle", isActive: activeTool == .rectangle, action: onRectangle)
            ToolbarItemButton(number: "3", title: "圆框", systemImage: "circle", isActive: activeTool == .oval, action: onOval)
            ToolbarItemButton(number: "4", title: "文本", systemImage: "text.bubble", isActive: activeTool == .text, action: onText)
            ToolbarItemButton(number: "5", title: "箭头", systemImage: "arrow.up.right", isActive: activeTool == .arrow, action: onArrow)
            ToolbarItemButton(number: "6", title: "画笔", systemImage: "pencil.tip", isActive: activeTool == .pen, action: onPen)
            ToolbarItemButton(number: "7", title: "马赛克", systemImage: "square.grid.3x3.fill", isActive: activeTool == .mosaic, action: onMosaic)

            ToolbarDivider()

            ColorOptionButton(color: activeColor.color, action: onColor)
            ToolbarItemButton(number: "⌘Z", title: "撤回", systemImage: "arrow.uturn.backward", isActive: false, action: onUndo)
            ToolbarItemButton(number: "↵", title: "复制", systemImage: "doc.on.clipboard", isActive: false, action: onCopy)

            ToolbarDivider()

            ToolbarItemButton(number: "↓", title: "保存", systemImage: "square.and.arrow.down", isActive: false, action: onSave)
            ToolbarItemButton(number: "esc", title: "关闭", systemImage: "xmark", isActive: false, action: onCancel)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.52))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .position(x: rect.midX, y: toolbarY)
    }
}

private struct ToolbarItemButton: View {
    let number: String
    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var showsShortcutNumber: Bool {
        number.allSatisfy { $0.isNumber }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                if showsShortcutNumber {
                    Text(number)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? .white : .black.opacity(0.50))
                        .frame(height: 7)
                }

                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isActive ? .white : .black.opacity(0.76))
                    .frame(height: 16)

                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isActive ? .white.opacity(0.95) : .black.opacity(0.58))
                    .opacity(isHovering ? 1 : 0)
                    .frame(height: 8)
            }
            .frame(width: 32, height: 38)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isActive ? Color.green.opacity(0.86) : (isHovering ? Color.white.opacity(0.90) : Color.clear))
            }
            .scaleEffect(isHovering ? 1.07 : 1.0)
            .offset(y: isHovering ? -2 : 0)
            .shadow(color: .black.opacity(isHovering ? 0.18 : 0), radius: 8, y: 4)
            .animation(.spring(response: 0.22, dampingFraction: 0.76), value: isHovering)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isActive)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct ColorOptionButton: View {
    let color: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Circle()
                    .fill(color)
                    .frame(width: 17, height: 17)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.18), lineWidth: 1)
                    }

                Text("颜色")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.black.opacity(0.58))
                    .opacity(isHovering ? 1 : 0)
                    .frame(height: 8)
            }
            .frame(width: 32, height: 38)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovering ? Color.white.opacity(0.90) : Color.clear)
            }
            .scaleEffect(isHovering ? 1.07 : 1.0)
            .offset(y: isHovering ? -2 : 0)
            .shadow(color: .black.opacity(isHovering ? 0.18 : 0), radius: 8, y: 4)
            .animation(.spring(response: 0.22, dampingFraction: 0.76), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.10))
            .frame(width: 1, height: 30)
            .padding(.horizontal, 2)
    }
}

private struct HandleDotView: View {
    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.90))
            .frame(width: 8, height: 8)
            .shadow(color: .black.opacity(0.30), radius: 2, y: 1)
    }
}
