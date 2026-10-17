import Foundation
import Observation
import os

/// Runs the `Scheduler` against the real clock and sensors, and forwards user actions to it.
@Observable
final class NudgeController {
    private(set) var scheduler = Scheduler()

    var phase: NudgePhase { scheduler.phase }

    /// Asked on every tick so the menu's pause state is the only source of truth.
    @ObservationIgnored var isPaused: () -> Bool = { false }
    /// Set by the panel while the pointer is over the card.
    @ObservationIgnored var isHovering = false
    @ObservationIgnored var onEvent: (SchedulerEvent) -> Void = { _ in }
    /// Called when the move rotation changes, so it can be saved.
    @ObservationIgnored var onPickerChange: (ExercisePicker) -> Void = { _ in }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// Sensor readings are reused for this long, so 1-second ticks stay cheap.
    @ObservationIgnored private var lastReading: (at: Date, idle: TimeInterval, quiet: QuietReason?)?
    private static let sensorInterval: TimeInterval = 4.5
    /// Keeps App Nap from stretching the 5-second tick, which would undercount active time.
    @ObservationIgnored private let activity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep,
        reason: "Avo counts active work time"
    )
    @ObservationIgnored private let log = Logger(subsystem: "com.thakobyan08.avo", category: "nudge")

    init(preferences: Preferences, picker: ExercisePicker = ExercisePicker()) {
        self.preferences = preferences
        scheduler = Scheduler(picker: picker)
    }

    func run() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.tick() else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Runs one step and returns how long to wait before the next: every second while something
    /// is on screen, every 5 seconds otherwise.
    @discardableResult
    func tick() -> Duration {
        let now = Date.now
        scheduler.config = SchedulerConfig(preferences)
        let reading = sensorReading(now: now)
        let conditions = Conditions(
            idleSeconds: reading.idle,
            quiet: reading.quiet,
            isPaused: isPaused(),
            isHovering: isHovering
        )
        let before = scheduler.activity
        handle(scheduler.tick(now: now, conditions: conditions))
        if scheduler.activity != before {
            log.info("Activity: \(String(describing: self.scheduler.activity), privacy: .public)")
        }
        return scheduler.phase == .hidden ? .seconds(5) : .seconds(1)
    }

    private func sensorReading(now: Date) -> (at: Date, idle: TimeInterval, quiet: QuietReason?) {
        if let last = lastReading, now.timeIntervalSince(last.at) < Self.sensorInterval, now >= last.at {
            // Idle time keeps growing between readings unless there was input.
            return (now, min(Sensors.idleSeconds(), last.idle + now.timeIntervalSince(last.at)), last.quiet)
        }
        let reading = (
            at: now,
            idle: Sensors.idleSeconds(),
            quiet: Sensors.quietReason(workHours: WorkHours(preferences), now: now)
        )
        lastReading = reading
        return reading
    }

    // MARK: Actions

    func nudgeNow() { act { $0.nudgeNow(now: .now) } }
    func start() { act { $0.start(now: .now); return [] } }
    func later() { act { $0.later(now: .now) } }
    func done() { act { $0.done(now: .now) } }
    func stop() { act { $0.stop() } }
    func dismiss() { act { $0.dismiss() } }
    func reset() { act { $0.reset(); return [] } }
    func keepCard() { act { $0.keepCard(now: .now); return [] } }

    #if DEBUG
    /// Makes the next nudge come due in `seconds` of active work.
    func debugDue(in seconds: TimeInterval) {
        scheduler.debugSetActiveTime(max(0, scheduler.config.workInterval - seconds))
    }
    #endif

    private func act(_ action: (inout Scheduler) -> [SchedulerEvent]) {
        scheduler.config = SchedulerConfig(preferences)
        handle(action(&scheduler))
        // Restart the loop so short timers (2 s snooze message, 3 s celebration) tick on time.
        run()
    }

    private func handle(_ events: [SchedulerEvent]) {
        for event in events {
            log.info("Event: \(String(describing: event), privacy: .public)")
            if case .shown = event { onPickerChange(scheduler.picker) }
            onEvent(event)
        }
    }
}

extension SchedulerConfig {
    init(_ preferences: Preferences) {
        self.init(
            workInterval: TimeInterval(preferences.workIntervalMinutes * 60),
            activeWindow: TimeInterval(preferences.activeWindowMinutes * 60),
            awayAfter: TimeInterval(preferences.awayMinutes * 60),
            quietGrace: TimeInterval(preferences.quietGraceMinutes * 60),
            cardDuration: TimeInterval(preferences.cardSeconds),
            pillTimeout: TimeInterval(preferences.pillMinutes * 60),
            snoozeLength: TimeInterval(preferences.snoozeMinutes * 60),
            latersBeforeSkip: preferences.latersBeforeSkip,
            celebrateDuration: TimeInterval(preferences.celebrateSeconds),
            snoozeConfirmDuration: TimeInterval(preferences.snoozeConfirmSeconds),
            enabledExercises: preferences.enabledExercises.map(\.id)
        )
    }
}

extension WorkHours {
    init(_ preferences: Preferences) {
        self.init(
            days: preferences.workDays,
            startMinute: preferences.workStartMinute,
            endMinute: preferences.workEndMinute
        )
    }
}
