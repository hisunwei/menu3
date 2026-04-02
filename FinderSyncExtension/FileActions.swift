import Cocoa

enum FileActions {

    static func createNewTextFile(in directoryURL: URL) {
        let baseName = "未命名"
        let ext = "txt"
        var fileName = "\(baseName).\(ext)"
        var counter = 2

        while FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(fileName).path) {
            fileName = "\(baseName) \(counter).\(ext)"
            counter += 1
        }

        let fileURL = directoryURL.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)

        let textEditURL = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: textEditURL,
            configuration: .init(),
            completionHandler: nil
        )
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
}
