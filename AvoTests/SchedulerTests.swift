import Foundation
import Testing
@testable import Avo

/// Drives a `Scheduler` with a fake clock, 5-second ticks like the app.
final class Harness {
    var scheduler: Scheduler
    var now = Date(timeIntervalSinceReferenceDate: 0)
    var conditions = Conditions()
    private(set) var events: [SchedulerEvent] = []

    init(_ config: SchedulerConfig = SchedulerConfig()) {
        scheduler = Scheduler(config: config)
        _ = scheduler.tick(now: now, conditions: conditions)
    }

    func advance(_ seconds: TimeInterval, step: TimeInterval = 5) {
        var elapsed: TimeInterval = 0
        while elapsed < seconds {
            elapsed += step
            now += step
            events += scheduler.tick(now: now, conditions: conditions)
        }
    }

    func act(_ action: (inout Scheduler, Date) -> [SchedulerEvent]) {
        events += action(&scheduler, now)
    }

    var phase: NudgePhase { scheduler.phase }
    var isCard: Bool { if case .card = phase { true } else { false } }
    var isPill: Bool { if case .pill = phase { true } else { false } }
    var shownCount: Int { events.filter { if case .shown = $0 { true } else { false } }.count }
}

struct SchedulerTests {
    @Test func `nudge shows after 25 minutes of active work`() {
        let h = Harness()
        h.advance(25 * 60 - 5)
        #expect(h.phase == .hidden)
        h.advance(5)
        #expect(h.isCard)
        #expect(h.shownCount == 1)
    }

    @Test func `idle between 2 and 5 minutes pauses the timer without resetting it`() {
        let h = Harness()
        h.advance(10 * 60)
        h.conditions.idleSeconds = 3 * 60
        h.advance(60)
        #expect(h.scheduler.activity == .idle)
        #expect(h.scheduler.activeTime == 10 * 60)
    }

    @Test func `being away for 5 minutes resets the work timer`() {
        let h = Harness()
        h.advance(20 * 60)
        h.conditions.idleSeconds = 5 * 60
        h.advance(5)
        #expect(h.scheduler.activity == .away)
        #expect(h.scheduler.activeTime == 0)
    }

    @Test func `a due nudge waits until 1 minute after Quiet ends`() {
        let h = Harness()
        h.advance(20 * 60)
        h.conditions.quiet = .camera
        h.advance(10 * 60)
        #expect(h.phase == .hidden)
        #expect(h.scheduler.pending != nil)

        // Quiet is seen to end on the first tick without it, 5 seconds in; the card waits a minute from there.
        h.conditions.quiet = nil
        h.advance(60)
        #expect(h.phase == .hidden)
        h.advance(5)
        #expect(h.isCard)
    }

    @Test func `a long call is not counted as Away`() {
        let h = Harness()
        h.advance(10 * 60)
        h.conditions.quiet = .microphone
        h.conditions.idleSeconds = 30 * 60
        h.advance(5 * 60)
        #expect(h.scheduler.activity == .quiet(.microphone))
        #expect(h.scheduler.activeTime == 15 * 60)
    }

    @Test func `a card on screen hides when a call starts and comes back after it`() {
        let h = Harness()
        h.advance(25 * 60)
        let nudge = h.phase.nudge
        h.conditions.quiet = .camera
        h.advance(5)
        #expect(h.phase == .hidden)
        h.conditions.quiet = nil
        h.advance(65)
        #expect(h.isCard)
        #expect(h.phase.nudge == nudge)
    }

    @Test func `outside work hours resets the timer and shows nothing`() {
        let h = Harness()
        h.advance(20 * 60)
        h.conditions.quiet = .outsideWorkHours
        h.advance(30 * 60)
        #expect(h.phase == .hidden)
        #expect(h.scheduler.activeTime == 0)
    }

    @Test func `card becomes a pill after 60 seconds`() {
        let h = Harness()
        h.advance(25 * 60)
        h.advance(55)
        #expect(h.isCard)
        h.advance(5)
        #expect(h.isPill)
    }

    @Test func `pill ignored for 10 minutes skips the nudge and restarts the timer`() {
        let h = Harness()
        h.advance(25 * 60 + 60)
        #expect(h.isPill)
        h.advance(10 * 60)
        #expect(h.phase == .hidden)
        #expect(h.events.last.map { if case .skipped = $0 { true } else { false } } == true)
        #expect(h.scheduler.activeTime < 60)
    }

