import Foundation

nonisolated struct Nudge: Equatable, Sendable {
    let exercise: ExerciseID
    /// Asked for from the menu ("Nudge me now"). Quiet does not hide it.
    var isManual = false
}

/// Why Avo is staying quiet (spec state 4).
nonisolated enum QuietReason: Equatable, Sendable {
    case camera, microphone, fullScreen, outsideWorkHours
}

/// What the sensors report on each tick.
nonisolated struct Conditions: Equatable, Sendable {
    var idleSeconds: TimeInterval = 0
    var quiet: QuietReason?
    var isPaused = false
    /// The pointer is over the nudge card.
    var isHovering = false
}

/// What the user is doing, as the scheduler sees it (spec states 1 to 4).
nonisolated enum Activity: Equatable, Sendable {
    case paused
    /// Input within the active window; time counts toward the next nudge.
    case working
    /// No input for a little while, not yet long enough to count as a break.
    case idle
    /// No input for the away threshold; the work timer was reset.
    case away
    case quiet(QuietReason)
}

/// What is on screen (spec states 5 to 9).
nonisolated enum NudgePhase: Equatable, Sendable {
    case hidden
    case card(Nudge, since: Date)
    case inProgress(Nudge, started: Date)
    case done(Nudge, until: Date)
    case snoozed(Nudge, until: Date)
    case pill(Nudge, since: Date)

    var nudge: Nudge? {
        switch self {
        case .hidden: nil
        case let .card(nudge, _), let .inProgress(nudge, _), let .done(nudge, _),
             let .snoozed(nudge, _), let .pill(nudge, _): nudge
        }
    }
}

nonisolated enum SchedulerEvent: Equatable, Sendable {
    case shown(Nudge)
    case completed(Nudge)
    case stopped(Nudge)
    case skipped(Nudge)
}

/// Spec timings in seconds, plus the moves that are on.
nonisolated struct SchedulerConfig: Equatable, Sendable {
    var workInterval: TimeInterval = 25 * 60
    var activeWindow: TimeInterval = 2 * 60
    var awayAfter: TimeInterval = 5 * 60
    var quietGrace: TimeInterval = 60
    var cardDuration: TimeInterval = 60
    var pillTimeout: TimeInterval = 10 * 60
    var snoozeLength: TimeInterval = 10 * 60
    var latersBeforeSkip = 3
    var celebrateDuration: TimeInterval = 3
    var snoozeConfirmDuration: TimeInterval = 2
    var enabledExercises: [ExerciseID] = ExerciseID.allCases
}

