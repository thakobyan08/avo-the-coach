import SwiftUI

/// The five nudge moments: shows up, in progress, done, snoozed and the pill.
struct NudgeContent: View {
    let model: AppModel
    let state: PanelState
    @State private var showHowTo = false

    /// Room around the card for its shadow, inside the panel.
    static let cardInsets = EdgeInsets(top: 10, leading: 24, bottom: 40, trailing: 20)
    static let pillInsets = EdgeInsets(top: 12, leading: 24, bottom: 34, trailing: 10)

    var body: some View {
        Group {
            switch model.nudges.phase {
            case .hidden:
                EmptyView()
            case let .card(nudge, _):
                ShowsUpCard(
                    exercise: Exercise[nudge.exercise],
                    dose: dose(for: nudge),
                    todayCount: model.todayCount,
                    showHowTo: $showHowTo,
                    onStart: model.nudges.start,
                    onLater: model.nudges.later,
                    onHowTo: model.nudges.keepCard
                )
                .padding(Self.cardInsets)
            case let .inProgress(nudge, started):
                InProgressCard(
                    exercise: Exercise[nudge.exercise],
                    dose: dose(for: nudge),
                    secondsPerRep: model.preferences.secondsPerRep,
                    started: started,
                    onDone: model.nudges.done,
                    onStop: model.nudges.stop
                )
                .padding(Self.cardInsets)
            case let .done(nudge, _):
                DoneCard(
                    exercise: Exercise[nudge.exercise],
                    todayCount: model.todayCount,
                    goal: model.preferences.dailyGoal
                )
                .padding(Self.cardInsets)
            case .snoozed:
                SnoozedCard(
                    minutes: model.preferences.snoozeMinutes,
                    backAt: model.nudges.scheduler.snoozeEnds,
                    onNow: model.nudges.start
                )
                .padding(Self.cardInsets)
            case let .pill(nudge, _):
                NudgePill(
                    exercise: Exercise[nudge.exercise],
                    isHovering: state.isHovering,
                    onStart: model.nudges.start,
                    onDismiss: model.nudges.dismiss
                )
                .padding(Self.pillInsets)
            }
        }
        .onChange(of: model.nudges.phase.nudge) { _, _ in showHowTo = false }
    }

    private func dose(for nudge: Nudge) -> Dose {
        model.preferences.setting(for: nudge.exercise).dose
    }
}

// MARK: - 1. Shows up

struct ShowsUpCard: View {
    let exercise: Exercise
    let dose: Dose
    let todayCount: Int
    @Binding var showHowTo: Bool
    let onStart: () -> Void
    let onLater: () -> Void
    let onHowTo: () -> Void

