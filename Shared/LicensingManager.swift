import AppKit
import Foundation

enum EntitlementState {
    case trial(daysRemaining: Int, endDate: Date)
    case lifetime
    case expired(endDate: Date)
}

@MainActor
final class LicensingManager: ObservableObject {
    static let shared = LicensingManager()

    @Published private(set) var entitlement: EntitlementState = .trial(daysRemaining: 0, endDate: Date())
    @Published private(set) var isCheckingLicense = false
    @Published private(set) var lastMessage = ""

    private let installDateKey = "menu3.installDate"
    private let licenseKeyStorageKey = "menu3.licenseKey"
    private let instanceIDStorageKey = "menu3.licenseInstanceID"
    private let licenseValidatedAtKey = "menu3.licenseValidatedAt"
    private let expiredPromptAtKey = "menu3.expiredPromptAt"

    private var trialDays: Int {
        let value = Bundle.main.object(forInfoDictionaryKey: "Menu3TrialDays") as? Int
        return max(1, value ?? 90)
    }

    private var lifetimePrice: Double {
        let value = Bundle.main.object(forInfoDictionaryKey: "Menu3LifetimePriceUSD") as? Double
        return value ?? 9.9
    }

    var formattedPrice: String {
        String(format: "$%.1f", lifetimePrice)
    }

    private var checkoutURL: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "Menu3LemonSqueezyCheckoutURL") as? String,
           let url = URL(string: raw),
           !raw.isEmpty {
            return url
        }
        return nil
    }

    var canUseFeatures: Bool {
        switch entitlement {
        case .trial, .lifetime:
            return true
        case .expired:
            return false
        }
    }

    private init() {
        refreshEntitlement()
    }

    func refreshEntitlement() {
        if storedLicenseKey != nil {
            entitlement = .lifetime
            return
        }

        let installDate = ensureInstallDate()
        let trialEnd = Calendar.current.date(byAdding: .day, value: trialDays, to: installDate) ?? installDate
        let now = Date()
        if now < trialEnd {
            let days = max(0, daysUntil(trialEnd))
            entitlement = .trial(daysRemaining: days, endDate: trialEnd)
        } else {
            entitlement = .expired(endDate: trialEnd)
        }
    }

    func openCheckout() {
        guard let checkoutURL else {
            lastMessage = L("未配置 LemonSqueezy 购买链接")
            return
        }
        NSWorkspace.shared.open(checkoutURL)
    }

    func refreshLicenseStatusIfNeeded(force: Bool) async {
        guard let key = storedLicenseKey else {
            refreshEntitlement()
            return
        }
        let instanceID = storedInstanceID
        if !force, let validatedAt = UserDefaults.standard.object(forKey: licenseValidatedAtKey) as? Date {
            let elapsed = Date().timeIntervalSince(validatedAt)
            if elapsed < 15 * 24 * 3600 {
                entitlement = .lifetime
                return
            }
        }
        _ = await validateLicense(key, instanceID: instanceID, isBackgroundRefresh: true)
    }

    func activateLicense(_ rawKey: String) async -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { lastMessage = L("请先输入授权码"); return false }

        isCheckingLicense = true
        defer { isCheckingLicense = false }

        do {
            let instance = Host.current().localizedName ?? "Menu3-Mac"
            let result = try await LemonSqueezyClient.shared.activateLicense(licenseKey: key, instanceName: instance)
            if result.activated {
                UserDefaults.standard.set(key, forKey: licenseKeyStorageKey)
                UserDefaults.standard.set(result.instanceID, forKey: instanceIDStorageKey)
                UserDefaults.standard.set(Date(), forKey: licenseValidatedAtKey)
                entitlement = .lifetime
                lastMessage = L("授权验证成功")
                return true
            }
            UserDefaults.standard.removeObject(forKey: licenseKeyStorageKey)
            UserDefaults.standard.removeObject(forKey: instanceIDStorageKey)
            refreshEntitlement()
            lastMessage = result.errorMessage ?? L("授权无效，请检查后重试。")
            return false
        } catch {
            lastMessage = L("网络错误，授权验证失败。")
            return false
        }
    }

    private func validateLicense(_ key: String, instanceID: String?, isBackgroundRefresh: Bool) async -> Bool {
        do {
            let result = try await LemonSqueezyClient.shared.validateLicense(licenseKey: key, instanceID: instanceID)
            if result.valid {
                UserDefaults.standard.set(Date(), forKey: licenseValidatedAtKey)
                entitlement = .lifetime
                return true
            }
            if !isBackgroundRefresh {
                lastMessage = result.errorMessage ?? L("授权无效，请检查后重试。")
            }
            UserDefaults.standard.removeObject(forKey: licenseKeyStorageKey)
            UserDefaults.standard.removeObject(forKey: instanceIDStorageKey)
            refreshEntitlement()
            return false
        } catch {
            if !isBackgroundRefresh {
                lastMessage = L("网络错误，授权验证失败。")
            }
            return false
        }
    }

    func promptExpiredIfNeeded() {
        guard case .expired = entitlement else { return }
        let defaults = UserDefaults.standard
        let now = Date()
        if let lastPromptAt = defaults.object(forKey: expiredPromptAtKey) as? Date,
           now.timeIntervalSince(lastPromptAt) < 600 {
            return
        }
        defaults.set(now, forKey: expiredPromptAtKey)
        presentActivateDialog()
    }

    func presentActivateDialog() {
        let alert = NSAlert()
        alert.messageText = L("Activate License")
        alert.informativeText = LF("输入授权码进行激活，或购买终身版（%@）。", formattedPrice)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("Activate License"))
        alert.addButton(withTitle: L("Buy Lifetime"))
        alert.addButton(withTitle: L("取消"))

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        inputField.placeholderString = L("输入 LemonSqueezy 授权码")
        alert.accessoryView = inputField

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task { _ = await activateLicense(inputField.stringValue) }
        } else if response == .alertSecondButtonReturn {
            openCheckout()
        }
    }

    private var storedLicenseKey: String? {
        guard let raw = UserDefaults.standard.string(forKey: licenseKeyStorageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }

    private var storedInstanceID: String? {
        guard let raw = UserDefaults.standard.string(forKey: instanceIDStorageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }

    private func ensureInstallDate() -> Date {
        let defaults = UserDefaults.standard
        if let date = defaults.object(forKey: installDateKey) as? Date {
            return date
        }
        let now = Date()
        defaults.set(now, forKey: installDateKey)
        return now
    }

    private func daysUntil(_ date: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }

    nonisolated static func isFeatureUnlockedNow() -> Bool {
        let defaults = UserDefaults.standard
        if let key = defaults.string(forKey: "menu3.licenseKey")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return true
        }
        let installDate = (defaults.object(forKey: "menu3.installDate") as? Date) ?? Date()
        let days = max(1, (Bundle.main.object(forInfoDictionaryKey: "Menu3TrialDays") as? Int) ?? 90)
        let trialEnd = Calendar.current.date(byAdding: .day, value: days, to: installDate) ?? installDate
        return Date() < trialEnd
    }
}
