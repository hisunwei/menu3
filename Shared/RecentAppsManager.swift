import Foundation

class RecentAppsManager {

    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }

    var recentApps: [String] {
        defaults.stringArray(forKey: AppConstants.recentAppsKey) ?? []
    }

    func addApp(_ path: String) {
        var apps = recentApps.filter { $0 != path }
        apps.insert(path, at: 0)
        if apps.count > AppConstants.maxRecentApps {
            apps = Array(apps.prefix(AppConstants.maxRecentApps))
        }
        defaults.set(apps, forKey: AppConstants.recentAppsKey)
        defaults.synchronize()
    }
}
