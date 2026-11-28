import Darwin
import Foundation
import UIKit

/// Lightweight cold-launch profiler for Debug and TestFlight diagnostics.
/// Records monotonic timestamps and numeric counts/sizes only (never user content).
@MainActor
final class StartupProfiler {
    static let shared = StartupProfiler()

    struct SpanRecord {
        let name: String
        let durationMs: Double
        let detail: String?
    }

    struct MilestoneRecord {
        let name: String
        let elapsedFromProcessStartMs: Double
    }

    /// Visible in Debug and TestFlight builds only; hidden in App Store production builds.
    static var isDiagnosticsAvailable: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    private let processStartAbsoluteTime: CFAbsoluteTime
    private let processStartResolved: Bool
    private var milestones: [MilestoneRecord] = []
    private var spans: [SpanRecord] = []
    private var metadata: [(String, String)] = []
    private var hasRecordedPrimaryStoreLoad = false
    private var hasRecordedInteractive = false
    private(set) var timeToInteractiveMs: Double?

    private init() {
        let nowAbs = CFAbsoluteTimeGetCurrent()
        if let procUnix = Self.processStartUnixTime() {
            let nowUnix = Date().timeIntervalSince1970
            let elapsedSinceProc = max(0, nowUnix - procUnix)
            self.processStartAbsoluteTime = nowAbs - elapsedSinceProc
            self.processStartResolved = true
        } else {
            self.processStartAbsoluteTime = nowAbs
            self.processStartResolved = false
        }
    }

