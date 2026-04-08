import SwiftUI

struct ContentView: View {
    @ObservedObject private var settings = TriggerSettings.shared
    @ObservedObject private var screenshotMgr = ScreenshotManager.shared
    @State private var hasAccessibility = FinderMonitor.hasAccessibilityPermission

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "contextualmenu.and.cursorarrow")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
                Text("Menu3")
                    .font(.title.bold())
            }

            Text("Finder 右键菜单增强工具")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            // Accessibility status
            GroupBox {
                HStack {
                    if hasAccessibility {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("辅助功能已授权")
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("需要辅助功能权限")
                        Spacer()
                        Button("授权") {
                            FinderMonitor.requestAccessibilityPermission()
                        }
                    }
                    Spacer()
                }
                .padding(4)
            }

            Divider()

            // Trigger settings
            VStack(alignment: .leading, spacing: 16) {
                Text("触发方式")
                    .font(.headline)

                Text("可同时启用多个触发方式")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(isOn: $settings.middleClick) {
                    VStack(alignment: .leading) {
                        Text("🖱️ 鼠标中键")
                        Text("按下鼠标中键（滚轮键）触发")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $settings.threeFingerTap) {
                    VStack(alignment: .leading) {
                        Text("👆 三指轻点")
                        Text("三根手指同时轻点触摸板")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $settings.threeFingerPress) {
                    VStack(alignment: .leading) {
                        Text("👇 三指用力按")
                        Text("三根手指用力按下触摸板")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $settings.optionThreeFingerTap) {
                    VStack(alignment: .leading) {
                        Text("⌥👆 Option + 三指轻点")
                        Text("按住 Option 键后三指轻点触摸板")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $settings.optionThreeFingerPress) {
                    VStack(alignment: .leading) {
                        Text("⌥👇 Option + 三指用力按")
                        Text("按住 Option 键后三指用力按下触摸板")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Screenshot feature
            VStack(alignment: .leading, spacing: 16) {
                Text("截图功能")
                    .font(.headline)

                Text("按下 ⌘⇧A 可触发交互式截图，自由选取屏幕区域后保存至「下载」文件夹。默认关闭，开启后需要屏幕录制权限。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: $settings.screenshotEnabled) {
                    VStack(alignment: .leading) {
                        Text("📷 启用 ⌘⇧A 截图快捷键")
                        Text("开启后全局监听 Command+Shift+A")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: settings.screenshotEnabled) { enabled in
                    if enabled {
                        screenshotMgr.refreshPermissionStatus()
                        if screenshotMgr.permissionStatus == .denied {
                            ScreenshotManager.requestPermission()
                        }
                    }
                }

                // Permission status
                GroupBox {
                    HStack {
                        if screenshotMgr.permissionStatus == .granted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(screenshotMgr.permissionStatus.displayText)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(screenshotMgr.permissionStatus.displayText)
                            Spacer()
                            Button("授权") {
                                ScreenshotManager.requestPermission()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    screenshotMgr.refreshPermissionStatus()
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }

            Divider()

            // Feature list
            VStack(alignment: .leading, spacing: 8) {
                Text("功能列表")
                    .font(.headline)
                Label("新建文本文件", systemImage: "doc.badge.plus")
                Label("复制文件名 / 文件路径", systemImage: "doc.on.clipboard")
                Label("复制 / 移动文件到其他目录", systemImage: "arrow.right.doc.on.clipboard")
                Label("保存文件/文本 来自粘贴板", systemImage: "square.and.arrow.down.on.square")
                Label("从当前目录打开应用", systemImage: "app.badge.checkmark")
                Label("显示 / 隐藏隐藏文件", systemImage: "eye")
                Label("⌘⇧A 交互式截图（可选）", systemImage: "camera.viewfinder")
            }
            .font(.callout)
        }
        .padding(30)
        .frame(width: 400)
        .onAppear {
            hasAccessibility = FinderMonitor.hasAccessibilityPermission
            screenshotMgr.refreshPermissionStatus()
        }
    }
}
