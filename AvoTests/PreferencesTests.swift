import Foundation
import Testing
@testable import Avo

struct PreferencesTests {
    let defaults: UserDefaults

    init() {
        let suite = "avo.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func `defaults match the spec`() {
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.workIntervalMinutes == 25)
        #expect(prefs.cardSeconds == 60)
        #expect(prefs.pillMinutes == 10)
        #expect(prefs.snoozeMinutes == 10)
        #expect(prefs.latersBeforeSkip == 3)
        #expect(prefs.celebrateSeconds == 3)
        #expect(prefs.snoozeConfirmSeconds == 2)
        #expect(prefs.secondsPerRep == 3)
        #expect(prefs.activeWindowMinutes == 2)
        #expect(prefs.awayMinutes == 5)
        #expect(prefs.quietGraceMinutes == 1)
        #expect(prefs.dailyGoal == 6)
        #expect(prefs.workDays == [2, 3, 4, 5, 6])
        #expect(prefs.workStartMinute == 9 * 60)
        #expect(prefs.workEndMinute == 19 * 60)
        #expect(prefs.soundEnabled == false)
        #expect(prefs.enabledExercises.count == 8)
    }

    @Test func `changes survive a relaunch`() {
        let prefs = Preferences(defaults: defaults)
        prefs.workIntervalMinutes = 40
        prefs.workDays = [1, 7]
        prefs.updateExercise(.walk) { $0.enabled = false }
        prefs.updateExercise(.chinTuck) { $0.dose.amount = 12 }

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.workIntervalMinutes == 40)
        #expect(reloaded.workDays == [1, 7])
        #expect(reloaded.setting(for: .walk).enabled == false)
        #expect(reloaded.setting(for: .chinTuck).dose.amount == 12)
    }

    @Test func `restore defaults resets timings`() {
        let prefs = Preferences(defaults: defaults)
        prefs.cardSeconds = 120
        prefs.awayMinutes = 20
        prefs.resetTimings()
        #expect(prefs.cardSeconds == 60)
        #expect(prefs.awayMinutes == 5)
    }

    @Test(arguments: [
        (ExerciseID.chinTuck, "10 slow reps"),
        (.neckSide, "20 sec each side"),
        (.shoulderRoll, "10 reps"),
        (.thoracic, "8 reps"),
        (.reach, "3 holds of 10 sec"),
        (.lookFar, "20 sec"),
        (.walk, "2 min"),
        (.breathe, "5 breaths"),
    ])
    func `default dose text matches the spec`(id: ExerciseID, text: String) {
        let exercise = Exercise[id]
        #expect(exercise.doseText(exercise.defaultDose) == text)
    }

    @Test func `values edited by hand are clamped to what Settings allows`() {
        defaults.set(0, forKey: "cardSeconds")
        defaults.set(1, forKey: "latersBeforeSkip")
        defaults.set([Int](), forKey: "workDays")
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.cardSeconds == 15)
        #expect(prefs.latersBeforeSkip == 2)
        #expect(prefs.workDays == Preferences.Default.workDays)
    }
}

struct FormatTests {
    @Test func `labels read in plain words`() {
        #expect(Format.minutes(1) == "1 minute")
        #expect(Format.minutes(25) == "25 minutes")
        #expect(Format.seconds(45) == "45 seconds")
        #expect(Format.seconds(60) == "1 minute")
        #expect(Format.seconds(90) == "1 min 30 sec")
        #expect(Format.ordinal(3) == "3rd")
        #expect(Format.ordinal(11) == "11th")
    }

    @Test func `a stored value that is not a preset still appears`() {
        #expect(Format.options([10, 25, 30], including: 35) == [10, 25, 30, 35])
        #expect(Format.options([10, 25, 30], including: 25) == [10, 25, 30])
    }

    @Test func `every default is one of the presets`() {
        for exercise in Exercise.all {
            #expect(exercise.doseKind.amountPresets.contains(exercise.defaultDose.amount), "\(exercise.id)")
        }
    }
}
