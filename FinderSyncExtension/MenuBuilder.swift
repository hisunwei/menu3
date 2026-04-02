import Cocoa
import FinderSync

enum MenuBuilder {

    enum Tag: Int {
        case newTextFile = 1
        case copyFileName = 2
        case copyFilePath = 3
        case copyAllFileNames = 4
        case copyAllFilePaths = 5
        case saveFilesFromClipboard = 6
        case saveTextFromClipboard = 7
        case chooseApp = 100
        case recentAppBase = 200
    }

    static func buildMenu(for menuKind: FIMenuKind, target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu(title: "RightMenu")

        switch menuKind {
        case .contextualMenuForContainer:
            addItem(to: menu, title: "新建文本文件", tag: .newTextFile, target: target, action: action)
            addClipboardActions(to: menu, target: target, action: action)
            menu.addItem(.separator())
            menu.addItem(buildOpenAppSubmenu(target: target, action: action))

        case .contextualMenuForItems:
            let selectedCount = FIFinderSyncController.default().selectedItemURLs()?.count ?? 0
            if selectedCount > 1 {
                addItem(to: menu, title: "复制所有文件名", tag: .copyAllFileNames, target: target, action: action)
                addItem(to: menu, title: "复制所有文件路径", tag: .copyAllFilePaths, target: target, action: action)
            } else {
                addItem(to: menu, title: "复制文件名", tag: .copyFileName, target: target, action: action)
                addItem(to: menu, title: "复制文件路径", tag: .copyFilePath, target: target, action: action)
            }
            addClipboardActions(to: menu, target: target, action: action)
            menu.addItem(.separator())
            menu.addItem(buildOpenAppSubmenu(target: target, action: action))

        default:
            break
        }

        return menu
    }

    private static func addClipboardActions(to menu: NSMenu, target: AnyObject, action: Selector) {
        let hasClipboardFiles = FileActions.hasFileURLsInClipboard()
        let hasClipboardText = FileActions.hasTextInClipboard()

        if hasClipboardFiles {
            addItem(to: menu, title: "保存文件 来自粘贴板", tag: .saveFilesFromClipboard, target: target, action: action)
        }
        if hasClipboardText {
            addItem(to: menu, title: "保存成文本文件", tag: .saveTextFromClipboard, target: target, action: action)
        }
    }

    private static func addItem(to menu: NSMenu, title: String, tag: Tag, target: AnyObject, action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = target
        item.tag = tag.rawValue
    }

    private static func buildOpenAppSubmenu(target: AnyObject, action: Selector) -> NSMenuItem {
        let submenuItem = NSMenuItem(title: "在此打开应用", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "在此打开应用")

        let recentApps = AppLauncher.shared.recentApps
        for (index, appURL) in recentApps.enumerated() {
            let appName = appURL.deletingPathExtension().lastPathComponent
            let item = NSMenuItem(title: appName, action: action, keyEquivalent: "")
            item.target = target
            item.tag = Tag.recentAppBase.rawValue + index
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            submenu.addItem(item)
        }

        if !recentApps.isEmpty {
            submenu.addItem(.separator())
        }

        let chooseItem = NSMenuItem(title: "选择应用…", action: action, keyEquivalent: "")
        chooseItem.target = target
        chooseItem.tag = Tag.chooseApp.rawValue
        submenu.addItem(chooseItem)

        submenuItem.submenu = submenu
        return submenuItem
    }
}
