import SwiftUI

@main
struct Menu3App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty — we manage windows manually
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item with the app icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let img = NSImage(named: "StatusBarIcon") {
                img.size = NSSize(width: 18, height: 18)
                button.image = img
            } else if let appIcon = NSImage(named: "AppIcon") {
                appIcon.size = NSSize(width: 18, height: 18)
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
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "关于 Menu3", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())

        // Accessibility status
        let accText = FinderMonitor.hasAccessibilityPermission
            ? "✅ 辅助功能已授权"
            : "⚠️ 需要辅助功能权限"
        let accItem = NSMenuItem(title: accText, action: nil, keyEquivalent: "")
        accItem.isEnabled = false
        menu.addItem(accItem)

        if !FinderMonitor.hasAccessibilityPermission {
            menu.addItem(withTitle: "授权辅助功能…", action: #selector(requestAccessibility), keyEquivalent: "")
        }

        // Screenshot status
        let screenshotEnabled = TriggerSettings.shared.screenshotEnabled
        let ssText = screenshotEnabled ? "✅ 截图功能已开启" : "⚫ 截图功能未开启"
        let ssItem = NSMenuItem(title: ssText, action: nil, keyEquivalent: "")
        ssItem.isEnabled = false
        menu.addItem(ssItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Menu3", action: #selector(quit), keyEquivalent: "q")

        for item in menu.items where item.action != nil {
            item.target = self
        }
    }

    private func handleTrigger(at screenPoint: NSPoint) {
        DispatchQueue.main.async {
            MenuPresenter.shared.show(at: screenPoint)
        }
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
            window.title = "Menu3 设置"
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
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func requestAccessibility() {
        FinderMonitor.requestAccessibilityPermission()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
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

