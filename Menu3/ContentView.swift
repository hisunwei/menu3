import SwiftUI

struct ContentView: View {
    @ObservedObject private var settings = TriggerSettings.shared
    @ObservedObject private var screenshotMgr = ScreenshotManager.shared
    @State private var hasAccessibility = FinderMonitor.hasAccessibilityPermission

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu3")
                            .font(.title.bold())
                        Text("Finder 快捷菜单增强工具")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // ========== Section 1: Finder 增强菜单 ==========
                VStack(alignment: .leading, spacing: 14) {
                    Label("Finder 增强菜单", systemImage: "contextualmenu.and.cursorarrow")
                        .font(.headline)

                    // 功能介绍
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("功能介绍")
                                .font(.subheadline.bold())
                            Text("在 Finder 中通过鼠标中键或触摸板手势呼出快捷菜单，提供以下增强操作：")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 4) {
                                Label("新建文本文件", systemImage: "doc.badge.plus")
                                Label("复制文件名 / 文件路径", systemImage: "doc.on.clipboard")
                                Label("复制 / 移动文件到其他目录", systemImage: "arrow.right.doc.on.clipboard")
                                Label("保存文件/文本 来自粘贴板", systemImage: "square.and.arrow.down.on.square")
                                Label("从当前目录打开应用", systemImage: "app.badge.checkmark")
                                Label("显示 / 隐藏隐藏文件", systemImage: "eye")
                            }
                            .font(.caption)
                        }
                        .padding(4)
                    }

                    // 使用方法
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("使用方法")
                                .font(.subheadline.bold())
                            Text("在 Finder 窗口中使用以下任一触发方式即可弹出快捷菜单。可同时启用多种方式。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(4)
                    }

                    // 权限状态
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

                    // 触发方式
                    VStack(alignment: .leading, spacing: 12) {
                        Text("触发方式")
                            .font(.subheadline.bold())

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
                }

                Divider()

                // ========== Section 2: 截图功能 ==========
                VStack(alignment: .leading, spacing: 14) {
                    Label("截图功能", systemImage: "camera.viewfinder")
                        .font(.headline)

                    // 功能介绍
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("功能介绍")
                                .font(.subheadline.bold())
                            Text("按下 ⌘⇧A 可触发交互式截图。支持自动识别并高亮窗口、拖拽选取任意区域、画笔标注、文字添加和调色板。截图完成后可复制到剪贴板或保存为 PNG 文件。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(4)
                    }

                    // 使用方法
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("使用方法")
                                .font(.subheadline.bold())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("1. 开启下方开关")
                                Text("2. 按下 ⌘⇧A 进入截图模式")
                                Text("3. 悬停可自动高亮窗口，点击选中；或拖拽选取自定义区域")
                                Text("4. 选区后可使用画笔🖊、文字T 进行标注，支持调色板选色")
                                Text("5. 点击「复制」存入剪贴板，或「保存」选择存储位置")
                                Text("6. 按 ESC 取消，按 Enter 快速复制")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }

                    // 权限状态
                    GroupBox {
                        HStack {
                            if screenshotMgr.permissionStatus == .granted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("屏幕录制已授权")
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("需要屏幕录制权限")
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

                    // 开关
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
                }

                Spacer(minLength: 10)
            }
            .padding(30)
        }
        .frame(width: 420)
        .onAppear {
            hasAccessibility = FinderMonitor.hasAccessibilityPermission
            screenshotMgr.refreshPermissionStatus()
        }
    }
}
