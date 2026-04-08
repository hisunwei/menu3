import Cocoa

// MARK: - Annotation data

enum AnnotationMode: Equatable, Hashable {
    case none, brush, text
}

private struct StrokeAnnotation {
    var path: NSBezierPath
    var color: NSColor
    var width: CGFloat
}

private struct TextAnnotation {
    var text: String
    var position: NSPoint   // view-coordinate baseline origin
    var color: NSColor
    var fontSize: CGFloat
}

private enum AnnotationItem {
    case stroke(StrokeAnnotation)
    case text(TextAnnotation)
}

// MARK: - Session (public entry point)

final class ScreenshotSession {
    var onFinished: (() -> Void)?
    private var overlayWindow: ScreenshotOverlayWindow?

    func start() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main!
        let windowFrames = fetchOnscreenWindowFrames(on: screen)
        guard let captured = captureScreen(screen) else {
            NSLog("Menu3: screen capture failed — screen recording permission denied?")
            onFinished?()
            return
        }
        let win = ScreenshotOverlayWindow(screen: screen, image: captured, windows: windowFrames)
        weak var weakWin = win
        win.onResult = { [weak self] result in
            weakWin?.orderOut(nil)
            self?.overlayWindow = nil
            self?.handleResult(result)
            self?.onFinished?()
        }
        overlayWindow = win
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(win.contentView)
    }

    private func handleResult(_ result: ScreenshotOverlayWindow.Result) {
        switch result {
        case .copy(let img):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
        case .save(let img):
            showSavePanel(img)
        case .cancel:
            break
        }
    }

    private func showSavePanel(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH.mm.ss"
        panel.nameFieldStringValue = "截图 \(fmt.string(from: Date())).png"
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            NSApp.setActivationPolicy(.accessory)
            guard response == .OK, let url = panel.url, let data = image.pngData() else { return }
            try? data.write(to: url)
        }
    }
}

// MARK: - Screen helpers

struct OverlayWindowInfo {
    let rect: NSRect
    let ownerName: String?
}

private func fetchOnscreenWindowFrames(on screen: NSScreen) -> [OverlayWindowInfo] {
    guard let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] else { return [] }
    let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
        ?? NSScreen.main?.frame.height ?? screen.frame.height
    return list.compactMap { info -> OverlayWindowInfo? in
        guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
              let b = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"],
              w > 40, h > 40 else { return nil }
        let nsRect = NSRect(x: x, y: primaryH - y - h, width: w, height: h)
        guard screen.frame.intersects(nsRect) else { return nil }
        return OverlayWindowInfo(rect: nsRect, ownerName: info[kCGWindowOwnerName as String] as? String)
    }
}

private func captureScreen(_ screen: NSScreen) -> NSImage? {
    let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
        ?? NSScreen.main?.frame.height ?? screen.frame.height
    let cgRect = CGRect(x: screen.frame.minX, y: primaryH - screen.frame.maxY,
                        width: screen.frame.width, height: screen.frame.height)
    guard let cg = CGWindowListCreateImage(cgRect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
    else { return nil }
    return NSImage(cgImage: cg, size: screen.frame.size)
}

// MARK: - Overlay window

final class ScreenshotOverlayWindow: NSWindow {
    enum Result { case copy(NSImage), save(NSImage), cancel }
    var onResult: ((Result) -> Void)?

    init(screen: NSScreen, image: NSImage, windows: [OverlayWindowInfo]) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true; hasShadow = false; backgroundColor = .black
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size),
                               image: image, windows: windows, screen: screen)
        view.onResult = { [weak self] r in self?.onResult?(r) }
        contentView = view
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Overlay view

private final class OverlayView: NSView {
    var onResult: ((ScreenshotOverlayWindow.Result) -> Void)?

    private enum Mode {
        case hovering
        case dragging(start: NSPoint, current: NSPoint)
        case selected(rect: NSRect)
    }

    private let image: NSImage
    private let windows: [OverlayWindowInfo]
    private let screen: NSScreen
    private var mode: Mode = .hovering
    private var hoveredWindow: OverlayWindowInfo?

