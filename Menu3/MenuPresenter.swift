import Cocoa

/// Builds and displays the Menu3 popup menu at the given screen location.
final class MenuPresenter {
    static let shared = MenuPresenter()

    func show(at screenPoint: NSPoint) {
        let bridge = FinderBridge.shared
        let selectedURLs = bridge.selectedItemURLs()
        let directoryURL = bridge.currentDirectoryURL()

        guard directoryURL != nil || !selectedURLs.isEmpty else {
            NSLog("Menu3: no directory or selection found")
            return
        }

        let targetDirectory: URL? = directoryURL ?? selectedURLs.first?.deletingLastPathComponent()
        let mover = FileMover.shared

        let menu = NSMenu(title: "Menu3")

        // Copy name/path actions
        if !selectedURLs.isEmpty {
            let label = selectedURLs.count > 1 ? L("复制所有文件名") : L("复制文件名")
            let labelPath = selectedURLs.count > 1 ? L("复制所有文件路径") : L("复制文件路径")
            addItem(to: menu, title: label, action: { FileActions.copyFileNames(from: selectedURLs) })
            addItem(to: menu, title: labelPath, action: { FileActions.copyFilePaths(from: selectedURLs) })
            menu.addItem(.separator())

            // Copy/Move staging
            let copyTitle: String
            let moveTitle: String
            if selectedURLs.count > 1 {
                copyTitle = LF("复制 %d 个项目", selectedURLs.count)
                moveTitle = LF("移动 %d 个项目", selectedURLs.count)
            } else {
                copyTitle = LF("复制 \"%@\"", selectedURLs[0].lastPathComponent)
                moveTitle = LF("移动 \"%@\"", selectedURLs[0].lastPathComponent)
            }
            addItem(to: menu, title: copyTitle, image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil), action: {
                mover.stage(urls: selectedURLs, operation: .copy)
            })
            addItem(to: menu, title: moveTitle, image: NSImage(systemSymbolName: "arrow.right.doc.on.clipboard", accessibilityDescription: nil), action: {
                mover.stage(urls: selectedURLs, operation: .move)
            })
            menu.addItem(.separator())
        } else if let dir = targetDirectory {
            addItem(to: menu, title: L("复制目录名"), action: { FileActions.copyFileNames(from: [dir]) })
            addItem(to: menu, title: L("复制目录路径"), action: { FileActions.copyFilePaths(from: [dir]) })
            menu.addItem(.separator())
        }

        // Paste staged copy/move
        if mover.hasPendingOperation, let dir = targetDirectory {
            addItem(to: menu, title: mover.pendingDescription, image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil), action: {
                mover.execute(to: dir)
            })
            addItem(to: menu, title: mover.operation == .copy ? L("取消复制") : L("取消移动"), action: {
                mover.clear()
            })
            menu.addItem(.separator())
        }

        // Toggle hidden files
        let isShowingHidden = FileActions.isShowingHiddenFiles
        let hiddenTitle = isShowingHidden ? L("隐藏隐藏文件") : L("显示隐藏文件")
        let hiddenImage = NSImage(systemSymbolName: isShowingHidden ? "eye.slash" : "eye", accessibilityDescription: nil)
        addItem(to: menu, title: hiddenTitle, image: hiddenImage, action: {
            FileActions.toggleHiddenFiles()
        })
        menu.addItem(.separator())

        // Directory-based actions
        if let dir = targetDirectory {
            addItem(to: menu, title: L("新建文件夹"), action: { FileActions.createNewFolder(in: dir) })
            addItem(to: menu, title: L("新建文本文件"), action: { FileActions.createNewTextFile(in: dir) })

            if FileActions.hasFileURLsInClipboard() {
                addItem(to: menu, title: L("保存文件 来自粘贴板"), action: { FileActions.saveFilesFromClipboard(to: dir) })
            }
            if FileActions.hasTextInClipboard() {
                addItem(to: menu, title: L("保存成文本文件"), action: { FileActions.saveTextFromClipboard(to: dir) })
            }

            menu.addItem(.separator())

            // Open in App submenu
            let submenuItem = NSMenuItem(title: L("在此打开应用"), action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: L("在此打开应用"))

            let recentApps = AppLauncher.shared.recentApps
            for appURL in recentApps {
                let appName = appURL.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = NSSize(width: 16, height: 16)
                addItem(to: submenu, title: appName, image: icon, action: {
                    AppLauncher.shared.launchApp(at: appURL, currentDirectory: dir)
                })
            }
            if !recentApps.isEmpty {
                submenu.addItem(.separator())
            }
            addItem(to: submenu, title: L("选择应用…"), action: {
                AppLauncher.shared.chooseAndLaunchApp(currentDirectory: dir)
            })
            submenuItem.submenu = submenu
            menu.addItem(submenuItem)

            // Go to folder submenu (shows the same right-side ">" indicator)
            let goToFolderItem = NSMenuItem(title: L("前往文件夹"), action: nil, keyEquivalent: "")
            let goToFolderSubmenu = NSMenu(title: L("前往文件夹"))
            addItem(to: goToFolderSubmenu, title: L("输入路径…"), action: { FileActions.promptAndGoToFolder() })
            goToFolderItem.submenu = goToFolderSubmenu
            menu.addItem(goToFolderItem)
        }

        menu.popUp(positioning: nil, at: screenPoint, in: nil)
    }

    // MARK: - Helpers

    private func addItem(to menu: NSMenu, title: String, image: NSImage? = nil, action: @escaping () -> Void) {
        let handler = ActionHandler(action: action)
        let item = menu.addItem(withTitle: title, action: #selector(ActionHandler.invoke), keyEquivalent: "")
        item.target = handler
        item.image = image
        item.representedObject = handler // prevent deallocation
    }
}

/// Helper to bridge closure-based actions to Objective-C selectors.
private class ActionHandler: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}
