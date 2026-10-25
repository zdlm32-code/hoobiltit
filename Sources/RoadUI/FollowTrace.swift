import Foundation
#if DEBUG && os(iOS)
import os
#endif

/// A running record of what the location stream and the follow camera did, for working out
/// after a drive why the map stopped following the car.
///
/// Debug builds on iOS only. The release build promises that nothing it keeps holds the user's
/// position — past drives are road names only — and this is a location trail, so everywhere
/// else every call compiles to nothing. The macOS test run is excluded too, so `swift test`
/// never writes into the developer's Caches.
///
/// Two sinks. The unified log, so the trace can be watched live in Console.app with the phone
/// plugged in; and a file in Caches, because the drive that matters usually happens with the
/// phone unplugged. Pull the file afterwards with
///
///     xcrun devicectl device copy from --device <udid> --domain-type appDataContainer \
///       --domain-identifier com.roadapp.whobuiltthis \
///       --source Library/Caches/follow-trace.log --destination follow-trace.log
@MainActor
enum FollowTrace {
    static func log(_ tag: String, _ message: @autoclosure () -> String) {
        #if DEBUG && os(iOS)
        let text = message()
        logger(for: tag).notice("\(text, privacy: .public)")
        guard let file else { return }
        let elapsed = Date().timeIntervalSince(launchedAt)
        let line = "\(stamp.string(from: Date())) +\(String(format: "%.3f", elapsed)) [\(tag)] \(text)\n"
        file.write(Data(line.utf8))
        #endif
    }

    /// A number for a trace line: fixed digits, or `-` when there is none.
    nonisolated static func num(_ value: Double?, _ digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "-" }
        return String(format: "%.\(digits)f", value)
    }

    #if DEBUG && os(iOS)
    private static let subsystem = "com.roadapp.whobuiltthis"
    private static let launchedAt = Date()
    /// Rotated at launch rather than mid-drive, so one drive is never split across two files.
    private static let rotateAboveBytes = 5_000_000
    private static var loggers: [String: Logger] = [:]

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func logger(for tag: String) -> Logger {
        if let existing = loggers[tag] { return existing }
        let made = Logger(subsystem: subsystem, category: tag)
        loggers[tag] = made
        return made
    }

    private static let file: FileHandle? = {
        let manager = FileManager.default
        guard let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let url = caches.appendingPathComponent("follow-trace.log")
        if let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? Int,
           size > rotateAboveBytes {
            let old = caches.appendingPathComponent("follow-trace.old.log")
            try? manager.removeItem(at: old)
            try? manager.moveItem(at: url, to: old)
        }
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        _ = try? handle.seekToEnd()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        handle.write(Data("\n=== launch \(version) (\(build)) ===\n".utf8))
        return handle
    }()
    #endif
}