    private var annotationMode: AnnotationMode = .none
    private var annotations: [AnnotationItem] = []
    private var currentStroke: StrokeAnnotation?
    private var selectedColor: NSColor = .systemRed
    private var brushWidth: CGFloat = 3
    private var activeTextField: NSTextField?
    private var toolbar: AnnotationToolbar?

    private let accentColor = NSColor(red: 0.18, green: 0.64, blue: 1.0, alpha: 1.0)

    init(frame: NSRect, image: NSImage, windows: [OverlayWindowInfo], screen: NSScreen) {
        self.image = image; self.windows = windows; self.screen = screen
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: frame,
            options: [.activeAlways, .mouseMoved, .cursorUpdate], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        image.draw(in: bounds)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        ctx.fill(bounds)

        switch mode {
        case .hovering:
            if let win = hoveredWindow {
                let r = toLocal(win.rect)
                clearOverlay(r, ctx: ctx)
                strokeBorder(r, ctx: ctx, color: .systemBlue, width: 2)
            }
        case .dragging(let s, let e):
            let r = makeRect(s, e)
            clearOverlay(r, ctx: ctx)
            strokeBorder(r, ctx: ctx, color: accentColor, width: 1.5)
            drawHandles(r, ctx: ctx)
            drawSizeLabel(r)
        case .selected(let r):
            clearOverlay(r, ctx: ctx)
            drawAnnotations(clippedTo: r, ctx: ctx)
            drawCurrentStroke(clippedTo: r, ctx: ctx)
            strokeBorder(r, ctx: ctx, color: accentColor, width: 1.5)
            if annotationMode == .none { drawHandles(r, ctx: ctx) }
        }
    }

    private func clearOverlay(_ rect: NSRect, ctx: CGContext) {
        ctx.saveGState(); ctx.clip(to: rect); image.draw(in: bounds); ctx.restoreGState()
    }

    private func strokeBorder(_ rect: NSRect, ctx: CGContext, color: NSColor, width: CGFloat) {
        ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(width)
        ctx.stroke(rect.insetBy(dx: width / 2, dy: width / 2))
    }

    private func drawHandles(_ rect: NSRect, ctx: CGContext) {
        let sz: CGFloat = 6
        let pts: [NSPoint] = [
            .init(x: rect.minX, y: rect.minY), .init(x: rect.midX, y: rect.minY), .init(x: rect.maxX, y: rect.minY),
            .init(x: rect.minX, y: rect.midY),                                     .init(x: rect.maxX, y: rect.midY),
            .init(x: rect.minX, y: rect.maxY), .init(x: rect.midX, y: rect.maxY), .init(x: rect.maxX, y: rect.maxY),
        ]
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(accentColor.cgColor)
        ctx.setLineWidth(1)
        for p in pts {
            let h = CGRect(x: p.x - sz/2, y: p.y - sz/2, width: sz, height: sz)
            ctx.fillEllipse(in: h); ctx.strokeEllipse(in: h)
        }
    }

