import Cocoa

// MARK: - Session (entry point called by ScreenshotManager)

final class ScreenshotSession {
    var onFinished: (() -> Void)?
    private var overlayWindow: ScreenshotOverlayWindow?

    func start() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main!

        // Fetch window list and capture screen BEFORE showing overlay
        let windowFrames = fetchOnscreenWindowFrames(on: screen)
        guard let capturedImage = captureScreen(screen) else {
            NSLog("Menu3: screen capture failed — screen recording permission denied?")
            onFinished?()
            return
        }

        let win = ScreenshotOverlayWindow(screen: screen, image: capturedImage, windows: windowFrames)
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
        case .copy(let image):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        case .save(let image):
            showSavePanel(image: image)
        case .cancel:
            break
        }
    }

    private func showSavePanel(image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        panel.nameFieldStringValue = "截图 \(formatter.string(from: Date())).png"
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            NSApp.setActivationPolicy(.accessory)
            guard response == .OK, let url = panel.url else { return }
            if let data = image.pngData() { try? data.write(to: url) }
        }
    }
}

// MARK: - Screen helpers

struct OverlayWindowInfo {
    let rect: NSRect   // global NS coords (bottom-left origin)
    let ownerName: String?
}

private func fetchOnscreenWindowFrames(on screen: NSScreen) -> [OverlayWindowInfo] {
    guard let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] else { return [] }

    // CGWindow uses top-left origin on the primary screen;
    // NS uses bottom-left origin. Compute primary screen height for the flip.
    let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
        ?? NSScreen.main?.frame.height ?? screen.frame.height

    return list.compactMap { info -> OverlayWindowInfo? in
        guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let w = bounds["Width"], let h = bounds["Height"],
              w > 40, h > 40
        else { return nil }

        let nsRect = NSRect(x: x, y: primaryH - y - h, width: w, height: h)
        guard screen.frame.intersects(nsRect) else { return nil }
        return OverlayWindowInfo(rect: nsRect, ownerName: info[kCGWindowOwnerName as String] as? String)
    }
}

private func captureScreen(_ screen: NSScreen) -> NSImage? {
    let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
        ?? NSScreen.main?.frame.height ?? screen.frame.height
    // Convert NS screen rect → CG capture rect (top-left origin)
    let cgRect = CGRect(
        x: screen.frame.minX,
        y: primaryH - screen.frame.maxY,
        width: screen.frame.width,
        height: screen.frame.height
    )
    guard let cgImage = CGWindowListCreateImage(cgRect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution) else {
        return nil
    }
    return NSImage(cgImage: cgImage, size: screen.frame.size)
}

// MARK: - Overlay window

final class ScreenshotOverlayWindow: NSWindow {
    enum Result { case copy(NSImage), save(NSImage), cancel }
    var onResult: ((Result) -> Void)?

    init(screen: NSScreen, image: NSImage, windows: [OverlayWindowInfo]) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true

