import Foundation

/// The eight moves from docs/SPEC.md, in spec order.
nonisolated enum ExerciseID: String, CaseIterable, Codable, Identifiable, Sendable {
    case chinTuck, neckSide, shoulderRoll, thoracic, reach, lookFar, walk, breathe

    var id: String { rawValue }
}

nonisolated enum Face: String, Sendable {
    case happy, grin, wink, focus, calm, sleepy
}

/// How much of a move to do. What `amount` counts depends on the exercise's `DoseKind`.
nonisolated struct Dose: Codable, Hashable, Sendable {
    var amount: Int
    /// Only used by `.holds`.
    var holdSeconds: Int = 0
}

nonisolated struct Exercise: Identifiable, Hashable, Sendable {
    enum DoseKind: Hashable, Sendable {
        case slowReps, reps, secondsEachSide, holds, seconds, minutes, breaths

        /// Choices offered in Settings for `Dose.amount`.
        var amountPresets: [Int] {
            switch self {
            case .slowReps, .reps: [5, 8, 10, 12, 15, 20]
            case .secondsEachSide: [10, 15, 20, 30, 45, 60]
            case .holds: [2, 3, 4, 5]
            case .seconds: [10, 15, 20, 30, 45, 60]
            case .minutes: [1, 2, 3, 5]
            case .breaths: [3, 5, 8, 10]
            }
        }

        /// Choices offered in Settings for `Dose.holdSeconds`.
        static let holdSecondsPresets = [5, 10, 15, 20, 30]
    }

    /// One slow breath: in for 4, out for 6.
    static let breathSeconds = 10

    let id: ExerciseID
    let name: String
    let cue: String
    let doseKind: DoseKind
    let defaultDose: Dose
    let face: Face
    /// How to steps, shown when the card expands.
    let steps: [String]

    /// Asset name of the pose art, e.g. "avo-chinTuck".
    var poseAsset: String { "avo-\(id.rawValue)" }

    /// Dose as shown on the card, e.g. "10 slow reps" or "3 holds of 10 sec".
    func doseText(_ dose: Dose) -> String {
        switch doseKind {
        case .slowReps: dose.amount == 1 ? "1 slow rep" : "\(dose.amount) slow reps"
        case .reps: dose.amount == 1 ? "1 rep" : "\(dose.amount) reps"
        case .secondsEachSide: "\(dose.amount) sec each side"
        case .holds: "\(dose.amount == 1 ? "1 hold" : "\(dose.amount) holds") of \(dose.holdSeconds) sec"
        case .seconds: "\(dose.amount) sec"
        case .minutes: "\(dose.amount) min"
        case .breaths: dose.amount == 1 ? "1 breath" : "\(dose.amount) breaths"
        }
    }

    /// How long the in-progress countdown runs, in seconds.
    func duration(of dose: Dose, secondsPerRep: Int) -> Int {
        switch doseKind {
        case .slowReps, .reps: dose.amount * secondsPerRep
        case .secondsEachSide: dose.amount * 2
        case .holds: dose.amount * dose.holdSeconds
        case .seconds: dose.amount
        case .minutes: dose.amount * 60
        case .breaths: dose.amount * Self.breathSeconds
        }
    }
}

nonisolated extension Exercise {
    static let all: [Exercise] = [
        Exercise(id: .chinTuck, name: "Chin tucks",
                 cue: "Pull your chin straight back. Eyes stay level.",
                 doseKind: .slowReps, defaultDose: Dose(amount: 10), face: .focus,
                 steps: ["Sit tall with your shoulders relaxed.", "Slide your chin straight back, like a gentle double chin.", "Hold for a breath, then let go."]),
        Exercise(id: .neckSide, name: "Neck side stretch",
                 cue: "Ear toward shoulder. Let the other shoulder sink.",
                 doseKind: .secondsEachSide, defaultDose: Dose(amount: 20), face: .calm,
                 steps: ["Sit tall and tip your right ear toward your right shoulder.", "Let your left shoulder sink and breathe slowly.", "Come back to center and switch sides."]),
        Exercise(id: .shoulderRoll, name: "Shoulder rolls",
                 cue: "Big slow circles, rolling backward.",
                 doseKind: .reps, defaultDose: Dose(amount: 10), face: .happy,
                 steps: ["Let your arms hang loose.", "Lift your shoulders up toward your ears.", "Roll them back and down in a big, slow circle."]),
        Exercise(id: .thoracic, name: "Upper back opener",
                 cue: "Hands behind your head, lift your chest over the chair back.",
                 doseKind: .reps, defaultDose: Dose(amount: 8), face: .grin,
                 steps: ["Lace your hands behind your head, elbows wide.", "Lean back over the top of your chair.", "Lift your chest toward the ceiling, then sit up again."]),
        Exercise(id: .reach, name: "Overhead reach",
                 cue: "Fingers laced, push the ceiling away.",
                 doseKind: .holds, defaultDose: Dose(amount: 3, holdSeconds: 10), face: .happy,
                 steps: ["Lace your fingers and turn your palms up.", "Push the ceiling away with long arms.", "Hold and breathe, then lower and repeat."]),
        Exercise(id: .lookFar, name: "Eye break",
                 cue: "Look at something about 20 feet away.",
                 doseKind: .seconds, defaultDose: Dose(amount: 20), face: .focus,
                 steps: ["Find a spot about 20 feet (6 m) away, out a window if you can.", "Let your eyes rest on it.", "Blink slowly a few times."]),
        Exercise(id: .walk, name: "Walkabout",
                 cue: "Stand up, refill your water, take a lap.",
                 doseKind: .minutes, defaultDose: Dose(amount: 2), face: .happy,
                 steps: ["Stand up and stretch tall.", "Refill your water or take a lap.", "Come back and tap Done."]),
        Exercise(id: .breathe, name: "Slow breaths",
                 cue: "In for 4, out for 6. Shoulders stay low.",
                 doseKind: .breaths, defaultDose: Dose(amount: 5), face: .calm,
                 steps: ["Sit tall and let your shoulders drop.", "Breathe in through your nose for 4.", "Breathe out slowly for 6."]),
    ]

    static subscript(id: ExerciseID) -> Exercise {
        all.first { $0.id == id }!
    }
}