    var body: some View {
        CardShell {
            HStack(alignment: .top, spacing: 14) {
                ArtTile(pose: "avo-wave", label: "Avo waving")
                VStack(alignment: .leading, spacing: 4) {
                    CardHeader(trailing: "\(todayCount) today")
                    CardTitle(exercise.name)
                    CardBody(exercise.cue)
                    Text(exercise.doseText(dose))
                        .font(Theme.body(13, weight: .bold))
                        .foregroundStyle(Theme.accentText)
                    HStack(spacing: 8) {
                        Button("Start", action: onStart).buttonStyle(.avoPrimary)
                        Button("Later", action: onLater).buttonStyle(.avoSecondary)
                        Spacer(minLength: 0)
                        Button(showHowTo ? "Hide" : "How to") {
                            withAnimation(.spring(duration: 0.3, bounce: 0.1)) { showHowTo.toggle() }
                            onHowTo()
                        }
                        .buttonStyle(.avoLink)
                    }
                    .padding(.top, 8)
                }
            }
            if showHowTo {
                HowToSection(exercise: exercise, dose: dose)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct HowToSection: View {
    let exercise: Exercise
    let dose: Dose

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            HStack(alignment: .top, spacing: 14) {
                ArtTile(pose: exercise.poseAsset, label: "Avo doing \(exercise.name.lowercased())")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(exercise.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)")
                                .font(Theme.body(11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Theme.accent))
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
                            CardBody(step)
                        }
                    }
                    Text(exercise.doseText(dose))
                        .font(Theme.body(13, weight: .bold))
                        .foregroundStyle(Theme.accentText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - 2. In progress

struct InProgressCard: View {
    let exercise: Exercise
    let dose: Dose
    let secondsPerRep: Int
    let started: Date
    let onDone: () -> Void
    let onStop: () -> Void

    var body: some View {
        let total = max(1, exercise.duration(of: dose, secondsPerRep: secondsPerRep))
        TimelineView(.periodic(from: started, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(started))
            let remaining = max(0, Double(total) - elapsed)
            let finished = remaining <= 0
            CardShell {
                HStack(alignment: .top, spacing: 14) {
                    ArtTile(pose: exercise.poseAsset, label: "Avo doing \(exercise.name.lowercased())")
                    VStack(alignment: .leading, spacing: 4) {
                        CardHeader(trailing: counterText(elapsed: elapsed))
                        CardTitle(exercise.name)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Self.clock(remaining))
                                .font(Theme.display(30))
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                                .contentTransition(.numericText(countsDown: true))
                            Text(finished ? "Tap Done" : "left")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.mutedText)
                        }
                        ProgressBar(fraction: min(1, elapsed / Double(total)))
                        HStack(spacing: 8) {
                            Button("Done", action: onDone).buttonStyle(.avoPrimary)
                            Button("Stop", action: onStop).buttonStyle(.avoSecondary)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    /// "Rep 4 of 10". The app cannot see reps, so this is paced by the clock.
    private func counterText(elapsed: TimeInterval) -> String {
        func step(_ length: Int, of count: Int) -> Int {
            min(count, Int(elapsed) / max(1, length) + 1)
        }
        switch exercise.doseKind {
        case .slowReps, .reps:
            return "Rep \(step(secondsPerRep, of: dose.amount)) of \(dose.amount)"
        case .secondsEachSide:
            return "Side \(step(dose.amount, of: 2)) of 2"
        case .holds:
            return "Hold \(step(dose.holdSeconds, of: dose.amount)) of \(dose.amount)"
        case .breaths:
            return "Breath \(step(Exercise.breathSeconds, of: dose.amount)) of \(dose.amount)"
        case .seconds, .minutes:
            return exercise.doseText(dose)
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(Theme.cardButtonLight)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: proxy.size.width * fraction)
                        .animation(.linear(duration: 1), value: fraction)
                }
            }
            .padding(.top, 4)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

// MARK: - 3. Done

struct DoneCard: View {
    let exercise: Exercise
    let todayCount: Int
    let goal: Int
    @State private var bounce = false

    var body: some View {
        CardShell {
            HStack(alignment: .top, spacing: 14) {
                ArtTile(pose: "avo-cheer", label: "Avo cheering")
                    .scaleEffect(bounce ? 1 : 0.92)
                    .animation(.spring(duration: 0.4, bounce: 0.5), value: bounce)
                    .onAppear { bounce = true }
                VStack(alignment: .leading, spacing: 4) {
                    CardHeader(trailing: "+1")
                    CardTitle("Nice one!")
                    CardBody("\(exercise.name) done. That makes \(todayCount) today.")
                    HStack(spacing: 6) {
                        if goal <= 10 {
                            ForEach(0..<goal, id: \.self) { index in
                                Circle()
                                    .fill(index < todayCount ? Theme.accent : Theme.dotEmpty)
                                    .frame(width: 12, height: 12)
                            }
                        }
                        Text("\(todayCount) of \(goal) today")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.mutedText)
                            .padding(.leading, goal <= 10 ? 6 : 0)
                    }
                    .padding(.top, 8)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - 4. Snoozed

struct SnoozedCard: View {
    let minutes: Int
    let backAt: Date?
    let onNow: () -> Void

    var body: some View {
        CardShell {
            HStack(alignment: .top, spacing: 14) {
                ArtTile(pose: "avo-snooze", label: "Avo snoozing")
                VStack(alignment: .leading, spacing: 4) {
                    CardHeader(trailing: backAt.map { "Back at \($0.formatted(date: .omitted, time: .shortened))" } ?? "")
                    CardTitle("No stress")
                    CardBody("I will check back in \(minutes) \(minutes == 1 ? "minute" : "minutes").")
                    HStack(spacing: 8) {
                        Button("Actually, now", action: onNow).buttonStyle(.avoSecondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}

// MARK: - 5. Left alone

struct NudgePill: View {
    let exercise: Exercise
    let isHovering: Bool
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AvoFace()
            Text("\(exercise.name) waiting")
                .font(Theme.body(13, weight: .bold))
                .foregroundStyle(Theme.ink)
            Button("Start", action: onStart).buttonStyle(.avoPrimary)
        }
        .padding(6)
        .background(Capsule().fill(.white).shadow(color: Theme.ink.opacity(0.12), radius: 12, y: 10))
        .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Theme.cardButtonLight))
                    .overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .offset(x: -6, y: -6)
            .opacity(isHovering ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .accessibilityLabel("Dismiss")
        }
    }
}

/// Face crop of avo-idle in a 44 pt circle, as in the Flow design.
struct AvoFace: View {
    var body: some View {
        Image("avo-idle")
            .resizable()
            .frame(width: 80, height: 112)
            .offset(x: -18, y: -21)
            .frame(width: 44, height: 44, alignment: .topLeading)
            .background(Theme.tile)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}
