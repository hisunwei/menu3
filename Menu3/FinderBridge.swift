import Cocoa

/// Communicates with Finder via AppleScript to get the current directory
/// and selected items.
final class FinderBridge {
    static let shared = FinderBridge()

    /// Returns the POSIX path of the frontmost Finder window's target directory.
    func currentDirectoryURL() -> URL? {
        let script = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                return POSIX path of (target of front Finder window as text)
            end if
        end tell
        """
        guard let result = runAppleScript(script) else { return nil }
        let path = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Returns the URLs of items currently selected in the frontmost Finder window.
    func selectedItemURLs() -> [URL] {
        let script = """
        tell application "Finder"
            set sel to selection
            if (count of sel) = 0 then return ""
            set paths to {}
            repeat with f in sel
                set end of paths to POSIX path of (f as text)
            end repeat
            set AppleScript's text item delimiters to "\\n"
            return paths as text
        end tell
        """
        guard let result = runAppleScript(script) else { return [] }
        let lines = result.split(separator: "\n").map(String.init)
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return URL(fileURLWithPath: trimmed)
        }
    }

    /// Activates Finder and selects the given file URLs.
    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Navigates Finder to the given directory URL.
    @discardableResult
    func goToDirectory(_ directoryURL: URL) -> Bool {
        let escapedPath = escapeAppleScriptPath(directoryURL.path)
        let script = """
        tell application "Finder"
            activate
            set targetFolder to POSIX file "\(escapedPath)" as alias
            if (count of Finder windows) > 0 then
                set target of front Finder window to targetFolder
            else
                make new Finder window to targetFolder
            end if
        end tell
        """
        return runAppleScript(script) != nil
    }

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }

    private func escapeAppleScriptPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