    private func drawSizeLabel(_ rect: NSRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let ts = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 5
        var lx = rect.minX
        var ly = rect.minY - ts.height - pad * 2 - 4
        if ly < 2 { ly = rect.maxY + 4 }
        if lx + ts.width + pad * 2 > bounds.maxX { lx = bounds.maxX - ts.width - pad * 2 }
        let bg = NSRect(x: lx, y: ly, width: ts.width + pad * 2, height: ts.height + pad * 2)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: NSPoint(x: lx + pad, y: ly + pad), withAttributes: attrs)
    }

    private func drawAnnotations(clippedTo rect: NSRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to: rect)
        for item in annotations {
            switch item {
            case .stroke(let s):
                s.color.setStroke()
                s.path.lineWidth = s.width
                s.path.lineCapStyle = .round; s.path.lineJoinStyle = .round
                s.path.stroke()
            case .text(let t):
                (t.text as NSString).draw(at: t.position, withAttributes: textAttrs(t.color, t.fontSize))
            }
        }
        ctx.restoreGState()
    }

    private func drawCurrentStroke(clippedTo rect: NSRect, ctx: CGContext) {
        guard let s = currentStroke else { return }
        ctx.saveGState(); ctx.clip(to: rect)
        s.color.setStroke()
        s.path.lineWidth = s.width
        s.path.lineCapStyle = .round; s.path.lineJoinStyle = .round
        s.path.stroke()
        ctx.restoreGState()
    }

    private func textAttrs(_ color: NSColor, _ size: CGFloat) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        shadow.shadowBlurRadius = 2
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        return [.font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: color, .shadow: shadow]
    }

    // MARK: Mouse events

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if case .hovering = mode {
            let sp = NSPoint(x: screen.frame.minX + pt.x, y: screen.frame.minY + pt.y)
            hoveredWindow = windows.first { $0.rect.contains(sp) }
        }
        updateCursor(); needsDisplay = true
    }
    override func cursorUpdate(with event: NSEvent) { updateCursor() }

    private func updateCursor() {
        if case .selected = mode {
            switch annotationMode {
            case .brush: NSCursor.crosshair.set()
            case .text:  NSCursor.iBeam.set()
            case .none:  NSCursor.crosshair.set()
            }
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if case .selected(let rect) = mode {
            if let tb = toolbar, tb.frame.contains(pt) { return }
            if rect.contains(pt) {
                switch annotationMode {
                case .brush: startBrushStroke(at: pt)
                case .text:  startTextInput(at: pt)
                case .none:  break
                }
            } else {
                commitTextInput()
                removeToolbar()
                annotations.removeAll(); annotationMode = .none
                mode = .dragging(start: pt, current: pt); needsDisplay = true
            }
        } else {
            removeToolbar()
            mode = .dragging(start: pt, current: pt); needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        switch mode {
        case .dragging(let s, _):
            mode = .dragging(start: s, current: pt); needsDisplay = true
        case .selected:
            if annotationMode == .brush { extendBrushStroke(to: pt); needsDisplay = true }
        default: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch mode {
        case .dragging(let start, let end):
            let rect = makeRect(start, end)
            if rect.width < 5 || rect.height < 5 {
                if let win = hoveredWindow {
                    let r = toLocal(win.rect); mode = .selected(rect: r); showToolbar(for: r)
                } else { mode = .hovering }
            } else {
                mode = .selected(rect: rect); showToolbar(for: rect)
            }
            needsDisplay = true
        case .selected:
            if annotationMode == .brush { finalizeBrushStroke(); needsDisplay = true }
        default: break
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // ESC
            if annotationMode != .none {
                commitTextInput(); annotationMode = .none; toolbar?.setMode(.none); needsDisplay = true
            } else { onResult?(.cancel) }
        case 36, 76: // Return / Enter → copy
            if case .selected(let r) = mode, let img = composeImage(selectionRect: r) {
                onResult?(.copy(img))
            }
        case 6: // z key → ⌘Z undo
            if event.modifierFlags.contains(.command) { undoLast() }
        default: break
        }
    }

    // MARK: Toolbar

    private func showToolbar(for rect: NSRect) {
        removeToolbar()
        let tbW: CGFloat = 420, tbH: CGFloat = 44
        var tx = rect.maxX - tbW, ty = rect.minY - tbH - 8
        if tx < 4 { tx = 4 }
        if tx + tbW > bounds.maxX - 4 { tx = bounds.maxX - tbW - 4 }
        if ty < 4 { ty = rect.maxY + 8 }
        if ty + tbH > bounds.maxY - 4 { ty = bounds.maxY - tbH - 4 }

        let tb = AnnotationToolbar(frame: NSRect(x: tx, y: ty, width: tbW, height: tbH))
        tb.onModeChanged = { [weak self] m in
            self?.commitTextInput(); self?.annotationMode = m; self?.needsDisplay = true
        }
        tb.onColorChanged = { [weak self] c in
            self?.selectedColor = c; self?.activeTextField?.textColor = c
        }
        tb.onBrushSizeChanged = { [weak self] w in self?.brushWidth = w }
        tb.onUndo = { [weak self] in self?.undoLast() }
        tb.onCopy = { [weak self] in
            guard case .selected(let r) = self?.mode, let img = self?.composeImage(selectionRect: r) else { return }
            self?.onResult?(.copy(img))
        }
        tb.onSave = { [weak self] in
            guard case .selected(let r) = self?.mode, let img = self?.composeImage(selectionRect: r) else { return }
            self?.onResult?(.save(img))
        }
        tb.onCancel = { [weak self] in
            self?.commitTextInput(); self?.mode = .hovering; self?.hoveredWindow = nil
            self?.annotations.removeAll(); self?.annotationMode = .none
            self?.removeToolbar(); self?.needsDisplay = true
        }
        addSubview(tb); toolbar = tb
    }

    private func removeToolbar() { toolbar?.removeFromSuperview(); toolbar = nil }

    // MARK: Brush

    private func startBrushStroke(at pt: NSPoint) {
        let path = NSBezierPath(); path.move(to: pt)
        currentStroke = StrokeAnnotation(path: path, color: selectedColor, width: brushWidth)
    }
    private func extendBrushStroke(to pt: NSPoint) { currentStroke?.path.line(to: pt) }
    private func finalizeBrushStroke() {
        if let s = currentStroke, s.path.elementCount > 1 { annotations.append(.stroke(s)) }
        currentStroke = nil
    }

    // MARK: Text

    private func startTextInput(at pt: NSPoint) {
        commitTextInput()
        let fontSize: CGFloat = 16
        let tf = NSTextField(frame: NSRect(x: pt.x, y: pt.y - fontSize - 4, width: 220, height: fontSize + 10))
        tf.backgroundColor = .clear; tf.drawsBackground = false
        tf.isBordered = false; tf.isBezeled = false; tf.focusRingType = .none
        tf.textColor = selectedColor
        tf.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        tf.isEditable = true; tf.stringValue = ""; tf.delegate = self
        addSubview(tf); window?.makeFirstResponder(tf); activeTextField = tf
    }

    private func commitTextInput() {
        guard let tf = activeTextField else { return }
        let text = tf.stringValue.trimmingCharacters(in: .whitespaces)
        activeTextField = nil
        if !text.isEmpty {
            annotations.append(.text(TextAnnotation(
                text: text,
                position: NSPoint(x: tf.frame.minX, y: tf.frame.minY + 2),
                color: selectedColor, fontSize: 16)))
        }
        tf.removeFromSuperview()
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(self) }
        needsDisplay = true
    }

    // MARK: Undo

    private func undoLast() {
        if activeTextField != nil { commitTextInput() }
        else if !annotations.isEmpty { annotations.removeLast(); needsDisplay = true }
    }

    // MARK: Image composition

    private func composeImage(selectionRect: NSRect) -> NSImage? {
        let pendingText: TextAnnotation?
        if let tf = activeTextField, !tf.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            pendingText = TextAnnotation(
                text: tf.stringValue,
                position: NSPoint(x: tf.frame.minX, y: tf.frame.minY + 2),
                color: selectedColor, fontSize: 16)
        } else { pendingText = nil }

        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let sx = CGFloat(cg.width) / image.size.width
        let sy = CGFloat(cg.height) / image.size.height
        let cgCrop = CGRect(x: selectionRect.minX * sx,
                            y: (image.size.height - selectionRect.maxY) * sy,
                            width: selectionRect.width * sx, height: selectionRect.height * sy)
        guard let cropped = cg.cropping(to: cgCrop) else { return nil }

        let result = NSImage(size: selectionRect.size)
        result.lockFocus()
        NSImage(cgImage: cropped, size: selectionRect.size)
            .draw(in: NSRect(origin: .zero, size: selectionRect.size))

        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        ctx.translateBy(x: -selectionRect.minX, y: -selectionRect.minY)
        let allItems = annotations + (pendingText.map { [.text($0)] } ?? [])
        for item in allItems {
            switch item {
            case .stroke(let s):
                s.color.setStroke()
                s.path.lineWidth = s.width
                s.path.lineCapStyle = .round; s.path.lineJoinStyle = .round
                s.path.stroke()
            case .text(let t):
                (t.text as NSString).draw(at: t.position, withAttributes: textAttrs(t.color, t.fontSize))
            }
        }
        ctx.restoreGState()
        result.unlockFocus()
        return result
    }

    // MARK: Helpers

    private func makeRect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(b.x-a.x), height: abs(b.y-a.y))
    }
    private func toLocal(_ r: NSRect) -> NSRect {
        NSRect(x: r.minX - screen.frame.minX, y: r.minY - screen.frame.minY, width: r.width, height: r.height)
    }
}

