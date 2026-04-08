import Cocoa
import Combine

/// Manages screen recording permission and triggers the custom screenshot overlay.
final class ScreenshotManager: ObservableObject {
    static let shared = ScreenshotManager()

    enum PermissionStatus {
        case granted, denied

        var displayText: String {
            switch self {
            case .granted: return "✅ 屏幕录制已授权"
            case .denied:  return "⚠️ 需要屏幕录制权限"
            }
        }
    }

    @Published var permissionStatus: PermissionStatus = .denied
    private var session: ScreenshotSession?

    private init() {
        refreshPermissionStatus()
    }

    func refreshPermissionStatus() {
        permissionStatus = Self.checkPermission() ? .granted : .denied
    }

    static func checkPermission() -> Bool {
        if #available(macOS 14.0, *) {
            return CGPreflightScreenCaptureAccess()
        } else {
            // On macOS 12/13: a successful capture (non-nil, non-zero-width) means permission is granted.
            guard let image = CGWindowListCreateImage(
                CGRect(x: 0, y: 0, width: 1, height: 1),
                .optionOnScreenOnly,
                kCGNullWindowID,
                .bestResolution
            ) else { return false }
            return image.width > 0
        }
    }

    static func requestPermission() {
        if #available(macOS 14.0, *) {
            CGRequestScreenCaptureAccess()
        }
        // Open System Preferences → Privacy → Screen Recording
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        )
    }

    /// Launches the custom WeChat-style screenshot overlay.
    func takeInteractiveScreenshot() {
        guard session == nil else { return } // Prevent double-launch
        refreshPermissionStatus()
        guard permissionStatus == .granted else {
            Self.requestPermission()
            return
        }
        let s = ScreenshotSession()
        session = s
        s.onFinished = { [weak self] in self?.session = nil }
        s.start()
    }
}

