import Foundation
import Observation
import os
import Testing
@testable import Avo

/// A fresh temp folder and a fixed-time-zone Gregorian calendar per test.
@MainActor
final class StoreFixture {
    let directory: URL
    let calendar: Calendar
    private(set) var store: ProgressStore

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "ProgressStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 4 * 3600)!
        self.calendar = calendar
        store = ProgressStore(directory: directory, calendar: calendar)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Reopens the store from disk, like a relaunch.
    @discardableResult
    func reopen() -> ProgressStore {
        store = ProgressStore(directory: directory, calendar: calendar)
        return store
    }

    var fileURL: URL { directory.appending(path: ProgressStore.fileName) }

    /// A local time in the fixture's calendar. 2026-10-12 is a Monday.
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute, second: second))!
    }

    /// Records `count` moves on the given day.
    func complete(_ count: Int, on day: Date) {
        for _ in 0..<count { store.recordCompleted(.chinTuck, at: day) }
    }
}

@MainActor
struct ProgressStoreTests {
    static let weekdays: Set<Int> = [2, 3, 4, 5, 6]

    // MARK: Counting

    @Test func `a new store has no moves`() {
        let f = StoreFixture()
        #expect(f.store.count(on: f.date(2026, 10, 12)) == 0)
        #expect(f.store.todayCount == 0)
        #expect(!FileManager.default.fileExists(atPath: f.fileURL.path(percentEncoded: false)))
    }

    @Test func `moves are counted per day`() {
        let f = StoreFixture()
        f.complete(3, on: f.date(2026, 10, 12))
        f.complete(1, on: f.date(2026, 10, 13))
        #expect(f.store.count(on: f.date(2026, 10, 12, 8)) == 3)
        #expect(f.store.count(on: f.date(2026, 10, 13, 20)) == 1)
        #expect(f.store.count(on: f.date(2026, 10, 14)) == 0)
    }

    @Test func `the day changes at local midnight`() {
        let f = StoreFixture()
        f.store.recordCompleted(.walk, at: f.date(2026, 10, 12, 23, 59, 59))
        f.store.recordCompleted(.walk, at: f.date(2026, 10, 13, 0, 0, 0))
        #expect(f.store.count(on: f.date(2026, 10, 12, 0, 0, 0)) == 1)
        #expect(f.store.count(on: f.date(2026, 10, 13, 23, 59, 59)) == 1)
        #expect(f.store.dayKey(for: f.date(2026, 10, 12, 23, 59, 59)) == "2026-10-12")
        #expect(f.store.dayKey(for: f.date(2026, 10, 13, 0, 0, 0)) == "2026-10-13")
    }

    @Test func `day keys follow the calendar time zone, not UTC`() {
        let f = StoreFixture()
        // 01:00 local at UTC+4 is still the previous day in UTC.
        #expect(f.store.dayKey(for: f.date(2026, 1, 5, 1)) == "2026-01-05")
    }

    @Test func `today count uses the current date`() {
        let f = StoreFixture()
        f.store.recordCompleted(.breathe)
        f.store.recordCompleted(.reach)
        #expect(f.store.todayCount == 2)
        #expect(f.store.goalReached(goal: 2))
        #expect(!f.store.goalReached(goal: 3))
    }

