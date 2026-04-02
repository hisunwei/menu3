import Cocoa
import FinderSync
import FileProvider

class FinderSync: FIFinderSync {

    override init() {
        super.init()
        let userName = NSUserName()
        var urls: Set<URL> = [
            URL(fileURLWithPath: "/Users/\(userName)"),
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/tmp"),
        ]
        urls.insert(URL(fileURLWithPath: "/Users/\(userName)/Library/Mobile Documents"))
        if let volumes = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") {
            for vol in volumes {
                urls.insert(URL(fileURLWithPath: "/Volumes/\(vol)"))
            }
        }
        FIFinderSyncController.default().directoryURLs = urls

        // Discover File Provider domain URLs (e.g. iCloud Desktop/Documents)
        // and add them to directoryURLs asynchronously.
        NSFileProviderManager.getDomainsWithCompletionHandler { [weak self] domains, error in
            guard self != nil else { return }
            let logPath = NSTemporaryDirectory() + "RightMenu_fp.log"
            var log = "FP discovery: \(domains.count) domains, error: \(error?.localizedDescription ?? "none")\n"

            let group = DispatchGroup()
            var fpURLs: [URL] = []
            let lock = NSLock()

            for domain in domains {
                log += "  domain: \(domain.identifier.rawValue) display: \(domain.displayName)\n"
                guard let mgr = NSFileProviderManager(for: domain) else {
                    log += "    no manager\n"
                    continue
                }
                group.enter()
                mgr.getUserVisibleURL(for: .rootContainer) { url, err in
                    if let url = url {
                        lock.lock()
                        fpURLs.append(url)
                        log += "    URL: \(url.absoluteString)\n"
                        lock.unlock()
                    } else {
                        lock.lock()
                        log += "    error: \(err?.localizedDescription ?? "unknown")\n"
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                if !fpURLs.isEmpty {
                    var current = FIFinderSyncController.default().directoryURLs ?? Set<URL>()
                    for url in fpURLs {
                        current.insert(url)
                    }
                    FIFinderSyncController.default().directoryURLs = current
                    log += "Updated directoryURLs with \(fpURLs.count) FP URLs\n"
                } else {
                    log += "No FP URLs found\n"
                }
                let final_urls = FIFinderSyncController.default().directoryURLs?.map { $0.absoluteString }.sorted().joined(separator: "\n  ") ?? "nil"
                log += "Final directoryURLs:\n  \(final_urls)\n"
                try? log.write(toFile: logPath, atomically: true, encoding: .utf8)
            }
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        return MenuBuilder.buildMenu(for: menuKind, target: self, action: #selector(handleMenuAction(_:)))
    }

    @objc func handleMenuAction(_ menuItem: NSMenuItem) {
        let tag = menuItem.tag

        switch tag {
        case MenuBuilder.Tag.newTextFile.rawValue:
            guard let targetDirectoryURL = currentTargetDirectoryURL() else { return }
            FileActions.createNewTextFile(in: targetDirectoryURL)

        case MenuBuilder.Tag.saveFilesFromClipboard.rawValue:
            guard let targetDirectoryURL = currentTargetDirectoryURL() else { return }
            FileActions.saveFilesFromClipboard(to: targetDirectoryURL)

        case MenuBuilder.Tag.saveTextFromClipboard.rawValue:
            guard let targetDirectoryURL = currentTargetDirectoryURL() else { return }
            FileActions.saveTextFromClipboard(to: targetDirectoryURL)

        case MenuBuilder.Tag.copyFileName.rawValue,
             MenuBuilder.Tag.copyAllFileNames.rawValue:
            guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return }
            FileActions.copyFileNames(from: urls)

        case MenuBuilder.Tag.copyFilePath.rawValue,
             MenuBuilder.Tag.copyAllFilePaths.rawValue:
            guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return }
            FileActions.copyFilePaths(from: urls)

        case MenuBuilder.Tag.chooseApp.rawValue:
            guard let targetDirectoryURL = currentTargetDirectoryURL() else { return }
            AppLauncher.shared.chooseAndLaunchApp(currentDirectory: targetDirectoryURL)

        default:
            if tag >= MenuBuilder.Tag.recentAppBase.rawValue
                && tag < MenuBuilder.Tag.recentAppBase.rawValue + AppConstants.maxRecentApps {
                let index = tag - MenuBuilder.Tag.recentAppBase.rawValue
                let recentApps = AppLauncher.shared.recentApps
                guard index < recentApps.count else { return }
                guard let targetDirectoryURL = currentTargetDirectoryURL() else { return }
                AppLauncher.shared.launchApp(at: recentApps[index], currentDirectory: targetDirectoryURL)
            }
        }
    }

    private func currentTargetDirectoryURL() -> URL? {
        if let targetedURL = FIFinderSyncController.default().targetedURL() {
            return targetedURL
        }
        guard let firstSelectedURL = FIFinderSyncController.default().selectedItemURLs()?.first else {
            return nil
        }
        let values = try? firstSelectedURL.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            return firstSelectedURL
        }
        return firstSelectedURL.deletingLastPathComponent()
    }
}