        let view = OverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            image: image, windows: windows, screen: screen
        )
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
    private var toolbar: ToolbarView?

    init(frame: NSRect, image: NSImage, windows: [OverlayWindowInfo], screen: NSScreen) {
        self.image = image
        self.windows = windows
        self.screen = screen
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(
            rect: frame,
            options: [.activeAlways, .mouseMoved, .cursorUpdate],
            owner: self, userInfo: nil
        ))
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Captured screen as background
        image.draw(in: bounds)

        // 2. Semi-transparent dark overlay
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        ctx.fill(bounds)

        // 3. Highlight / selection region
        switch mode {
        case .hovering:
            if let win = hoveredWindow {
                let r = toLocal(win.rect)
                clearOverlay(r, ctx: ctx)
                drawBorder(r, ctx: ctx, color: .systemBlue, width: 2)
            }
        case .dragging(let s, let e):
            let r = makeRect(s, e)
            clearOverlay(r, ctx: ctx)
            drawBorder(r, ctx: ctx, color: blueColor, width: 1.5)
            drawHandles(r, ctx: ctx)
            drawSizeLabel(r)
        case .selected(let r):
            clearOverlay(r, ctx: ctx)
            drawBorder(r, ctx: ctx, color: blueColor, width: 1.5)
            drawHandles(r, ctx: ctx)
        }
    }

    private let blueColor = NSColor(red: 0.18, green: 0.64, blue: 1.0, alpha: 1.0)

    private func clearOverlay(_ rect: NSRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to: rect)
        image.draw(in: bounds)
        ctx.restoreGState()
    }

    private func drawBorder(_ rect: NSRect, ctx: CGContext, color: NSColor, width: CGFloat) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
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
        ctx.setStrokeColor(blueColor.cgColor)
        ctx.setLineWidth(1.0)
        for p in pts {
            let h = CGRect(x: p.x - sz/2, y: p.y - sz/2, width: sz, height: sz)
            ctx.fillEllipse(in: h)
            ctx.strokeEllipse(in: h)
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

    // MARK: Mouse events

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if case .hovering = mode {
            let sp = NSPoint(x: screen.frame.minX + pt.x, y: screen.frame.minY + pt.y)
            hoveredWindow = windows.first { $0.rect.contains(sp) }
        }
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseDown(with event: NSEvent) {
        removeToolbar()
        let pt = convert(event.locationInWindow, from: nil)
        mode = .dragging(start: pt, current: pt)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if case .dragging(let s, _) = mode { mode = .dragging(start: s, current: pt) }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard case .dragging(let start, let end) = mode else { return }
        let rect = makeRect(start, end)
        if rect.width < 5 || rect.height < 5 {
            // Treat as click: auto-select the hovered window
            if let win = hoveredWindow {
                let r = toLocal(win.rect)
                mode = .selected(rect: r)
                showToolbar(for: r)
            } else {
                mode = .hovering
            }
        } else {
            mode = .selected(rect: rect)
            showToolbar(for: rect)
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // ESC — cancel
            onResult?(.cancel)
        case 36, 76: // Return / numpad Enter — copy selected region
            if case .selected(let r) = mode, let img = cropImage(to: r) {
                onResult?(.copy(img))
            }
        default:
            break
        }
    }

    // MARK: Toolbar

    private func showToolbar(for rect: NSRect) {
        removeToolbar()
        let tbW: CGFloat = 200, tbH: CGFloat = 38
        var tx = rect.maxX - tbW
        var ty = rect.minY - tbH - 8
        if tx < 4 { tx = 4 }
        if tx + tbW > bounds.maxX - 4 { tx = bounds.maxX - tbW - 4 }
        if ty < 4 { ty = rect.maxY + 8 }
        if ty + tbH > bounds.maxY - 4 { ty = bounds.maxY - tbH - 4 }

        let tb = ToolbarView(frame: NSRect(x: tx, y: ty, width: tbW, height: tbH))
        tb.onCopy = { [weak self] in
            guard case .selected(let r) = self?.mode, let img = self?.cropImage(to: r) else { return }
            self?.onResult?(.copy(img))
        }
        tb.onSave = { [weak self] in
            guard case .selected(let r) = self?.mode, let img = self?.cropImage(to: r) else { return }
            self?.onResult?(.save(img))
        }
        tb.onCancel = { [weak self] in
            self?.mode = .hovering
            self?.hoveredWindow = nil
            self?.removeToolbar()
            self?.needsDisplay = true
        }
        addSubview(tb)
        toolbar = tb
    }

    private func removeToolbar() { toolbar?.removeFromSuperview(); toolbar = nil }

    // MARK: Helpers

    private func makeRect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func toLocal(_ nsRect: NSRect) -> NSRect {
        NSRect(x: nsRect.minX - screen.frame.minX, y: nsRect.minY - screen.frame.minY,
               width: nsRect.width, height: nsRect.height)
    }

    /// Crops the pre-captured full-screen image to the selected local rect.
    /// Handles Retina (2x) scale correctly.
    private func cropImage(to localRect: NSRect) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let sx = CGFloat(cg.width)  / image.size.width
        let sy = CGFloat(cg.height) / image.size.height
        // CGImage has (0,0) at top-left; NSView has (0,0) at bottom-left → flip Y
        let cgRect = CGRect(
            x: localRect.minX * sx,
            y: (image.size.height - localRect.maxY) * sy,
            width: localRect.width  * sx,
            height: localRect.height * sy
        )
        guard let cropped = cg.cropping(to: cgRect) else { return nil }
        return NSImage(cgImage: cropped, size: localRect.size)
    }
}

// MARK: - Action toolbar

private final class ToolbarView: NSView {
    var onCopy:   (() -> Void)?
    var onSave:   (() -> Void)?
    var onCancel: (() -> Void)?

    override init(frame: NSRect) { super.init(frame: frame); setupUI() }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.10, alpha: 0.93).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10).fill()
    }

    private func setupUI() {
        let copyBtn   = makeBtn("复制", icon: "doc.on.clipboard",       sel: #selector(doCopy))
        let saveBtn   = makeBtn("保存", icon: "square.and.arrow.down",   sel: #selector(doSave))
        let cancelBtn = makeBtn("取消", icon: "xmark",                   sel: #selector(doCancel))
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor

        let stack = NSStackView(views: [copyBtn, saveBtn, sep, cancelBtn])
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            sep.widthAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func makeBtn(_ title: String, icon: String, sel: Selector) -> NSButton {
        let b = NSButton()
        b.title = " " + title
        b.bezelStyle = .regularSquare
        b.isBordered = false
        b.font = .systemFont(ofSize: 12)
        b.contentTintColor = .white
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            b.image = img; b.imagePosition = .imageLeft
        }
        b.target = self; b.action = sel
        return b
    }

    @objc private func doCopy()   { onCopy?() }
    @objc private func doSave()   { onSave?() }
    @objc private func doCancel() { onCancel?() }
}

// MARK: - NSImage helper

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
