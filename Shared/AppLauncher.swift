import Cocoa
import UniformTypeIdentifiers

class AppLauncher {

    static let shared = AppLauncher()
    private let recentAppsManager = RecentAppsManager()

    private init() {}

    var recentApps: [URL] {
        recentAppsManager.recentApps
            .compactMap { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func launchApp(at appURL: URL, currentDirectory: URL) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [currentDirectory],
            withApplicationAt: appURL,
            configuration: config,
            completionHandler: nil
        )
        recentAppsManager.addApp(appURL.path)
    }

    func chooseAndLaunchApp(currentDirectory: URL) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = L("打开")
        panel.message = L("选择要在当前目录打开的应用")

        if panel.runModal() == .OK, let url = panel.url {
            launchApp(at: url, currentDirectory: currentDirectory)
        }
    }
}