    @Test func `pill dismiss skips the nudge`() {
        let h = Harness()
        h.advance(25 * 60 + 60)
        h.act { s, _ in s.dismiss() }
        #expect(h.phase == .hidden)
        #expect(h.scheduler.activeTime == 0)
    }

    @Test func `Later shows a 2 second message then brings the same move back after 10 minutes`() {
        let h = Harness()
        h.advance(25 * 60)
        let nudge = h.phase.nudge
        h.act { s, now in s.later(now: now) }
        guard case .snoozed = h.phase else { Issue.record("expected snooze message"); return }

        h.advance(2, step: 1)
        #expect(h.phase == .hidden)
        h.advance(10 * 60 - 5)
        #expect(h.phase == .hidden)
        h.advance(5)
        #expect(h.isCard)
        #expect(h.phase.nudge == nudge)
    }

    @Test func `the third Later in a row skips the nudge`() {
        let h = Harness()
        h.advance(25 * 60)
        h.act { s, now in s.later(now: now) }
        h.advance(10 * 60 + 5)
        h.act { s, now in s.later(now: now) }
        h.advance(10 * 60 + 5)
        #expect(h.isCard)
        h.act { s, now in s.later(now: now) }
        #expect(h.phase == .hidden)
        #expect(h.scheduler.pending == nil)
        #expect(h.scheduler.latersInARow == 0)
        #expect(h.events.last.map { if case .skipped = $0 { true } else { false } } == true)
    }

    @Test func `Actually, now starts the snoozed move`() {
        let h = Harness()
        h.advance(25 * 60)
        h.act { s, now in s.later(now: now) }
        h.act { s, now in s.start(now: now); return [] }
        guard case .inProgress = h.phase else { Issue.record("expected in progress"); return }
        #expect(h.scheduler.pending == nil)
    }

    @Test func `Done celebrates for 3 seconds, credits the move and restarts the timer`() {
        let h = Harness()
        h.advance(25 * 60)
        h.act { s, now in s.start(now: now); return [] }
        h.advance(30)
        h.act { s, now in s.done(now: now) }
        #expect(h.events.contains { if case .completed = $0 { true } else { false } })
        guard case .done = h.phase else { Issue.record("expected done"); return }
        #expect(h.scheduler.activeTime == 0)
        h.advance(3, step: 1)
        #expect(h.phase == .hidden)
    }

    @Test func `Stop gives no credit and restarts the timer`() {
        let h = Harness()
        h.advance(25 * 60)
        h.act { s, now in s.start(now: now); return [] }
        h.act { s, _ in s.stop() }
        #expect(h.phase == .hidden)
        #expect(!h.events.contains { if case .completed = $0 { true } else { false } })
        #expect(h.scheduler.activeTime == 0)
    }

    @Test func `the in-progress card stays while the user walks away`() {
        let h = Harness()
        h.advance(25 * 60)
        h.act { s, now in s.start(now: now); return [] }
        h.conditions.idleSeconds = 10 * 60
        h.advance(10 * 60)
        guard case .inProgress = h.phase else { Issue.record("expected in progress"); return }
    }

    @Test func `Nudge me now shows a card even during Quiet, and Quiet does not hide it`() {
        let h = Harness()
        h.conditions.quiet = .fullScreen
        h.act { s, now in s.nudgeNow(now: now) }
        #expect(h.isCard)
        h.advance(30)
        #expect(h.isCard)
    }

    @Test func `paused shows nothing`() {
        let h = Harness()
        h.conditions.isPaused = true
        h.advance(60 * 60)
        #expect(h.phase == .hidden)
        #expect(h.scheduler.activity == .paused)
    }

    @Test func `a short stall between ticks counts at most a minute`() {
        let h = Harness()
        h.advance(3 * 60, step: 3 * 60)
        #expect(h.scheduler.activeTime == Scheduler.maxTickGap)
    }

    @Test func `sleeping the Mac counts as a break`() {
        let h = Harness()
        h.advance(20 * 60)
        h.advance(60 * 60, step: 60 * 60) // lid closed for an hour; input on wake keeps idle at 0
        #expect(h.scheduler.activeTime == 0)
    }

    @Test func `sleeping cancels a snoozed nudge`() {
        let h = Harness()
        h.advance(25 * 60)
        h.act { s, now in s.later(now: now) }
        h.advance(5)
        h.advance(60 * 60, step: 60 * 60)
        #expect(h.scheduler.pending == nil)
    }

    @Test func `a full-screen app with nobody at the keyboard is Away`() {
        let h = Harness()
        h.advance(20 * 60)
        h.conditions.quiet = .fullScreen
        h.conditions.idleSeconds = 5 * 60
        h.advance(5)
        #expect(h.scheduler.activity == .away)
        #expect(h.scheduler.activeTime == 0)
    }

