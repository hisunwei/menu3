import SwiftUI

@main
struct Menu3App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty — we manage windows manually
        Settings { EmptyView() }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let installDateKey = "menu3.installDate"
    private let licensing = LicensingManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        persistInstallDateIfNeeded()
        licensing.refreshEntitlement()

        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item with the app icon (template = transparent background)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let img = NSImage(named: "StatusBarIcon") {
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = false
                button.image = img
            } else if let appIcon = NSImage(named: "AppIcon") {
                appIcon.size = NSSize(width: 18, height: 18)
                appIcon.isTemplate = false
                button.image = appIcon
            } else {
                button.title = "M3"
            }
        }

        // Build the menu dynamically each time it opens for live status
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Request accessibility if needed
        if !FinderMonitor.hasAccessibilityPermission {
            FinderMonitor.requestAccessibilityPermission()
        }

        // Start monitoring
        FinderMonitor.shared.onTrigger = { [weak self] mouseLocation in
            self?.handleTrigger(at: mouseLocation)
        }
        FinderMonitor.shared.start()

        Task { @MainActor in
            await licensing.refreshLicenseStatusIfNeeded(force: false)
            licensing.promptExpiredIfNeeded()
        }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        licensing.refreshEntitlement()
        menu.removeAllItems()

        menu.addItem(withTitle: L("设置…"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: L("关于 Menu3"), action: #selector(showAbout), keyEquivalent: "")
        addLanguageMenuItem(to: menu)
        menu.addItem(.separator())

        // Accessibility status
        let hasAcc = FinderMonitor.hasAccessibilityPermission
        let accItem = NSMenuItem(title: hasAcc ? L("辅助功能已授权") : L("辅助功能未授权"), action: nil, keyEquivalent: "")
        accItem.isEnabled = false
        if hasAcc {
            accItem.image = menuStatusImage(systemName: "checkmark.circle.fill", color: .systemGreen)
        } else {
            accItem.image = menuStatusImage(systemName: "exclamationmark.circle.fill", color: .systemOrange)
        }
        menu.addItem(accItem)

        if !FinderMonitor.hasAccessibilityPermission {
            menu.addItem(withTitle: L("授权辅助功能…"), action: #selector(requestAccessibility), keyEquivalent: "")
        }

        // Screenshot status
        let screenshotEnabled = TriggerSettings.shared.screenshotEnabled
        let ssItem = NSMenuItem(title: screenshotEnabled ? L("截图功能已开启") : L("截图功能未开启"), action: nil, keyEquivalent: "")
        ssItem.isEnabled = false
        ssItem.image = menuStatusImage(
            systemName: screenshotEnabled ? "camera.fill" : "camera",
            color: screenshotEnabled ? .systemGreen : .secondaryLabelColor
        )
        menu.addItem(ssItem)

        let launchAtLoginEnabled = LaunchAtLoginManager.shared.state == .enabled
        let launchAtLoginItem = NSMenuItem(
            title: launchAtLoginEnabled ? L("开机启动已设置") : L("开机启动未设置"),
            action: launchAtLoginEnabled ? nil : #selector(configureLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.isEnabled = !launchAtLoginEnabled
        launchAtLoginItem.image = menuStatusImage(
            systemName: launchAtLoginEnabled ? "power.circle.fill" : "power.circle",
            color: launchAtLoginEnabled ? .systemGreen : .systemOrange
        )
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        switch licensing.entitlement {
        case .trial(let daysRemaining, _):
            let item = NSMenuItem(title: LF("Trial: %d days left", daysRemaining), action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = menuStatusImage(systemName: "hourglass", color: .systemBlue)
            menu.addItem(item)
            menu.addItem(withTitle: LF("Buy Lifetime (%@)…", licensing.formattedPrice), action: #selector(openPurchasePage), keyEquivalent: "")
            menu.addItem(withTitle: L("Activate License…"), action: #selector(openActivateLicenseDialog), keyEquivalent: "")
        case .lifetime:
            let item = NSMenuItem(title: L("Lifetime Activated"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = menuStatusImage(systemName: "checkmark.seal.fill", color: .systemGreen)
            menu.addItem(item)
        case .expired:
            let item = NSMenuItem(title: L("Trial expired"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = menuStatusImage(systemName: "clock.badge.exclamationmark", color: .systemOrange)
            menu.addItem(item)
            menu.addItem(withTitle: LF("Buy Lifetime (%@)…", licensing.formattedPrice), action: #selector(openPurchasePage), keyEquivalent: "")
            menu.addItem(withTitle: L("Activate License…"), action: #selector(openActivateLicenseDialog), keyEquivalent: "")
        }
        menu.addItem(withTitle: L("退出 Menu3"), action: #selector(quit), keyEquivalent: "q")

        for item in menu.items where item.action != nil {
            item.target = self
        }
    }

    private func handleTrigger(at screenPoint: NSPoint) {
        DispatchQueue.main.async {
            MenuPresenter.shared.show(at: screenPoint)
        }
    }

    /// Creates a 14pt SF Symbol image tinted with the given color for use as a menu item icon.
    private func menuStatusImage(systemName: String, color: NSColor) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        guard let sym = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return nil }
        let size = NSSize(width: 16, height: 16)
        let tinted = NSImage(size: size, flipped: false) { _ in
            color.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
            sym.draw(in: NSRect(origin: .zero, size: size),
                     from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        return tinted
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 720),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = L("Menu3 设置")
            window.contentView = NSHostingView(rootView: ContentView())
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .credits: NSAttributedString(string: L("当前为公测版本，感谢早期支持者。"))
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func requestAccessibility() {
        FinderMonitor.requestAccessibilityPermission()
    }

    @objc private func openPurchasePage() {
        licensing.openCheckout()
    }

    @objc private func openActivateLicenseDialog() {
        licensing.presentActivateDialog()
    }

    @objc private func configureLaunchAtLogin() {
        LaunchAtLoginManager.shared.guideEnableIfNeeded()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = AppLanguage(rawValue: raw) else { return }
        LanguageManager.shared.setLanguage(language)
        if let menu = statusItem.menu {
            rebuildMenu(menu)
        }
    }

    private func addLanguageMenuItem(to menu: NSMenu) {
        let current = LanguageManager.shared.currentLanguage
        let title = LF("语言：%@", current.displayName)
        let langItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: L("语言"))
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.displayName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = language == current ? .on : .off
            submenu.addItem(item)
        }
        langItem.submenu = submenu
        menu.addItem(langItem)
    }

    private func persistInstallDateIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: installDateKey) == nil else { return }
        defaults.set(Date(), forKey: installDateKey)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if NSApp.windows.filter({ $0.isVisible && $0 != self.statusItem.button?.window }).isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}
