import Cocoa
import Combine

/// Manages screen recording permission and triggers interactive screenshot capture.
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
            // On macOS 12/13: attempt to read a 1×1 pixel from on-screen content.
            // Returns nil (or a blank placeholder) when permission is denied.
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

    /// Launches an interactive screenshot session (user draws a selection rectangle).
    /// The result is saved to ~/Downloads with a timestamp-based name.
    func takeInteractiveScreenshot() {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let filename = "截图 \(formatter.string(from: Date())).png"
        let outputURL = downloadsURL.appendingPathComponent(filename)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-i", outputURL.path]
        try? proc.run()
    }
}
