import Foundation
import Observation

nonisolated struct ExerciseSetting: Codable, Hashable, Sendable {
    var enabled: Bool
    var dose: Dose
}

/// Every tunable value from docs/SPEC.md, starting at the spec's defaults and saved to UserDefaults.
@Observable
final class Preferences {
    /// Spec defaults. Times are in the unit named by the property.
    enum Default {
        static let workIntervalMinutes = 25
        static let dailyGoal = 6
        static let workDays: Set<Int> = [2, 3, 4, 5, 6] // Calendar weekdays, 1 = Sunday
        static let workStartMinute = 9 * 60
        static let workEndMinute = 19 * 60
        static let cardSeconds = 60
        static let pillMinutes = 10
        static let snoozeMinutes = 10
        static let latersBeforeSkip = 3
        static let celebrateSeconds = 3
        static let snoozeConfirmSeconds = 2
        static let secondsPerRep = 3
        static let activeWindowMinutes = 2
        static let awayMinutes = 5
        static let quietGraceMinutes = 1
        static let soundEnabled = false
    }

    /// Allowed values, shared with the Settings steppers.
    enum Limits {
        static let workIntervalMinutes = 5...120
        static let dailyGoal = 1...20
        static let minuteOfDay = 0...(24 * 60 - 1)
        static let cardSeconds = 15...300
        static let pillMinutes = 1...60
        static let snoozeMinutes = 1...60
        static let latersBeforeSkip = 2...10
        static let shortSeconds = 1...10
        static let activeWindowMinutes = 1...10
        static let awayMinutes = 1...30
        static let quietGraceMinutes = 0...10
    }

    private enum Key: String {
        case workIntervalMinutes, dailyGoal, workDays, workStartMinute, workEndMinute
        case cardSeconds, pillMinutes, snoozeMinutes, latersBeforeSkip
        case celebrateSeconds, snoozeConfirmSeconds, secondsPerRep
        case activeWindowMinutes, awayMinutes, quietGraceMinutes
        case soundEnabled, exercises
    }

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: Schedule

    /// Minutes of active work before a nudge.
    var workIntervalMinutes: Int { didSet { save(workIntervalMinutes, .workIntervalMinutes) } }
    var dailyGoal: Int { didSet { save(dailyGoal, .dailyGoal) } }
    var workDays: Set<Int> { didSet { save(workDays.sorted(), .workDays) } }
    /// Minutes after midnight.
    var workStartMinute: Int { didSet { save(workStartMinute, .workStartMinute) } }
    /// Minutes after midnight.
    var workEndMinute: Int { didSet { save(workEndMinute, .workEndMinute) } }

    // MARK: Nudge card

    var cardSeconds: Int { didSet { save(cardSeconds, .cardSeconds) } }
    var pillMinutes: Int { didSet { save(pillMinutes, .pillMinutes) } }
    var snoozeMinutes: Int { didSet { save(snoozeMinutes, .snoozeMinutes) } }
    /// The Later that reaches this count in a row skips the nudge.
    var latersBeforeSkip: Int { didSet { save(latersBeforeSkip, .latersBeforeSkip) } }
    var celebrateSeconds: Int { didSet { save(celebrateSeconds, .celebrateSeconds) } }
    var snoozeConfirmSeconds: Int { didSet { save(snoozeConfirmSeconds, .snoozeConfirmSeconds) } }
    var secondsPerRep: Int { didSet { save(secondsPerRep, .secondsPerRep) } }

    // MARK: Activity

    /// Input within this window counts as active work.
    var activeWindowMinutes: Int { didSet { save(activeWindowMinutes, .activeWindowMinutes) } }
    /// No input for this long counts as a break.
    var awayMinutes: Int { didSet { save(awayMinutes, .awayMinutes) } }
    /// A nudge that came due during Quiet waits this long after Quiet ends.
    var quietGraceMinutes: Int { didSet { save(quietGraceMinutes, .quietGraceMinutes) } }

    // MARK: Other

