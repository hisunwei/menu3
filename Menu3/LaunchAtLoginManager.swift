import AppKit
import ServiceManagement

final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    enum State {
        case enabled
        case notEnabled
    }

    private init() {}

    var state: State {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return .enabled
            case .notRegistered, .requiresApproval, .notFound:
                return .notEnabled
            @unknown default:
                return .notEnabled
            }
        }
        return .notEnabled
    }

    func guideEnableIfNeeded() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp

            switch service.status {
            case .enabled:
                return
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notRegistered, .notFound:
                do {
                    try service.register()
                } catch {
                    NSLog("开机启动注册失败: \(error.localizedDescription)")
                    SMAppService.openSystemSettingsLoginItems()
                    return
                }

                if service.status != .enabled {
                    SMAppService.openSystemSettingsLoginItems()
                }
            @unknown default:
                SMAppService.openSystemSettingsLoginItems()
            }
            return
        }

        if let legacyLoginItemsURL = URL(string: "x-apple.systempreferences:com.apple.preference.users?LoginItems") {
            NSWorkspace.shared.open(legacyLoginItemsURL)
        }
    }
}
