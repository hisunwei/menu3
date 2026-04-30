import Cocoa

enum FileMoveOperation {
    case copy
    case move
}

/// Manages a pending file copy/move operation.
/// Stores source URLs and operation type until the user pastes them at a destination.
final class FileMover {
    static let shared = FileMover()

    private(set) var sourceURLs: [URL] = []
    private(set) var operation: FileMoveOperation?

    var hasPendingOperation: Bool {
        operation != nil && !sourceURLs.isEmpty
    }

    var pendingDescription: String {
        guard let op = operation, !sourceURLs.isEmpty else { return "" }
        if sourceURLs.count == 1 {
            if op == .copy {
                return LF("复制 \"%@\" 到这里", sourceURLs[0].lastPathComponent)
            }
            return LF("移动 \"%@\" 到这里", sourceURLs[0].lastPathComponent)
        }
        if op == .copy {
            return LF("复制 %d 个项目到这里", sourceURLs.count)
        }
        return LF("移动 %d 个项目到这里", sourceURLs.count)
    }

    func stage(urls: [URL], operation: FileMoveOperation) {
        self.sourceURLs = urls
        self.operation = operation
    }

    func clear() {
        sourceURLs = []
        operation = nil
    }

    /// Shows a confirmation alert, then executes the operation.
    func execute(to destinationDir: URL) {
        guard let op = operation, !sourceURLs.isEmpty else { return }

        let verb = op == .copy ? L("复制") : L("移动")
        let fileList = sourceURLs.map { "  · \($0.lastPathComponent)" }.joined(separator: "\n")
        let message = LF("%@以下 %d 个项目到：\n%@\n\n%@", verb, sourceURLs.count, destinationDir.path, fileList)

        let alert = NSAlert()
        alert.messageText = LF("%@确认", verb)
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: verb)
        alert.addButton(withTitle: L("取消"))

        // Show as a standalone modal
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            performOperation(op, to: destinationDir)
        }

        // Always clear after confirmation or cancel
        clear()
    }

    private func performOperation(_ op: FileMoveOperation, to destinationDir: URL) {
        let fm = FileManager.default
        var errors: [String] = []

        for sourceURL in sourceURLs {
            let destURL = uniqueDestinationURL(for: sourceURL, in: destinationDir)
            do {
                switch op {
                case .copy:
                    try fm.copyItem(at: sourceURL, to: destURL)
                case .move:
                    try fm.moveItem(at: sourceURL, to: destURL)
                }
            } catch {
                errors.append("\(sourceURL.lastPathComponent): \(error.localizedDescription)")
                NSLog("Menu3: %@ failed: %@",
                      op == .copy ? "Copy" : "Move",
                      error.localizedDescription)
            }
        }

        if !errors.isEmpty {
            let alert = NSAlert()
            alert.messageText = L("部分操作失败")
            alert.informativeText = errors.joined(separator: "\n")
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("确定"))
            alert.runModal()
        }

        // Reveal destination in Finder
        NSWorkspace.shared.activateFileViewerSelecting(
            sourceURLs.map { uniqueDestinationURL(for: $0, in: destinationDir) }
                .filter { fm.fileExists(atPath: $0.path) }
        )
    }

    private func uniqueDestinationURL(for sourceURL: URL, in directoryURL: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension

        var candidateName = sourceURL.lastPathComponent
        var counter = 2

        while FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(candidateName).path) {
            if ext.isEmpty {
                candidateName = "\(baseName) \(counter)"
            } else {
                candidateName = "\(baseName) \(counter).\(ext)"
            }
            counter += 1
        }
        return directoryURL.appendingPathComponent(candidateName)
    }
}
