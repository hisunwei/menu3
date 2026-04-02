import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "contextualmenu.and.cursorarrow")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("RightMenu")
                .font(.largeTitle.bold())

            Text("macOS Finder 右键菜单增强工具")
                .font(.title3)
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Label("新建文本文件", systemImage: "doc.badge.plus")
                Label("复制文件名 / 文件路径", systemImage: "doc.on.clipboard")
                Label("从当前目录打开应用", systemImage: "app.badge.checkmark")
            }
            .font(.body)

            Divider()

            VStack(spacing: 12) {
                Text("请确保 Finder 扩展已启用")
                    .font(.headline)

                Text("系统设置 → 隐私与安全性 → 扩展 → 已添加的扩展")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("打开扩展设置") {
                    openExtensionSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(40)
        .frame(width: 420)
    }

    private func openExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }
}