/// The nudge state machine from docs/SPEC.md. Pure logic: time and sensor readings come in through `tick`,
/// user actions through the action methods, and side effects go out as `SchedulerEvent`s.
nonisolated struct Scheduler: Sendable {
    /// A nudge that came due but is not on screen: snoozed, or waiting for Quiet to end.
    struct Pending: Equatable, Sendable {
        /// Nil until the nudge is first shown and its move is picked.
        var nudge: Nudge?
        /// End of a snooze.
        var notBefore: Date?
    }

    /// Ticks further apart than this (a stalled run loop) only count this much active time.
    /// A gap of `awayAfter` or more means the Mac slept, which counts as a break.
    static let maxTickGap: TimeInterval = 60

    var config: SchedulerConfig
    private(set) var phase: NudgePhase = .hidden
    private(set) var activity: Activity = .working
    /// Active work since the last break or nudge.
    private(set) var activeTime: TimeInterval = 0
    private(set) var pending: Pending?
    private(set) var latersInARow = 0
    private(set) var picker: ExercisePicker
    private var lastTick: Date?
    private var wasQuiet = false
    private var quietEndedAt: Date?

    init(config: SchedulerConfig = .init(), picker: ExercisePicker = .init()) {
        self.config = config
        self.picker = picker
    }

    /// Active work left until the next nudge comes due.
    var timeUntilDue: TimeInterval { max(0, config.workInterval - activeTime) }

    /// When a snoozed nudge comes back.
    var snoozeEnds: Date? { pending?.notBefore }

    // MARK: Clock

    mutating func tick(now: Date, conditions: Conditions) -> [SchedulerEvent] {
        let gap = max(now.timeIntervalSince(lastTick ?? now), 0)
        let slept = gap >= config.awayAfter
        let elapsed = slept ? 0 : min(gap, Self.maxTickGap)
        lastTick = now

        let isQuiet = conditions.quiet != nil
        if isQuiet {
            quietEndedAt = nil
        } else if wasQuiet {
            quietEndedAt = now
        }
        wasQuiet = isQuiet

        var events: [SchedulerEvent] = []
        advanceVisiblePhase(now: now, conditions: conditions, events: &events)

        // The Mac slept: a break, like Away.
        if slept, phase == .hidden {
            activity = .away
            resetCycle()
        }

        // A snooze the user asked for from the menu comes back on time, whatever the hour or Quiet.
        if phase == .hidden, let pending, let nudge = pending.nudge, nudge.isManual,
           now >= pending.notBefore ?? .distantPast {
            show(nudge, now: now, events: &events)
            return events
        }

        if conditions.isPaused {
            activity = .paused
            return events
        }
        if conditions.quiet == .outsideWorkHours {
            activity = .quiet(.outsideWorkHours)
            resetCycle(keepingManualSnooze: true)
            return events
        }
        guard phase == .hidden else { return events }

        // A full-screen app (or anything else) with nobody at the keyboard is still Away. Calls are exempt.
        let awayDespiteQuiet = conditions.quiet == .fullScreen && conditions.idleSeconds >= config.awayAfter
        if let quiet = conditions.quiet, !awayDespiteQuiet {
            // On a call or watching something full screen: still at the desk, so it counts as work, never as Away.
            activity = .quiet(quiet)
            activeTime += elapsed
        } else if conditions.idleSeconds >= config.awayAfter {
            activity = .away
            resetCycle() // Being away counts as a break.
        } else if conditions.idleSeconds < config.activeWindow {
            activity = .working
            activeTime += elapsed
        } else {
            activity = .idle
        }

        if pending == nil, activeTime >= config.workInterval {
            pending = Pending()
        }
        if let pending, !isQuiet, now >= pending.notBefore ?? .distantPast, quietGraceIsOver(now) {
            show(pending.nudge, now: now, events: &events)
        }
        return events
    }

    private mutating func advanceVisiblePhase(now: Date, conditions: Conditions, events: inout [SchedulerEvent]) {
        switch phase {
        case .hidden, .inProgress:
            break
        case let .card(nudge, since):
            if shouldHide(nudge, conditions) {
                hide(nudge)
            } else if conditions.isHovering {
                // Being looked at: the 60 seconds start over once the pointer leaves.
                phase = .card(nudge, since: now)
            } else if now.timeIntervalSince(since) >= config.cardDuration {
                phase = .pill(nudge, since: now)
            }
        case let .pill(nudge, since):
            if shouldHide(nudge, conditions) {
                hide(nudge)
            } else if now.timeIntervalSince(since) >= config.pillTimeout {
                skip(nudge, events: &events)
            }
        case let .done(_, until), let .snoozed(_, until):
            if now >= until { phase = .hidden }
        }
    }

    // MARK: Actions

    /// Menu: Nudge me now. Shows the waiting nudge, or a fresh one, even during Quiet or Pause.
    mutating func nudgeNow(now: Date) -> [SchedulerEvent] {
        switch phase {
        case .hidden, .done, .snoozed:
            var nudge = pending?.nudge ?? pickNudge()
            nudge?.isManual = true
            var events: [SchedulerEvent] = []
            show(nudge, now: now, events: &events)
            return events
        case .card, .pill, .inProgress:
            return []
        }
    }

    /// Card or pill: Start. Snooze confirmation: Actually, now.
    mutating func start(now: Date) {
        switch phase {
        case let .card(nudge, _), let .pill(nudge, _), let .snoozed(nudge, _):
            phase = .inProgress(nudge, started: now)
            pending = nil
            latersInARow = 0
        default:
            break
        }
    }

    /// The user is looking at the card (hovering, reading How to): restart its 60 seconds.
    mutating func keepCard(now: Date) {
        if case let .card(nudge, _) = phase {
            phase = .card(nudge, since: now)
        }
    }

    /// Card or pill: Later. Snoozes, or skips the nudge on the last Later in a row.
    mutating func later(now: Date) -> [SchedulerEvent] {
        switch phase {
        case let .card(nudge, _), let .pill(nudge, _):
            latersInARow += 1
            if latersInARow >= config.latersBeforeSkip {
                var events: [SchedulerEvent] = []
                skip(nudge, events: &events)
                return events
            }
            phase = .snoozed(nudge, until: now.addingTimeInterval(config.snoozeConfirmDuration))
            pending = Pending(nudge: nudge, notBefore: now.addingTimeInterval(config.snoozeLength))
            return []
        default:
            return []
        }
    }

    /// In progress: Done. Celebrates, credits the move and restarts the work timer.
    mutating func done(now: Date) -> [SchedulerEvent] {
        guard case let .inProgress(nudge, _) = phase else { return [] }
        phase = .done(nudge, until: now.addingTimeInterval(config.celebrateDuration))
        resetCycle()
        return [.completed(nudge)]
    }

    /// In progress: Stop. No credit, work timer restarts.
    mutating func stop() -> [SchedulerEvent] {
        guard case let .inProgress(nudge, _) = phase else { return [] }
        phase = .hidden
        resetCycle()
        return [.stopped(nudge)]
    }

    /// Pill ✕ (or closing the card). Skips the nudge, work timer restarts.
    mutating func dismiss() -> [SchedulerEvent] {
        switch phase {
        case let .card(nudge, _), let .pill(nudge, _):
            var events: [SchedulerEvent] = []
            skip(nudge, events: &events)
            return events
        default:
            return []
        }
    }

    /// Pausing from the menu: close everything and start fresh afterwards.
    mutating func reset() {
        phase = .hidden
        resetCycle()
    }

    #if DEBUG
    mutating func debugSetActiveTime(_ seconds: TimeInterval) {
        activeTime = seconds
    }
    #endif

    // MARK: Helpers

    private func shouldHide(_ nudge: Nudge, _ conditions: Conditions) -> Bool {
        !nudge.isManual && (conditions.quiet != nil || conditions.isPaused)
    }

    private func quietGraceIsOver(_ now: Date) -> Bool {
        guard let quietEndedAt else { return true }
        return now.timeIntervalSince(quietEndedAt) >= config.quietGrace
    }

    private mutating func pickNudge() -> Nudge? {
        guard let id = picker.next(from: config.enabledExercises) else { return nil }
        picker.record(id)
        return Nudge(exercise: id)
    }

    private mutating func show(_ chosen: Nudge?, now: Date, events: inout [SchedulerEvent]) {
        // A move turned off in Settings while this nudge waited is swapped for another.
        let stillEnabled = chosen.map { config.enabledExercises.contains($0.exercise) } ?? false
        let kept = stillEnabled ? chosen : chosen.flatMap { old in
            pickNudge().map { Nudge(exercise: $0.exercise, isManual: old.isManual) }
        }
        guard let nudge = kept ?? pickNudge() else {
            pending = nil
            return
        }
        pending = nil
        phase = .card(nudge, since: now)
        events.append(.shown(nudge))
    }

    private mutating func hide(_ nudge: Nudge) {
        phase = .hidden
        pending = Pending(nudge: nudge, notBefore: nil)
    }

    private mutating func skip(_ nudge: Nudge, events: inout [SchedulerEvent]) {
        phase = .hidden
        resetCycle()
        events.append(.skipped(nudge))
    }

    private mutating func resetCycle(keepingManualSnooze: Bool = false) {
        activeTime = 0
        latersInARow = 0
        if !(keepingManualSnooze && pending?.nudge?.isManual == true) {
            pending = nil
        }
    }
}
