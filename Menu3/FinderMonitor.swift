import Cocoa
import Combine

/// Monitors configurable mouse/trackpad gestures in Finder to trigger the custom menu.
final class FinderMonitor {
    static let shared = FinderMonitor()

    var onTrigger: ((_ mouseLocation: NSPoint) -> Void)?

    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private let settings = TriggerSettings.shared

    /// Debounce to avoid multiple triggers from the same gesture
    private var lastTriggerTime: TimeInterval = 0

    // Multitouch state
    private var mtDevices: [MTDeviceRef] = []
    private var peakTouchCount: Int32 = 0
    private var touchStartTime: TimeInterval = 0
    private var didReachThree = false

    func start() {
        setupMonitors()

        settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.setupMonitors() }
        }.store(in: &cancellables)

        NSLog("Menu3: Monitor started")
    }

    func stop() {
        removeAllMonitors()
        cancellables.removeAll()
    }

    private func setupMonitors() {
        removeAllMonitors()

        // Middle mouse button
        if settings.middleClick {
            let m = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
                guard event.buttonNumber == 2 else { return }
                self?.trigger()
            }
            if let m { monitors.append(m) }
        }

        // cmd+shift+a global screenshot shortcut (keyCode 0 = 'A')
        if settings.screenshotEnabled {
            let targetFlags: NSEvent.ModifierFlags = [.command, .shift]
            let globalHotkey = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 0,
                      event.modifierFlags.intersection([.command, .shift, .control, .option]) == targetFlags
                else { return }
                self?.handleScreenshotHotkey()
            }
            if let globalHotkey { monitors.append(globalHotkey) }

            let localHotkey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 0,
                      event.modifierFlags.intersection([.command, .shift, .control, .option]) == targetFlags
                else { return event }
                self?.handleScreenshotHotkey()
                return nil
            }
            if let localHotkey { monitors.append(localHotkey) }
        }

        // Three-finger gestures via MultitouchSupport private API
        let needsMultitouch = settings.threeFingerTap || settings.threeFingerPress
            || settings.optionThreeFingerTap || settings.optionThreeFingerPress
        if needsMultitouch {
            startMultitouchDevices()
        }
    }

    private func handleScreenshotHotkey() {
        DispatchQueue.main.async {
            ScreenshotManager.shared.takeInteractiveScreenshot()
        }
    }

    // MARK: - MultitouchSupport

    private func startMultitouchDevices() {
        let cfList = MTDeviceCreateList()
        let count = CFArrayGetCount(cfList)
        guard count > 0 else {
            NSLog("Menu3: No multitouch devices found")
            return
        }

        for i in 0..<count {
            guard let ptr = CFArrayGetValueAtIndex(cfList, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: ptr)
            MTRegisterContactFrameCallback(device, multitouchCallback)
            MTDeviceStart(device, 0)
            mtDevices.append(device)
        }
        NSLog("Menu3: Registered multitouch on %d devices", mtDevices.count)
    }

    private func stopMultitouchDevices() {
        for device in mtDevices {
            MTDeviceStop(device)
        }
        mtDevices.removeAll()
    }

    func handleMultitouch(touchCount: Int32, touches: UnsafeRawPointer, timestamp: Double) {
        let count = touchCount

        if count >= 3 && !didReachThree {
            // Three or more fingers just appeared
            didReachThree = true
            touchStartTime = timestamp
            peakTouchCount = count
        } else if count > peakTouchCount {
            peakTouchCount = count
        }

        // All fingers lifted
        if count == 0 && didReachThree {
            let duration = timestamp - touchStartTime
            let optionHeld = NSEvent.modifierFlags.contains(.option)

            // Three-finger tap (with or without Option)
            if peakTouchCount == 3 && duration > 0.02 && duration < 0.4 {
                if optionHeld && settings.optionThreeFingerTap {
                    DispatchQueue.main.async { [weak self] in self?.trigger() }
                } else if !optionHeld && settings.threeFingerTap {
                    DispatchQueue.main.async { [weak self] in self?.trigger() }
                }
            }

            // Reset state
            didReachThree = false
            peakTouchCount = 0
            touchStartTime = 0
        }

        // Three-finger press: sustained 3 fingers > 0.5s
        if didReachThree && count >= 3 && peakTouchCount == 3 {
            let duration = timestamp - touchStartTime
            if duration > 0.5 {
                let optionHeld = NSEvent.modifierFlags.contains(.option)
                let shouldTrigger = (optionHeld && settings.optionThreeFingerPress)
                    || (!optionHeld && settings.threeFingerPress)
                if shouldTrigger {
                    peakTouchCount = 99
                    DispatchQueue.main.async { [weak self] in self?.trigger() }
                }
            }
        }
    }

    private func removeAllMonitors() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        stopMultitouchDevices()
    }

    private func trigger() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTriggerTime > 0.5 else { return }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier == "com.apple.finder" else { return }

        lastTriggerTime = now
        let mouseLocation = NSEvent.mouseLocation
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?(mouseLocation)
        }
    }

    // MARK: - Accessibility Permission

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

// C-level callback — bridges to FinderMonitor.shared
private let multitouchCallback: MTContactCallbackFunction = { device, touches, touchCount, timestamp, frame in
    FinderMonitor.shared.handleMultitouch(touchCount: touchCount, touches: touches, timestamp: timestamp)
}
