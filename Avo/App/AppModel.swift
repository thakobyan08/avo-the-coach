import AppKit
import Observation
import os

/// App-wide state shared by the menu, Settings and the nudge engine.
@Observable
final class AppModel {
    let preferences: Preferences
    let loginItem = LoginItem()
    let nudges: NudgeController
    let progress: ProgressStore

    private(set) var pausedUntil: Date? {
        didSet { defaults.set(pausedUntil, forKey: Self.pausedUntilKey) }
    }


    /// Start of the current day, so the menu's Today and Streak refresh at midnight.
    private(set) var today = Calendar.autoupdatingCurrent.startOfDay(for: .now)

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var panel: NudgePanelController?
    @ObservationIgnored private let log = Logger(subsystem: "com.thakobyan08.avo", category: "app")

    private static let pausedUntilKey = "pausedUntil"

    init(defaults: UserDefaults = .standard, progress: ProgressStore = ProgressStore()) {
        self.defaults = defaults
        self.progress = progress
        preferences = Preferences(defaults: defaults)
        nudges = NudgeController(preferences: preferences, picker: progress.picker)
        pausedUntil = defaults.object(forKey: Self.pausedUntilKey) as? Date
        expirePause()

        nudges.isPaused = { [weak self] in self?.isPaused ?? false }
        nudges.onEvent = { [weak self] in self?.handle($0) }
        nudges.onPickerChange = { [weak self] in self?.progress.picker = $0 }
        nudges.run()
        panel = NudgePanelController(model: self)

        #if DEBUG
        // `open Avo.app --args -AvoNudgeOnLaunch YES` shows a card right away, for testing the panel.
        if defaults.bool(forKey: "AvoNudgeOnLaunch") {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.nudgeNow()
            }
        }
        #endif

        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self?.expirePause()
                self?.refreshToday()
            }
        }
    }

    var todayCount: Int {
        _ = today
        return progress.todayCount
    }

    var streak: Int {
        _ = today
        return progress.streak(goal: preferences.dailyGoal, workDays: preferences.workDays)
    }

    /// Why Avo is holding back right now, for the menu. Nil while working.
    var quietReason: QuietReason? {
        if case let .quiet(reason) = nudges.scheduler.activity { return reason }
        return nil
    }

    var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > .now
    }

    // MARK: Menu actions

    func nudgeNow() {
        nudges.nudgeNow()
    }

    func pause(for duration: Duration) {
        pausedUntil = .now.addingTimeInterval(TimeInterval(duration.components.seconds))
        nudges.reset()
    }

    func pauseUntilTomorrow() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        pausedUntil = calendar.startOfDay(for: tomorrow)
        nudges.reset()
    }

    func resume() {
        pausedUntil = nil
    }

    // MARK: Engine events

    private func handle(_ event: SchedulerEvent) {
        switch event {
        case .shown:
            if preferences.soundEnabled { NSSound(named: "Glass")?.play() }
        case let .completed(nudge):
            progress.recordCompleted(nudge.exercise)
        case .stopped, .skipped:
            break
        }
    }

    private func refreshToday() {
        let start = Calendar.autoupdatingCurrent.startOfDay(for: .now)
        if start != today { today = start }
    }

    private func expirePause() {
        if let pausedUntil, pausedUntil <= .now {
            self.pausedUntil = nil
        }
    }
}
