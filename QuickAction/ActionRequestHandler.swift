import Cocoa
import UniformTypeIdentifiers

/// No-UI Action Extension that shows a context menu with RightMenu actions.
/// Works in all Finder directories including iCloud-managed ones.
class ActionRequestHandler: NSObject, NSExtensionRequestHandling {

    var extensionContext: NSExtensionContext?

    func beginRequest(with context: NSExtensionContext) {
        self.extensionContext = context

        // Extract file URLs from the extension input
        let urls = extractFileURLs(from: context)
        guard !urls.isEmpty else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        // Determine the target directory from the first selected item
        let targetDirectory: URL = {
            let first = urls[0]
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir), isDir.boolValue {
                return first
            }
            return first.deletingLastPathComponent()
        }()

        // Build and show popup menu at mouse location
        let menu = NSMenu(title: "RightMenu")

        // Copy actions
        if urls.count > 1 {
            addItem(to: menu, title: "复制所有文件名", action: #selector(copyAllNames), target: self)
            addItem(to: menu, title: "复制所有文件路径", action: #selector(copyAllPaths), target: self)
        } else {
            addItem(to: menu, title: "复制文件名", action: #selector(copyName), target: self)
            addItem(to: menu, title: "复制文件路径", action: #selector(copyPath), target: self)
        }

        menu.addItem(.separator())

        // New file / clipboard actions
        addItem(to: menu, title: "新建文本文件", action: #selector(newTextFile), target: self)
        if hasClipboardFiles() {
            addItem(to: menu, title: "保存文件 来自粘贴板", action: #selector(saveClipboardFiles), target: self)
        }
        if hasClipboardText() {
            addItem(to: menu, title: "保存成文本文件", action: #selector(saveClipboardText), target: self)
        }

        // Store context for action handlers
        objc_setAssociatedObject(self, &AssociatedKeys.urls, urls, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(self, &AssociatedKeys.directory, targetDirectory, .OBJC_ASSOCIATION_RETAIN)

        // Show popup menu at mouse location
        DispatchQueue.main.async {
            let location = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) }) {
                let point = NSPoint(x: location.x - screen.frame.origin.x,
                                    y: location.y - screen.frame.origin.y)
                menu.popUp(positioning: nil, at: point, in: nil)
            } else {
                menu.popUp(positioning: nil, at: .zero, in: nil)
            }
            // If menu dismissed without action
            context.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    // MARK: - Actions

    @objc private func copyName() {
        guard let urls = storedURLs else { return finish(); }
        let name = urls[0].lastPathComponent
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
        finish()
    }

    @objc private func copyPath() {
        guard let urls = storedURLs else { return finish(); }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls[0].path, forType: .string)
        finish()
    }

    @objc private func copyAllNames() {
        guard let urls = storedURLs else { return finish(); }
        let names = urls.map { $0.lastPathComponent }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(names, forType: .string)
        finish()
    }

    @objc private func copyAllPaths() {
        guard let urls = storedURLs else { return finish(); }
        let paths = urls.map { $0.path }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
        finish()
    }

    @objc private func newTextFile() {
        guard let dir = storedDirectory else { return finish(); }
        let fileURL = nextAvailableURL(in: dir, name: "untitled", ext: "txt")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        finish()
    }

    @objc private func saveClipboardFiles() {
        guard let dir = storedDirectory else { return finish(); }
        let pb = NSPasteboard.general
        guard let fileURLs = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return finish(); }

        var saved: [URL] = []
        for srcURL in fileURLs {
            let destURL = nextAvailableURL(in: dir, name: srcURL.deletingPathExtension().lastPathComponent,
                                           ext: srcURL.pathExtension)
            try? FileManager.default.copyItem(at: srcURL, to: destURL)
            saved.append(destURL)
        }
        if !saved.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(saved)
        }
        finish()
    }

    @objc private func saveClipboardText() {
        guard let dir = storedDirectory else { return finish(); }
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string) else { return finish(); }
        let fileURL = nextAvailableURL(in: dir, name: "untitled", ext: "txt")
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        finish()
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector, target: AnyObject) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = target
    }

    // MARK: - Helpers

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private var storedURLs: [URL]? {
        objc_getAssociatedObject(self, &AssociatedKeys.urls) as? [URL]
    }

    private var storedDirectory: URL? {
        objc_getAssociatedObject(self, &AssociatedKeys.directory) as? URL
    }

    private func extractFileURLs(from context: NSExtensionContext) -> [URL] {
        var urls: [URL] = []
        for item in context.inputItems as? [NSExtensionItem] ?? [] {
            for attachment in item.attachments ?? [] {
                if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    let semaphore = DispatchSemaphore(value: 0)
                    attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                        if let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                            urls.append(url)
                        } else if let url = data as? URL {
                            urls.append(url)
                        }
                        semaphore.signal()
                    }
                    semaphore.wait()
                }
            }
        }
        return urls
    }

    private func hasClipboardFiles() -> Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private func hasClipboardText() -> Bool {
        NSPasteboard.general.string(forType: .string) != nil
    }

    private func nextAvailableURL(in directory: URL, name: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(name).appendingPathExtension(ext)
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    private struct AssociatedKeys {
        static var urls = "storedURLs"
        static var directory = "storedDirectory"
    }
}