    var soundEnabled: Bool { didSet { save(soundEnabled, .soundEnabled) } }
    private(set) var exercises: [ExerciseID: ExerciseSetting] { didSet { saveExercises() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        /// Stored values are clamped to the ranges Settings allows, in case they were edited by hand.
        func int(_ key: Key, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
            let value = defaults.object(forKey: key.rawValue) as? Int ?? fallback
            return min(max(value, range.lowerBound), range.upperBound)
        }
        workIntervalMinutes = int(.workIntervalMinutes, Default.workIntervalMinutes, Limits.workIntervalMinutes)
        dailyGoal = int(.dailyGoal, Default.dailyGoal, Limits.dailyGoal)
        let days = (defaults.array(forKey: Key.workDays.rawValue) as? [Int]).map { Set($0.filter { (1...7).contains($0) }) }
        workDays = days.flatMap { $0.isEmpty ? nil : $0 } ?? Default.workDays
        workStartMinute = int(.workStartMinute, Default.workStartMinute, Limits.minuteOfDay)
        workEndMinute = int(.workEndMinute, Default.workEndMinute, Limits.minuteOfDay)
        cardSeconds = int(.cardSeconds, Default.cardSeconds, Limits.cardSeconds)
        pillMinutes = int(.pillMinutes, Default.pillMinutes, Limits.pillMinutes)
        snoozeMinutes = int(.snoozeMinutes, Default.snoozeMinutes, Limits.snoozeMinutes)
        latersBeforeSkip = int(.latersBeforeSkip, Default.latersBeforeSkip, Limits.latersBeforeSkip)
        celebrateSeconds = int(.celebrateSeconds, Default.celebrateSeconds, Limits.shortSeconds)
        snoozeConfirmSeconds = int(.snoozeConfirmSeconds, Default.snoozeConfirmSeconds, Limits.shortSeconds)
        secondsPerRep = int(.secondsPerRep, Default.secondsPerRep, Limits.shortSeconds)
        activeWindowMinutes = int(.activeWindowMinutes, Default.activeWindowMinutes, Limits.activeWindowMinutes)
        awayMinutes = int(.awayMinutes, Default.awayMinutes, Limits.awayMinutes)
        quietGraceMinutes = int(.quietGraceMinutes, Default.quietGraceMinutes, Limits.quietGraceMinutes)
        soundEnabled = defaults.object(forKey: Key.soundEnabled.rawValue) as? Bool ?? Default.soundEnabled
        exercises = Self.loadExercises(from: defaults)
    }

    // MARK: Exercises

    func setting(for id: ExerciseID) -> ExerciseSetting {
        exercises[id] ?? Self.defaultSetting(for: id)
    }

    func updateExercise(_ id: ExerciseID, _ change: (inout ExerciseSetting) -> Void) {
        var setting = setting(for: id)
        change(&setting)
        exercises[id] = setting
    }

    var enabledExercises: [Exercise] {
        Exercise.all.filter { setting(for: $0.id).enabled }
    }

    // MARK: Reset

    /// Restores the card, activity and rep-pace timings to the spec defaults.
    func resetTimings() {
        cardSeconds = Default.cardSeconds
        pillMinutes = Default.pillMinutes
        snoozeMinutes = Default.snoozeMinutes
        latersBeforeSkip = Default.latersBeforeSkip
        celebrateSeconds = Default.celebrateSeconds
        snoozeConfirmSeconds = Default.snoozeConfirmSeconds
        secondsPerRep = Default.secondsPerRep
        activeWindowMinutes = Default.activeWindowMinutes
        awayMinutes = Default.awayMinutes
        quietGraceMinutes = Default.quietGraceMinutes
    }

    // MARK: Storage

    private func save(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private func saveExercises() {
        let byName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(byName) {
            defaults.set(data, forKey: Key.exercises.rawValue)
        }
    }

    private static func defaultSetting(for id: ExerciseID) -> ExerciseSetting {
        ExerciseSetting(enabled: true, dose: Exercise[id].defaultDose)
    }

    private static func loadExercises(from defaults: UserDefaults) -> [ExerciseID: ExerciseSetting] {
        var stored: [String: ExerciseSetting] = [:]
        if let data = defaults.data(forKey: Key.exercises.rawValue) {
            stored = (try? JSONDecoder().decode([String: ExerciseSetting].self, from: data)) ?? [:]
        }
        var result: [ExerciseID: ExerciseSetting] = [:]
        for id in ExerciseID.allCases {
            result[id] = stored[id.rawValue] ?? defaultSetting(for: id)
        }
        return result
    }
}
