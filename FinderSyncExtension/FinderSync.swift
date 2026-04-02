import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
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
