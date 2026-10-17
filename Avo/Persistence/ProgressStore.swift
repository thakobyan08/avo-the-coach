import Foundation
import Observation
import os

/// On-disk shape of `progress.json`. Bump `version` when the format changes.
nonisolated struct ProgressFile: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = ProgressFile.currentVersion
    /// Completed moves per local day, keyed "yyyy-MM-dd", in the order they were done.
    var days: [String: [ExerciseID]] = [:]
    /// Exercise rotation, so it survives relaunch.
    var picker = ExercisePicker()

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        days = try container.decodeIfPresent([String: [ExerciseID]].self, forKey: .days) ?? [:]
        picker = try container.decodeIfPresent(ExercisePicker.self, forKey: .picker) ?? ExercisePicker()
    }
}

/// Avo's history: moves done per day, the streak, and the exercise rotation.
/// Saved as JSON in `~/Library/Application Support/Avo/progress.json`, written on each change.
@Observable
final class ProgressStore {
    static let fileName = "progress.json"
    /// Days older than this are dropped on save.
    static let keepDays = 400
    /// The streak walk-back never looks further than this.
    static let maxStreakDays = 1000

    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let logger = Logger(subsystem: "com.thakobyan08.avo", category: "progress")

    private var data: ProgressFile

    /// - Parameters:
    ///   - directory: Folder that holds `progress.json`. Defaults to Application Support/Avo.
    ///   - calendar: Decides where days start and end. Defaults to the user's calendar and time zone.
    init(directory: URL? = nil, calendar: Calendar = .autoupdatingCurrent) {
        let folder = directory ?? Self.defaultDirectory
        fileURL = folder.appending(path: Self.fileName)
        self.calendar = calendar
        data = ProgressFile()
        data = load()
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Avo", directoryHint: .isDirectory)
    }

    // MARK: Moves

    func recordCompleted(_ id: ExerciseID, at date: Date = .now) {
        data.days[dayKey(for: date), default: []].append(id)
        save(now: date)
    }

    func count(on date: Date) -> Int {
        data.days[dayKey(for: date)]?.count ?? 0
    }

    var todayCount: Int { count(on: .now) }

    func goalReached(goal: Int, on date: Date = .now) -> Bool {
        count(on: date) >= max(goal, 1)
    }

    // MARK: Streak

    /// Consecutive work days with the goal reached (docs/SPEC.md). Days outside `workDays`
    /// (Calendar weekdays, 1 = Sunday) are skipped. Today counts once the goal is reached;
    /// an unfinished today does not break the streak.
    func streak(goal: Int, workDays: Set<Int>, now: Date = .now) -> Int {
        guard let earliest = data.days.keys.min(), !workDays.isEmpty else { return 0 }

        func isWorkDay(_ day: Date) -> Bool {
            workDays.contains(calendar.component(.weekday, from: day))
        }

        var day = calendar.startOfDay(for: now)
        var streak = isWorkDay(day) && goalReached(goal: goal, on: day) ? 1 : 0

        for _ in 0..<Self.maxStreakDays {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
            if dayKey(for: day) < earliest { break }
            guard isWorkDay(day) else { continue }
            guard goalReached(goal: goal, on: day) else { break }
            streak += 1
        }
        return streak
    }

    // MARK: Rotation

    var picker: ExercisePicker {
        get { data.picker }
        set {
            guard newValue != data.picker else { return }
            data.picker = newValue
            save(now: .now)
        }
    }

    // MARK: Reset

    /// Clears the completed-move history (and so the streak). The exercise rotation is kept.
    func resetAll() {
        data.days = [:]
        save(now: .now)
    }

    // MARK: Day keys

    /// "yyyy-MM-dd" for the local day containing `date`, built from calendar components.
    func dayKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0, month = parts.month ?? 0, day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: Storage

    private func load() -> ProgressFile {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return ProgressFile()
        }
        do {
            let raw = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(ProgressFile.self, from: raw)
        } catch {
            logger.error("Could not read progress file, starting fresh: \(error.localizedDescription, privacy: .public)")
            moveAside()
            return ProgressFile()
        }
    }

    /// Keeps an unreadable file as `progress.json.bak` instead of overwriting it.
    private func moveAside() {
        let backup = fileURL.appendingPathExtension("bak")
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: backup.path(percentEncoded: false)) {
                try fileManager.removeItem(at: backup)
            }
            try fileManager.moveItem(at: fileURL, to: backup)
        } catch {
            logger.error("Could not move progress file aside: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save(now: Date) {
        prune(now: now)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let raw = try encoder.encode(data)
            try raw.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not save progress file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func prune(now: Date) {
        guard let cutoffDate = calendar.date(byAdding: .day, value: -Self.keepDays, to: now) else { return }
        let cutoff = dayKey(for: cutoffDate)
        let old = data.days.keys.filter { $0 < cutoff }
        guard !old.isEmpty else { return }
        for key in old { data.days[key] = nil }
    }
}