    @Test func `hovering keeps the card from becoming a pill`() {
        let h = Harness()
        h.advance(25 * 60)
        h.conditions.isHovering = true
        h.advance(3 * 60)
        #expect(h.isCard)
        h.conditions.isHovering = false
        h.advance(55)
        #expect(h.isCard)
        h.advance(10)
        #expect(h.isPill)
    }

    @Test func `a snooze from Nudge me now comes back on time outside work hours`() {
        let h = Harness()
        h.conditions.quiet = .outsideWorkHours
        h.act { s, now in s.nudgeNow(now: now) }
        h.act { s, now in s.later(now: now) }
        h.advance(10 * 60 - 5)
        #expect(h.phase == .hidden)
        h.advance(5)
        #expect(h.isCard)
    }

    @Test func `a waiting move that was turned off is swapped for another`() {
        let h = Harness()
        h.advance(25 * 60)
        let first = h.phase.nudge!.exercise
        h.act { s, now in s.later(now: now) }
        h.scheduler.config.enabledExercises.removeAll { $0 == first }
        h.advance(10 * 60 + 5)
        #expect(h.isCard)
        #expect(h.phase.nudge?.exercise != first)
    }

    @Test func `the next nudge after one is done needs another full interval`() {
        let h = Harness()
        h.advance(25 * 60)
        h.act { s, now in s.start(now: now); return [] }
        h.act { s, now in s.done(now: now) }
        h.advance(25 * 60 - 5)
        #expect(h.shownCount == 1)
        h.advance(5)
        #expect(h.shownCount == 2)
    }
}

struct ExercisePickerTests {
    private func run(_ count: Int, enabled: [ExerciseID] = ExerciseID.allCases) -> [ExerciseID] {
        var picker = ExercisePicker()
        var picks: [ExerciseID] = []
        for _ in 0..<count {
            guard let next = picker.next(from: enabled) else { break }
            picker.record(next)
            picks.append(next)
        }
        return picks
    }

    @Test func `never repeats one of the last 2 moves`() {
        let picks = run(60)
        for i in 2..<picks.count {
            #expect(picks[i] != picks[i - 1] && picks[i] != picks[i - 2], "repeat at \(i): \(picks)")
        }
    }

    @Test func `Walkabout at least every 3rd nudge`() {
        let picks = run(60)
        for i in 2..<picks.count {
            #expect(picks[(i - 2)...i].contains(.walk), "no walk in nudges \(i - 2)...\(i): \(picks)")
        }
    }

    @Test func `rotates through every enabled move`() {
        #expect(Set(run(24)) == Set(ExerciseID.allCases))
    }

    @Test func `works without Walkabout`() {
        let enabled = ExerciseID.allCases.filter { $0 != .walk }
        let picks = run(14, enabled: enabled)
        #expect(!picks.contains(.walk))
        #expect(Set(picks) == Set(enabled))
    }

    @Test func `alternates when only 2 moves are on`() {
        #expect(run(4, enabled: [.chinTuck, .breathe]) == [.chinTuck, .breathe, .chinTuck, .breathe])
    }

    @Test func `repeats when only 1 move is on, and gives nothing when none are`() {
        #expect(run(3, enabled: [.reach]) == [.reach, .reach, .reach])
        #expect(run(1, enabled: []).isEmpty)
    }
}

struct WorkHoursTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-10-12 is a Monday.
    private func date(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private let weekdays = WorkHours(days: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 19 * 60)

    @Test func `Monday to Friday, 9:00 to 19:00`() {
        #expect(weekdays.contains(date(day: 12, 9, 0), calendar: calendar))
        #expect(weekdays.contains(date(day: 16, 18, 59), calendar: calendar))
        #expect(!weekdays.contains(date(day: 12, 8, 59), calendar: calendar))
        #expect(!weekdays.contains(date(day: 12, 19, 0), calendar: calendar))
        #expect(!weekdays.contains(date(day: 17, 12), calendar: calendar)) // Saturday
    }

    @Test func `hours that run past midnight belong to the day they start`() {
        let night = WorkHours(days: [6], startMinute: 22 * 60, endMinute: 2 * 60) // Friday night
        #expect(night.contains(date(day: 16, 23), calendar: calendar))
        #expect(night.contains(date(day: 17, 1), calendar: calendar))
        #expect(!night.contains(date(day: 18, 1), calendar: calendar))
    }
}
