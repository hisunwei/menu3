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

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: "Menu3") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "RM"
            }
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "关于 Menu3", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())

        let statusLabel = NSMenuItem(title: accessibilityStatusText(), action: nil, keyEquivalent: "")
        statusLabel.isEnabled = false
        menu.addItem(statusLabel)

        if !FinderMonitor.hasAccessibilityPermission {
            menu.addItem(withTitle: "授权辅助功能…", action: #selector(requestAccessibility), keyEquivalent: "")
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Menu3", action: #selector(quit), keyEquivalent: "q")

        // Set targets for menu items
        for item in menu.items where item.action != nil {
            item.target = self
        }

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

    private func handleTrigger(at screenPoint: NSPoint) {
        DispatchQueue.main.async {
            MenuPresenter.shared.show(at: screenPoint)
        }
    }

    private func accessibilityStatusText() -> String {
        FinderMonitor.hasAccessibilityPermission
            ? "✅ 辅助功能已授权"
            : "⚠️ 需要辅助功能权限"
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
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
        // Hide from Dock when settings window closes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if NSApp.windows.filter({ $0.isVisible && $0 != self.statusItem.button?.window }).isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