// MARK: - NSTextFieldDelegate

extension OverlayView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === activeTextField else { return }
        commitTextInput()
    }
}

// MARK: - Annotation toolbar

private final class AnnotationToolbar: NSView {
    var onModeChanged:      ((AnnotationMode) -> Void)?
    var onColorChanged:     ((NSColor) -> Void)?
    var onBrushSizeChanged: ((CGFloat) -> Void)?
    var onUndo:    (() -> Void)?
    var onCopy:    (() -> Void)?
    var onSave:    (() -> Void)?
    var onCancel:  (() -> Void)?

    private var currentMode: AnnotationMode = .none
    private var modeButtons: [AnnotationMode: NSButton] = [:]
    private var swatches: [ColorSwatchView] = []
    private var sizeButtons: [NSButton] = []

    private let brushSizes: [CGFloat] = [2, 4, 8]
    private var selectedBrushSize: CGFloat = 3

    private let paletteColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow,
        .systemGreen, .systemCyan, .systemBlue,
        .systemPurple, .white, .black
    ]

    override init(frame: NSRect) { super.init(frame: frame); setupUI() }
    required init?(coder: NSCoder) { nil }

    func setMode(_ mode: AnnotationMode) {
        currentMode = mode
        modeButtons.forEach { $0.value.state = $0.key == mode ? .on : .off }
        updateSizeButtonsVisibility()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.10, alpha: 0.93).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10).fill()
    }

    private func setupUI() {
        // --- Mode buttons ---
        let brushBtn = makeModeBtn(icon: "paintbrush.pointed", mode: .brush)
        let textBtn  = makeModeBtn(icon: "character.cursor.ibeam", mode: .text)

        // --- Color swatches ---
        let colorViews: [NSView] = paletteColors.map { color in
            let sw = ColorSwatchView(color: color)
            sw.onTapped = { [weak self] in
                self?.swatches.forEach { $0.isSelected = $0.color.isEqual(color) }
                self?.onColorChanged?(color)
            }
            swatches.append(sw)
            return sw
        }
        swatches.first?.isSelected = true

        // --- Brush size buttons ---
        let sizeViews: [NSView] = brushSizes.enumerated().map { idx, sz in
            let btn = NSButton()
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.title = ""
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            btn.setButtonType(.pushOnPushOff)
            btn.state = idx == 1 ? .on : .off   // default: medium
            btn.tag = idx
            btn.target = self
            btn.action = #selector(sizeButtonTapped(_:))
            // Show as a filled dot of increasing size
            let dotSz = max(4, sz * 1.5)
            let img = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
                NSColor.white.withAlphaComponent(0.8).setFill()
                let r = NSRect(x: (20 - dotSz)/2, y: (20 - dotSz)/2, width: dotSz, height: dotSz)
                NSBezierPath(ovalIn: r).fill()
                return true
            }
            btn.image = img
            btn.widthAnchor.constraint(equalToConstant: 24).isActive = true
            sizeButtons.append(btn)
            return btn
        }
        selectedBrushSize = brushSizes[1]

        // --- Undo, separators, action buttons ---
        let undoBtn   = makeIconBtn(icon: "arrow.uturn.backward", action: #selector(doUndo))
        let copyBtn   = makeTextBtn(title: "复制", icon: "doc.on.clipboard",    action: #selector(doCopy))
        let saveBtn   = makeTextBtn(title: "保存", icon: "square.and.arrow.down", action: #selector(doSave))
        let cancelBtn = makeIconBtn(icon: "xmark", action: #selector(doCancel))
        cancelBtn.contentTintColor = NSColor(white: 0.7, alpha: 1)

        let sep1 = makeSep(), sep2 = makeSep(), sep3 = makeSep(), sep4 = makeSep()

        var allViews: [NSView] = [brushBtn, textBtn, sep1]
        allViews += colorViews
        allViews += [sep2]
        allViews += sizeViews
        allViews += [sep3, undoBtn, sep4, copyBtn, saveBtn, cancelBtn]

        let stack = NSStackView(views: allViews)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.distribution = .fill
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func makeModeBtn(icon: String, mode: AnnotationMode) -> NSButton {
        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        btn.bezelStyle = .regularSquare; btn.isBordered = false
        btn.contentTintColor = .white
        btn.setButtonType(.pushOnPushOff); btn.state = .off
        btn.widthAnchor.constraint(equalToConstant: 28).isActive = true
        btn.tag = mode == .brush ? 1 : 2
        btn.target = self; btn.action = #selector(modeButtonTapped(_:))
        modeButtons[mode] = btn
        return btn
    }

    private func makeIconBtn(icon: String, action: Selector) -> NSButton {
        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        btn.bezelStyle = .regularSquare; btn.isBordered = false
        btn.contentTintColor = .white
        btn.widthAnchor.constraint(equalToConstant: 28).isActive = true
        btn.target = self; btn.action = action
        return btn
    }

    private func makeTextBtn(title: String, icon: String, action: Selector) -> NSButton {
        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.title = " " + title
        btn.bezelStyle = .regularSquare; btn.isBordered = false
        btn.font = .systemFont(ofSize: 12); btn.contentTintColor = .white
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            btn.image = img; btn.imagePosition = .imageLeft
        }
        btn.target = self; btn.action = action
        return btn
    }

    private func makeSep() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func updateSizeButtonsVisibility() {
        let show = currentMode == .brush
        sizeButtons.forEach { $0.isHidden = !show }
    }

    @objc private func modeButtonTapped(_ sender: NSButton) {
        let tapped: AnnotationMode = sender.tag == 1 ? .brush : .text
        let next: AnnotationMode = currentMode == tapped ? .none : tapped
        setMode(next)
        onModeChanged?(next)
    }

    @objc private func sizeButtonTapped(_ sender: NSButton) {
        sizeButtons.forEach { $0.state = .off }
        sender.state = .on
        let sz = brushSizes[sender.tag]
        selectedBrushSize = sz
        onBrushSizeChanged?(sz)
    }

    @objc private func doUndo()   { onUndo?() }
    @objc private func doCopy()   { onCopy?() }
    @objc private func doSave()   { onSave?() }
    @objc private func doCancel() { onCancel?() }
}

// MARK: - Color swatch view

private final class ColorSwatchView: NSView {
    let color: NSColor
    var isSelected: Bool = false { didSet { needsDisplay = true } }
    var onTapped: (() -> Void)?

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 18).isActive = true
        heightAnchor.constraint(equalToConstant: 18).isActive = true
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        // Outer selection ring
        if isSelected {
            NSColor.white.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 2; ring.stroke()
        }
        // Filled circle
        let inner = bounds.insetBy(dx: isSelected ? 3 : 1, dy: isSelected ? 3 : 1)
        color.setFill()
        NSBezierPath(ovalIn: inner).fill()
        // Subtle border
        NSColor.white.withAlphaComponent(0.4).setStroke()
        let border = NSBezierPath(ovalIn: inner.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 0.5; border.stroke()
    }

    override func mouseDown(with event: NSEvent) { isSelected = true; onTapped?() }
}

// MARK: - NSImage helper

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
