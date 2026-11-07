import AppKit
import Darwin
import ServiceManagement
import SlapNoteCore

/// Collects the signals used to tell a login-item launch from a manual launch.
/// See DECISIONS.md, "Login-item launch detection".
enum LaunchDetector {
    /// `true`/`false` if the current Apple event is an open-application event (with or without the
    /// login-item flag), `nil` if no such event is being handled.
    static func appleEventLoginItemFlag() -> Bool? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication) else { return nil }
        let prop = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))
        return prop?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    static var loginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Seconds since the user's `loginwindow` process started (it restarts with every login session).
    static func secondsSinceSessionStart(now: Date = Date()) -> TimeInterval? {
        guard let login = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.loginwindow" }),
              let start = processStartDate(pid: login.processIdentifier) else { return nil }
        return now.timeIntervalSince(start)
    }

    static func processStartDate(pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        let tv = info.kp_proc.p_un.__p_starttime
        guard tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
    }

    static func classify(appleEventFlag: Bool?) -> LaunchKind {
        LaunchContext.classify(appleEventSaysLoginItem: appleEventFlag,
                               loginItemEnabled: loginItemEnabled,
                               secondsSinceSessionStart: secondsSinceSessionStart())
    }
}

/// Launch at login via `SMAppService.mainApp`.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    static var statusDescription: String {
        switch status {
        case .enabled: return "SlapNote starts when you log in."
        case .requiresApproval: return "Waiting for approval in System Settings › General › Login Items."
        case .notRegistered: return "Off"
        case .notFound: return "Not available for this copy of SlapNote."
        @unknown default: return ""
        }
    }

    /// Returns an error message, or nil on success.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
