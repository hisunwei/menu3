import Cocoa

enum FileActions {

    // MARK: - Hidden Files Toggle

    /// Checks whether Finder is currently showing hidden files.
    static var isShowingHiddenFiles: Bool {
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        let value = CFPreferencesCopyAppValue("AppleShowAllFiles" as CFString, "com.apple.finder" as CFString)
        if let num = value as? NSNumber { return num.boolValue }
        if let str = value as? String { return ["1", "true", "yes"].contains(str.lowercased()) }
        return false
    }

    /// Simulates Cmd+Shift+. (the native Finder shortcut) via CGEvent.
    /// Requires accessibility permission (which Menu3 already has).
    /// Finder handles the event in-place — no restart, no window re-open.
    static func toggleHiddenFiles() {
        guard let finderApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first else {
            NSLog("Menu3: Finder not running")
            return
        }

        // Bring Finder to front briefly so it receives the keystroke
        finderApp.activate(options: [])
        // Small delay to let Finder become key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let keyCode: CGKeyCode = 47  // period (.)
            let flags: CGEventFlags = [.maskCommand, .maskShift]

            let src = CGEventSource(stateID: .combinedSessionState)
            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
                  let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
            else {
                NSLog("Menu3: failed to create CGEvent for toggle hidden files")
                return
            }
            keyDown.flags = flags
            keyUp.flags = flags
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    static func createNewTextFile(in directoryURL: URL) {
        let fileURL = nextUntitledTextFileURL(in: directoryURL)
        let created = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        guard created else {
            NSLog("RightMenu: failed to create text file at %@", fileURL.path)
            return
        }

        let textEditURL = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: textEditURL,
            configuration: .init(),
            completionHandler: nil
        )
    }

    static func hasFileURLsInClipboard() -> Bool {
        let classes: [AnyClass] = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = NSPasteboard.general.readObjects(forClasses: classes, options: options) as? [URL]
        return !(urls?.isEmpty ?? true)
    }

    static func hasTextInClipboard() -> Bool {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            return false
        }
        return !value.isEmpty
    }

    static func saveFilesFromClipboard(to directoryURL: URL) {
        let classes: [AnyClass] = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let sourceURLs = NSPasteboard.general.readObjects(forClasses: classes, options: options) as? [URL],
              !sourceURLs.isEmpty else {
            NSLog("RightMenu: no file URLs found in pasteboard")
            return
        }

        var createdURLs: [URL] = []
        for sourceURL in sourceURLs {
            let destinationURL = uniqueDestinationURL(for: sourceURL, in: directoryURL)
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                createdURLs.append(destinationURL)
            } catch {
                NSLog(
                    "RightMenu: failed to copy %@ to %@, error: %@",
                    sourceURL.path,
                    destinationURL.path,
                    error.localizedDescription
                )
            }
        }

        guard let firstCreatedURL = createdURLs.first else {
            NSLog("RightMenu: no files copied from pasteboard")
            return
        }
        revealAndBeginRename(fileURL: firstCreatedURL)
    }

    static func saveTextFromClipboard(to directoryURL: URL) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            NSLog("RightMenu: no text found in pasteboard")
            return
        }

        let fileURL = nextUntitledTextFileURL(in: directoryURL)
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("RightMenu: failed writing text file at %@, error: %@", fileURL.path, error.localizedDescription)
            return
        }

        revealAndBeginRename(fileURL: fileURL)
    }

    static func copyFileNames(from urls: [URL]) {
        let names = urls.map { $0.lastPathComponent }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(names, forType: .string)
    }

    static func copyFilePaths(from urls: [URL]) {
        let paths = urls.map { $0.path }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    private static func nextUntitledTextFileURL(in directoryURL: URL) -> URL {
        var fileName = "未命名.txt"
        var counter = 2

        while FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(fileName).path) {
            fileName = "未命名 \(counter).txt"
            counter += 1
        }
        return directoryURL.appendingPathComponent(fileName)
    }

    private static func uniqueDestinationURL(for sourceURL: URL, in directoryURL: URL) -> URL {
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

    private static func revealAndBeginRename(fileURL: URL) {
        let escapedPath = fileURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Finder"
            activate
            reveal POSIX file "\(escapedPath)"
            set selectedItem to (POSIX file "\(escapedPath)") as alias
            set selection to {selectedItem}
            delay 0.15
            tell application "System Events"
                keystroke return
            end tell
        end tell
        """

        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
        if let error {
            NSLog("RightMenu: failed to trigger rename via AppleScript: %@", error)
        }
    }
}
