import SwiftUI

struct MenuContent: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Nudge me now") { model.nudgeNow() }

        Divider()

        if model.isPaused {
            Text(pausedText)
            Button("Resume") { model.resume() }
        } else {
            if let reason = model.quietReason {
                Text(quietText(reason))
            }
            Button("Pause 1 hour") { model.pause(for: .seconds(3600)) }
            Button("Pause until tomorrow") { model.pauseUntilTomorrow() }
        }

        Divider()

        Text("Today: \(model.todayCount) of \(model.preferences.dailyGoal)")
        Text(model.streak == 1 ? "Streak: 1 day" : "Streak: \(model.streak) days")

        Divider()

        #if DEBUG
        DebugMenu(nudges: model.nudges)
        Divider()
        #endif

        Button("Settings…") {
            // Avo has no Dock icon, so bring it forward or the window opens behind other apps.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Quit Avo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var pausedText: String {
        guard let until = model.pausedUntil else { return "Paused" }
        let calendar = Calendar.current
        if calendar.isDateInToday(until) {
            return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        if until == calendar.startOfDay(for: until) {
            return "Paused until tomorrow"
        }
        return "Paused until \(until.formatted(date: .abbreviated, time: .shortened))"
    }

    private func quietText(_ reason: QuietReason) -> String {
        switch reason {
        case .camera: "Quiet: camera in use"
        case .microphone: "Quiet: microphone in use"
        case .fullScreen: "Quiet: full-screen app"
        case .outsideWorkHours: "Quiet: outside work hours"
        }
    }
}

#if DEBUG
/// Engine state and the card's actions, for testing without waiting. Not in Release builds.
private struct DebugMenu: View {
    let nudges: NudgeController

    var body: some View {
        Menu("Debug") {
            Text("Status: \(statusText)")
            Text("On screen: \(phaseText)")
            Text("Active: \(minutes(nudges.scheduler.activeTime)), due in \(minutes(nudges.scheduler.timeUntilDue))")
            if let ends = nudges.scheduler.snoozeEnds {
                Text("Snoozed until \(ends.formatted(date: .omitted, time: .standard))")
            }
            Text("Laters in a row: \(nudges.scheduler.latersInARow)")
            Text("Recent moves: \(nudges.scheduler.picker.history.suffix(4).map(\.rawValue).joined(separator: ", "))")
            Divider()
            Button("Make nudge due in 20 s") { nudges.debugDue(in: 20) }
            Divider()
            Button("Start") { nudges.start() }
            Button("Later") { nudges.later() }
            Button("Done") { nudges.done() }
            Button("Stop") { nudges.stop() }
            Button("Dismiss (pill ✕)") { nudges.dismiss() }
        }
    }

    private var statusText: String {
        switch nudges.scheduler.activity {
        case .paused: "Paused"
        case .working: "Working"
        case .idle: "Idle (not counting)"
        case .away: "Away (timer reset)"
        case .quiet(.camera): "Quiet, camera in use"
        case .quiet(.microphone): "Quiet, mic in use"
        case .quiet(.fullScreen): "Quiet, full-screen app"
        case .quiet(.outsideWorkHours): "Quiet, outside work hours"
        }
    }

    private var phaseText: String {
        let name = nudges.phase.nudge.map { Exercise[$0.exercise].name } ?? ""
        return switch nudges.phase {
        case .hidden: "nothing"
        case .card: "card, \(name)"
        case .inProgress: "in progress, \(name)"
        case .done: "done, \(name)"
        case .snoozed: "snooze message, \(name)"
        case .pill: "pill, \(name)"
        }
    }

    private func minutes(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
#endif