    private static func processStartUnixTime() -> TimeInterval? {
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, UInt32(mib.count), &kinfo, &size, nil, 0)
        guard result == 0 else { return nil }
        let tv = kinfo.kp_proc.p_starttime
        return TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000.0
    }

    var shouldRecordPrimaryStoreLoad: Bool {
        !PersistenceController.isRunningTests && !hasRecordedPrimaryStoreLoad
    }

    func finishPrimaryStoreLoad() {
        hasRecordedPrimaryStoreLoad = true
    }

    func mark(_ name: String) {
        guard !PersistenceController.isRunningTests else { return }
        // Avoid duplicating repeated lifecycle events after the first cold launch.
        if milestones.contains(where: { $0.name == name }) { return }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - processStartAbsoluteTime) * 1000.0
        milestones.append(MilestoneRecord(name: name, elapsedFromProcessStartMs: elapsedMs))
        if (name == "startupLogo.complete" || name == "firstInteractiveFrame") && !hasRecordedInteractive {
            hasRecordedInteractive = true
            timeToInteractiveMs = elapsedMs
        }
    }

    @discardableResult
    func measure<T>(_ name: String, detail: (() -> String?)? = nil, _ body: () throws -> T) rethrows -> T {
        guard !PersistenceController.isRunningTests else { return try body() }
        let start = CFAbsoluteTimeGetCurrent()
        let result = try body()
        let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        spans.append(SpanRecord(name: name, durationMs: durationMs, detail: detail?()))
        return result
    }

    func recordSpan(_ name: String, durationMs: Double, detail: String? = nil) {
        guard !PersistenceController.isRunningTests else { return }
        spans.append(SpanRecord(name: name, durationMs: durationMs, detail: detail))
    }

    func setMetadata(_ key: String, value: String) {
        guard !PersistenceController.isRunningTests else { return }
        if let idx = metadata.firstIndex(where: { $0.0 == key }) {
            metadata[idx] = (key, value)
        } else {
            metadata.append((key, value))
        }
    }

    func recordDatabaseSizes() {
        guard !PersistenceController.isRunningTests else { return }
        let fm = FileManager.default
        let storeURL: URL?
        if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: PersistenceController.appGroupIdentifier) {
            storeURL = groupURL.appendingPathComponent("default.store")
        } else {
            storeURL = URL.applicationSupportDirectory.appendingPathComponent("default.store")
        }
        guard let base = storeURL else { return }
        let sizes: [(String, Int64)] = ["", "-wal", "-shm"].map { suffix in
            let path = base.path + suffix
            let bytes = (try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            return (suffix.isEmpty ? "main" : String(suffix.dropFirst()), bytes)
        }
        let total = sizes.reduce(Int64(0)) { $0 + $1.1 }
        let mb = { (b: Int64) in String(format: "%.2fMB", Double(b) / 1024.0 / 1024.0) }
        let breakdown = sizes.map { "\($0.0)=\(mb($0.1))" }.joined(separator: ", ")
        setMetadata("DBサイズ", value: "\(mb(total)) (\(breakdown))")
    }

    // MARK: - Summary Helpers

    var totalInteractiveSummary: String {
        if let ms = timeToInteractiveMs {
            return String(format: "%.0f ms", ms)
        }
        if let last = milestones.last {
            return String(format: "%.0f ms", last.elapsedFromProcessStartMs)
        }
        return "-"
    }

    var preMainMs: Double? {
        milestones.first(where: { $0.name == "appDelegate.didFinishLaunching.start" })?.elapsedFromProcessStartMs
    }

    var firebaseConfigureMs: Double? {
        spans.first(where: { $0.name == "firebase.configure" })?.durationMs
    }

    var storeInitTotalMs: Double? {
        let open = spans.first(where: { $0.name == "store.openContainer" })?.durationMs ?? 0
        let initMs = spans.first(where: { $0.name == "store.appDataStoreInit" })?.durationMs ?? 0
        return (open + initMs) > 0 ? (open + initMs) : nil
    }

    var uiFirstFrameMs: Double? {
        guard let storeEnd = milestones.first(where: { $0.name == "storeOwner.openIfNeeded.end" })?.elapsedFromProcessStartMs,
              let interactive = milestones.first(where: { $0.name == "firstInteractiveFrame" })?.elapsedFromProcessStartMs else {
            return nil
        }
        return max(0, interactive - storeEnd)
    }

    var fromStoreOpenToInteractiveMs: Double? {
        guard let storeStart = milestones.first(where: { $0.name == "storeOwner.openIfNeeded.start" })?.elapsedFromProcessStartMs,
              let interactive = milestones.first(where: { $0.name == "firstInteractiveFrame" })?.elapsedFromProcessStartMs else {
            return nil
        }
        return max(0, interactive - storeStart)
    }

    var isPrewarmedLaunch: Bool {
        ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
    }

    func formattedReport() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let channel: String = {
            #if DEBUG
            return "Debug"
            #else
            return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "TestFlight" : "AppStore"
            #endif
        }()
        let hardware = Self.hardwareIdentifier()
        let iosVersion = UIDevice.current.systemVersion
        let appLockEnabled = UserDefaults.standard.bool(forKey: "isAppLockEnabled")
        let photoCloudSync = UserDefaults.standard.bool(forKey: "diaryPhotoCloudSyncEnabled")
        let reduceMotion = UIAccessibility.isReduceMotionEnabled

        var lines: [String] = []
        lines.append("=== lifelify Startup Report ===")
        lines.append("Version: \(version) (\(build)) [\(channel)]")
        lines.append("Device: \(hardware) / iOS \(iosVersion)")
        lines.append("Flags: appLock=\(appLockEnabled), photoCloudSync=\(photoCloudSync), reduceMotion=\(reduceMotion), prewarm=\(isPrewarmedLaunch)")
        lines.append("ProcessStartResolved: \(processStartResolved)")
        lines.append("")

        lines.append("[Summary]")
        lines.append("  Time to Interactive: \(totalInteractiveSummary)")
        if let v = preMainMs { lines.append(String(format: "  Pre-main (OS + dyld): %7.1f ms", v)) }
        if let v = firebaseConfigureMs { lines.append(String(format: "  Firebase.configure:   %7.1f ms", v)) }
        if let v = storeInitTotalMs { lines.append(String(format: "  Store open + init:    %7.1f ms", v)) }
        if let v = uiFirstFrameMs { lines.append(String(format: "  UI first frame:       %7.1f ms", v)) }
        if isPrewarmedLaunch, let v = fromStoreOpenToInteractiveMs {
            lines.append(String(format: "  Tap -> Interactive:   %7.1f ms (prewarmed)", v))
        }
        lines.append("")

        lines.append("[Timeline (from process start)]")
        var previous: Double = 0
        for m in milestones {
            let delta = m.elapsedFromProcessStartMs - previous
            lines.append(String(format: "  %+7.1f ms (Δ %6.1f ms)  %@", m.elapsedFromProcessStartMs, delta, m.name))
            previous = m.elapsedFromProcessStartMs
        }
        lines.append("")

        lines.append("[Spans]")
        for s in spans {
            if let detail = s.detail, !detail.isEmpty {
                lines.append(String(format: "  %7.1f ms  %@  (%@)", s.durationMs, s.name, detail))
            } else {
                lines.append(String(format: "  %7.1f ms  %@", s.durationMs, s.name))
            }
        }
        lines.append("")

        if !metadata.isEmpty {
            lines.append("[Store Metadata]")
            for (k, v) in metadata {
                lines.append("  \(k): \(v)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func hardwareIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