    @Test func `observers of today count are told when a move is recorded`() {
        let f = StoreFixture()
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = f.store.todayCount
        } onChange: {
            changed.withLock { $0 = true }
        }
        f.store.recordCompleted(.shoulderRoll)
        #expect(changed.withLock { $0 })
    }

    // MARK: Persistence

    @Test func `history survives a relaunch`() throws {
        let f = StoreFixture()
        f.complete(4, on: f.date(2026, 10, 12))
        f.store.recordCompleted(.lookFar, at: f.date(2026, 10, 13))
        #expect(FileManager.default.fileExists(atPath: f.fileURL.path(percentEncoded: false)))

        let reopened = f.reopen()
        #expect(reopened.count(on: f.date(2026, 10, 12)) == 4)
        #expect(reopened.count(on: f.date(2026, 10, 13)) == 1)
    }

    @Test func `the file is versioned JSON keyed by day`() throws {
        let f = StoreFixture()
        f.store.recordCompleted(.walk, at: f.date(2026, 10, 12))
        let raw = try Data(contentsOf: f.fileURL)
        let file = try JSONDecoder().decode(ProgressFile.self, from: raw)
        #expect(file.version == 1)
        #expect(file.days == ["2026-10-12": [.walk]])
        let json = try #require(String(data: raw, encoding: .utf8))
        #expect(json.contains("\"version\" : 1"))
    }

    @Test func `the directory is created if missing`() {
        let f = StoreFixture()
        #expect(!FileManager.default.fileExists(atPath: f.directory.path(percentEncoded: false)))
        f.store.recordCompleted(.walk, at: f.date(2026, 10, 12))
        #expect(FileManager.default.fileExists(atPath: f.fileURL.path(percentEncoded: false)))
    }

    @Test func `the exercise rotation survives a relaunch`() {
        let f = StoreFixture()
        var picker = f.store.picker
        picker.record(.chinTuck)
        picker.record(.neckSide)
        picker.walkEvery = 4
        f.store.picker = picker

        let reopened = f.reopen()
        #expect(reopened.picker == picker)
        #expect(reopened.picker.history == [.chinTuck, .neckSide])
        #expect(reopened.picker.walkEvery == 4)
    }

    @Test func `a corrupt file is moved aside and the store starts empty`() throws {
        let f = StoreFixture()
        try FileManager.default.createDirectory(at: f.directory, withIntermediateDirectories: true)
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: f.fileURL)

        let store = f.reopen()
        #expect(store.count(on: f.date(2026, 10, 12)) == 0)
        #expect(store.picker == ExercisePicker())

        let backup = f.fileURL.appendingPathExtension("bak")
        #expect(try Data(contentsOf: backup) == garbage)
        #expect(!FileManager.default.fileExists(atPath: f.fileURL.path(percentEncoded: false)))

        store.recordCompleted(.walk, at: f.date(2026, 10, 12))
        #expect(f.reopen().count(on: f.date(2026, 10, 12)) == 1)
        #expect(try Data(contentsOf: backup) == garbage)
    }

    @Test func `a file with missing fields still loads`() throws {
        let f = StoreFixture()
        try FileManager.default.createDirectory(at: f.directory, withIntermediateDirectories: true)
        try Data(#"{"days":{"2026-10-12":["walk","breathe"]}}"#.utf8).write(to: f.fileURL)

        let store = f.reopen()
        #expect(store.count(on: f.date(2026, 10, 12)) == 2)
        #expect(store.picker == ExercisePicker())
    }

    @Test func `days older than the keep window are pruned on save`() {
        let f = StoreFixture()
        let old = f.date(2025, 1, 1)
        let recent = f.date(2026, 10, 12)
        let edge = f.calendar.date(byAdding: .day, value: -ProgressStore.keepDays, to: recent)!
        f.complete(2, on: old)
        f.complete(1, on: edge)
        f.complete(1, on: recent)

        let reopened = f.reopen()
        #expect(reopened.count(on: old) == 0)
        #expect(reopened.count(on: edge) == 1)
        #expect(reopened.count(on: recent) == 1)
    }

    @Test func `reset clears history but keeps the rotation`() {
        let f = StoreFixture()
        f.complete(3, on: f.date(2026, 10, 12))
        var picker = f.store.picker
        picker.record(.walk)
        f.store.picker = picker

        f.store.resetAll()
        #expect(f.store.count(on: f.date(2026, 10, 12)) == 0)
        #expect(f.reopen().count(on: f.date(2026, 10, 12)) == 0)
        #expect(f.store.picker.history == [.walk])
    }

    // MARK: Streak

    @Test func `no history means no streak`() {
        let f = StoreFixture()
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: f.date(2026, 10, 14)) == 0)
    }

    @Test func `goal reached several work days in a row`() {
        let f = StoreFixture()
        f.complete(6, on: f.date(2026, 10, 12)) // Mon
        f.complete(7, on: f.date(2026, 10, 13)) // Tue
        f.complete(6, on: f.date(2026, 10, 14)) // Wed
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: f.date(2026, 10, 14, 18)) == 3)
    }

    @Test func `an unfinished today does not break the streak`() {
        let f = StoreFixture()
        f.complete(6, on: f.date(2026, 10, 12))
        f.complete(6, on: f.date(2026, 10, 13))
        f.complete(2, on: f.date(2026, 10, 14)) // Wed, in progress
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: f.date(2026, 10, 14, 15)) == 2)
        // The next day, the unfinished Wednesday is a missed work day.
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: f.date(2026, 10, 15, 9)) == 0)
    }

    @Test func `nothing done yet today keeps yesterday's streak`() {
        let f = StoreFixture()
        f.complete(6, on: f.date(2026, 10, 12))
        f.complete(6, on: f.date(2026, 10, 13))
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: f.date(2026, 10, 14, 9)) == 2)
    }

    @Test func `reaching the goal today adds today`() {
        let f = StoreFixture()
        f.complete(6, on: f.date(2026, 10, 13))
        f.complete(5, on: f.date(2026, 10, 14))
        let now = f.date(2026, 10, 14, 16)
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: now) == 1)
        f.store.recordCompleted(.walk, at: now)
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: now) == 2)
    }

    @Test func `the weekend is skipped`() {
        let f = StoreFixture()
        f.complete(6, on: f.date(2026, 10, 15)) // Thu
        f.complete(6, on: f.date(2026, 10, 16)) // Fri
        f.complete(6, on: f.date(2026, 10, 19)) // Mon
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: f.date(2026, 10, 19, 17)) == 3)
        // Checked on Sunday, Friday's streak still stands and Sunday adds nothing.
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: f.date(2026, 10, 18, 12)) == 2)
    }

    @Test func `moves on a non-work day do not count toward the streak`() {
        let f = StoreFixture()
        f.complete(6, on: f.date(2026, 10, 16)) // Fri
        f.complete(6, on: f.date(2026, 10, 17)) // Sat
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: f.date(2026, 10, 17, 20)) == 1)
    }

    @Test func `a missed work day ends the streak`() {
        let f = StoreFixture()
        f.complete(6, on: f.date(2026, 10, 12)) // Mon
        f.complete(6, on: f.date(2026, 10, 13)) // Tue
        f.complete(3, on: f.date(2026, 10, 14)) // Wed, missed
        f.complete(6, on: f.date(2026, 10, 15)) // Thu
        f.complete(6, on: f.date(2026, 10, 16)) // Fri
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: f.date(2026, 10, 16, 18)) == 2)
    }

    @Test func `a work day with no moves at all ends the streak`() {
        let f = StoreFixture()
        f.complete(6, on: f.date(2026, 10, 12)) // Mon
        f.complete(6, on: f.date(2026, 10, 14)) // Wed, Tue empty
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: f.date(2026, 10, 14, 18)) == 1)
    }

    @Test func `custom work days are respected`() {
        let f = StoreFixture()
        let mwf: Set<Int> = [2, 4, 6]
        f.complete(6, on: f.date(2026, 10, 12)) // Mon
        f.complete(6, on: f.date(2026, 10, 14)) // Wed
        f.complete(6, on: f.date(2026, 10, 16)) // Fri
        #expect(f.store.streak(goal: 6, workDays: mwf, now: f.date(2026, 10, 16, 18)) == 3)
        #expect(f.store.streak(goal: 6, workDays: Self.weekdays, now: f.date(2026, 10, 16, 18)) == 1)
        #expect(f.store.streak(goal: 6, workDays: [], now: f.date(2026, 10, 16, 18)) == 0)
    }

    @Test func `the streak spans months and uses the given goal`() {
        let f = StoreFixture()
        f.complete(3, on: f.date(2026, 9, 29)) // Tue
        f.complete(3, on: f.date(2026, 9, 30)) // Wed
        f.complete(3, on: f.date(2026, 10, 1)) // Thu
        #expect(f.store.streak(goal: 3, workDays: Self.weekdays, now: f.date(2026, 10, 1, 18)) == 3)
        #expect(f.store.streak(goal: 4, workDays: Self.weekdays, now: f.date(2026, 10, 1, 18)) == 0)
    }

    @Test func `the streak survives a relaunch`() {
        let f = StoreFixture()
        f.complete(6, on: f.date(2026, 10, 12))
        f.complete(6, on: f.date(2026, 10, 13))
        #expect(f.reopen().streak(goal: 6, workDays: Self.weekdays, now: f.date(2026, 10, 13, 18)) == 2)
    }
}
