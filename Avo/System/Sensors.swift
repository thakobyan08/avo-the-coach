import AppKit
import CoreAudio
import CoreMediaIO

/// The signals behind Away and Quiet. None of these reads content or needs a permission prompt.
/// Screen sharing has no public API to detect it, so it is not checked; calls are caught by camera and mic.
enum Sensors {
    static func quietReason(workHours: WorkHours, now: Date) -> QuietReason? {
        if !workHours.contains(now) { return .outsideWorkHours }
        if isCameraInUse() { return .camera }
        if isMicrophoneInUse() { return .microphone }
        if isFullScreenAppInFront() { return .fullScreen }
        return nil
    }

    /// Seconds since the last keyboard, mouse or trackpad input.
    static func idleSeconds() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// Any camera running in any app.
    static func isCameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }

        var running = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        return devices.contains { device in
            var isRunning: UInt32 = 0
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &isRunning
            )
            return status == noErr && isRunning != 0
        }
    }

    /// Any other process recording from a microphone. Per process, so audio playing through a
    /// headset does not count.
    static func isMicrophoneInUse() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return false }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return processes.contains { process in
            readUInt32(process, kAudioProcessPropertyIsRunningInput) != 0
                && pid(of: process) != ownPID
        }
    }

    /// The front app has a window covering a whole display.
    static func isFullScreenAppInFront() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              !notFullScreenApps.contains(front.bundleIdentifier ?? ""),
              let windows = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]]
        else { return false }

        let displays = activeDisplayBounds()
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int ?? -1) >= 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return false }
            return displays.contains { display in
                abs(display.minX - bounds.minX) < 1 && abs(display.minY - bounds.minY) < 1
                    && abs(display.width - bounds.width) < 1 && abs(display.height - bounds.height) < 1
            }
        }
    }

    // MARK: Helpers

    /// Cover the screen while nobody is working: idle time should turn into Away, not Quiet.
    private static let notFullScreenApps: Set<String> = ["com.apple.ScreenSaver.Engine", "com.apple.loginwindow"]

    private static func activeDisplayBounds() -> [CGRect] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    private static func readUInt32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private static func pid(of process: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid)
        return pid
    }
}
