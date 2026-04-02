# Menu3 架构文档

## 概述

Menu3 是一个 macOS Finder 增强工具，使用 **Accessibility API** 替代已弃用的 Finder Sync Extension 方案。应用作为菜单栏常驻程序运行，通过全局事件监听检测用户触发手势，动态生成和显示上下文菜单。

## 为什么选择 Accessibility API？

### Finder Sync Extension 的局限
- 被 Apple 标记为 **deprecated**
- **无法访问 iCloud 云同步目录**（File Provider 管理的目录）
- 系统会自动跳过这些目录中的 Finder Sync Extension
- 无法扩展到用户所有使用场景

### Accessibility API 的优势
- ✅ 对所有目录有效（本地、iCloud、移动存储）
- ✅ 完全由用户控制触发方式
- ✅ 不受系统限制
- ✅ 更灵活的手势支持

## 核心组件

- **RightMenuApp.swift** — 应用入口 + NSStatusBar 菜单栏
- **FinderMonitor.swift** — 全局事件监听（NSEvent、MultiTouch、修饰键）
- **MenuPresenter.swift** — NSMenu 构建和显示
- **FileMover.swift** — 文件复制/移动操作缓存
- **FinderBridge.swift** — AppleScript Finder 通信
- **TriggerSettings.swift** — 触发配置（UserDefaults）
- **MultitouchPrivate.swift** — MultitouchSupport.framework 私有 API 绑定
- **Shared/FileActions.swift** — 文件操作实现
- **Shared/AppLauncher.swift** — 应用启动管理

## 关键技术解决方案

### 1. 中键点击触发
```swift
NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown)
// buttonNumber == 2 表示中键
```

### 2. 触摸板三指手势（私有 API）
使用 MultitouchSupport.framework 直接获取触摸数据：
- 状态机：`didReachThree` + `peakTouchCount` + `touchStartTime`
- 轻点 = 达到3根 && 抬起 && 0.02s-0.4s
- 按下 = 达到3根 && 保持3根 && > 0.5s

### 3. Option 修饰键检测
```swift
NSEvent.modifierFlags.contains(.option)
```

### 4. iCloud 目录支持
- Finder Sync Extension 在 iCloud 目录中不工作（系统限制）
- Accessibility API 无此限制，可在所有目录工作

## 权限要求

- **Accessibility** — 全局事件监听（用户手动授予）
- **AppleScript** — 与 Finder 通信（Info.plist）

## 已知问题与解决方案

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| CGEvent.tapCreate 返回 nil | macOS 26+ 需要 Input Monitoring 权限 | 改用 MultitouchSupport API |
| NSEvent.allTouches() 为空 | 全局监听事件不完整 | 直接使用 MultiTouch 私有 API |
| 三指检测不稳定 | 简单计数状态机 | 使用 peak tracking 状态机 |

## 构建与部署

```bash
# 生成 Xcode 项目
xcodegen generate

# 编译 Release
xcodebuild -project menu3.xcodeproj -scheme menu3 -configuration Release \
  CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=M9HUJXV356 build

# 创建 DMG
hdiutil create -volname "Menu3" -srcfolder build/dmg -ov -format UDZO build/Menu3-1.0.0.dmg
```

## 更多信息

详见：
- `README.md` — 用户指南
- 代码注释 — 实现细节
