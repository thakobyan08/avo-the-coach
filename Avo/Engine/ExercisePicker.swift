import Foundation

/// Picks the next move: rotate through the enabled moves, never repeat one of the last 2,
/// and make at least every 3rd nudge a Walkabout (docs/SPEC.md, Timing and logic).
nonisolated struct ExercisePicker: Codable, Equatable, Sendable {
    static let historyLimit = 20
    static let noRepeatCount = 2

    /// Moves picked so far, most recent last.
    private(set) var history: [ExerciseID] = []
    var walkEvery = 3

    func next(from enabled: [ExerciseID]) -> ExerciseID? {
        guard !enabled.isEmpty else { return nil }

        if enabled.contains(.walk), walkEvery > 0 {
            let window = walkEvery - 1
            if history.count >= window, !history.suffix(window).contains(.walk) {
                return .walk
            }
        }

        let recent = history.suffix(Self.noRepeatCount)
        var candidates = enabled.filter { !recent.contains($0) }
        if candidates.isEmpty { candidates = enabled.filter { $0 != history.last } }
        if candidates.isEmpty { candidates = enabled }

        // Least recently used first; moves never used come first, in spec order.
        return candidates.min { lastUse($0) < lastUse($1) }
    }

    mutating func record(_ id: ExerciseID) {
        history.append(id)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }

    private func lastUse(_ id: ExerciseID) -> Int {
        history.lastIndex(of: id) ?? -1
    }
}
