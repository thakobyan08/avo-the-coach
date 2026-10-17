import SwiftUI

/// Avo's Settings window, laid out like macOS System Settings: a toolbar of tabs, grouped forms,
/// labels on the left and controls on the right. Values are picked from pop-up menus of sensible
/// presets, so they read in plain words and can never be invalid.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(loginItem: model.loginItem, preferences: model.preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
            ScheduleSettings(preferences: model.preferences)
                .tabItem { Label("Schedule", systemImage: "calendar") }
            ExerciseSettings(preferences: model.preferences)
                .tabItem { Label("Moves", systemImage: "figure.cooldown") }
            TimingSettings(preferences: model.preferences)
                .tabItem { Label("Timing", systemImage: "timer") }
        }
        .frame(width: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    let loginItem: LoginItem
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Launch Avo at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.needsApproval {
                    LabeledContent {
                        Button("Open Login Items…") { loginItem.openSystemSettings() }
                    } label: {
                        Text("Allow Avo in System Settings to finish turning this on.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = loginItem.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                Toggle("Play a sound when Avo shows up", isOn: $preferences.soundEnabled)
            }
            Section {
                LabeledContent("Version", value: Bundle.main.shortVersion)
            } footer: {
                Text("Avo makes no network calls and collects no data. Everything stays on this Mac.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginItem.refresh() }
    }
}

// MARK: - Schedule

private struct ScheduleSettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section {
                ValuePicker(
                    "Nudge after active work",
                    value: $preferences.workIntervalMinutes,
                    presets: [10, 15, 20, 25, 30, 45, 60, 90, 120],
                    label: Format.minutes
                )
                ValuePicker(
                    "Daily goal",
                    value: $preferences.dailyGoal,
                    presets: Array(1...12),
                    label: { $0 == 1 ? "1 move" : "\($0) moves" }
                )
            } footer: {
                Text("Active work is time with keyboard or mouse input. A break of a few minutes starts the count again.")
                    .foregroundStyle(.secondary)
            }
            Section {
                DatePicker("From", selection: minuteBinding(\.workStartMinute), displayedComponents: .hourAndMinute)
                DatePicker("To", selection: minuteBinding(\.workEndMinute), displayedComponents: .hourAndMinute)
                LabeledContent("Days") {
                    HStack(spacing: 4) {
                        ForEach(Self.orderedWeekdays, id: \.self) { weekday in
                            Toggle(Calendar.current.shortWeekdaySymbols[weekday - 1], isOn: dayBinding(weekday))
                                .toggleStyle(.button)
                                // Keep at least one work day, or Avo would never nudge.
                                .disabled(preferences.workDays == [weekday])
                        }
                    }
                }
            } header: {
                Text("Work hours")
            } footer: {
                Text(workHoursFooter)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var workHoursFooter: String {
        if preferences.workStartMinute == preferences.workEndMinute {
            return "Same start and end: Avo nudges all day on these days."
        }
        if preferences.workEndMinute < preferences.workStartMinute {
            return "Your hours run past midnight. Avo stays quiet outside them."
        }
        return "Avo stays quiet outside these hours."
    }

    /// Calendar weekdays (1 = Sunday) starting from the user's first day of the week.
    private static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private func dayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { preferences.workDays.contains(weekday) },
            set: { on in
                if on { preferences.workDays.insert(weekday) } else { preferences.workDays.remove(weekday) }
            }
        )
    }

    /// Bridges minutes-after-midnight to a `Date` for `DatePicker`.
    private func minuteBinding(_ keyPath: ReferenceWritableKeyPath<Preferences, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = preferences[keyPath: keyPath]
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now
                ) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                preferences[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

// MARK: - Moves

private struct ExerciseSettings: View {
    let preferences: Preferences

    var body: some View {
        Form {
            Section {
                ForEach(Exercise.all) { exercise in
                    ExerciseRow(exercise: exercise, preferences: preferences)
                }
            } footer: {
                Text("Avo rotates through the moves that are on, and suggests a Walkabout at least every third nudge.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
    }
}

private struct ExerciseRow: View {
    let exercise: Exercise
    let preferences: Preferences

    private var setting: ExerciseSetting { preferences.setting(for: exercise.id) }

    /// Keep at least one move on, or Avo has nothing to suggest.
    private var isLastEnabled: Bool {
        setting.enabled && preferences.enabledExercises.count == 1
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                dosePickers
                    .disabled(!setting.enabled)
                Toggle("On", isOn: binding(\.enabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(isLastEnabled)
                    .help(isLastEnabled ? "At least one move stays on." : "")
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                Text(exercise.cue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var dosePickers: some View {
        let kind = exercise.doseKind
        if kind == .holds {
            Picker("Holds", selection: binding(\.dose.amount)) {
                ForEach(Format.options(kind.amountPresets, including: setting.dose.amount), id: \.self) { count in
                    Text(count == 1 ? "1 hold" : "\(count) holds").tag(count)
                }
            }
            .labelsHidden()
            .fixedSize()
            Picker("Each hold", selection: binding(\.dose.holdSeconds)) {
                ForEach(
                    Format.options(Exercise.DoseKind.holdSecondsPresets, including: setting.dose.holdSeconds),
                    id: \.self
                ) { seconds in
                    Text("of \(seconds) sec").tag(seconds)
                }
            }
            .labelsHidden()
            .fixedSize()
        } else {
            Picker("Dose", selection: binding(\.dose.amount)) {
                ForEach(Format.options(kind.amountPresets, including: setting.dose.amount), id: \.self) { amount in
                    Text(exercise.doseText(Dose(amount: amount, holdSeconds: setting.dose.holdSeconds))).tag(amount)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ExerciseSetting, Value>) -> Binding<Value> {
        Binding(
            get: { setting[keyPath: keyPath] },
            set: { value in preferences.updateExercise(exercise.id) { $0[keyPath: keyPath] = value } }
        )
    }
}

// MARK: - Timing

private struct TimingSettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section {
                ValuePicker(
                    "Card stays on screen", value: $preferences.cardSeconds,
                    presets: [15, 30, 45, 60, 90, 120, 180, 300], label: Format.seconds
                )
                ValuePicker(
                    "Pill waits before skipping", value: $preferences.pillMinutes,
                    presets: [2, 5, 10, 15, 20, 30, 60], label: Format.minutes
                )
                ValuePicker(
                    "Later snoozes for", value: $preferences.snoozeMinutes,
                    presets: [5, 10, 15, 20, 30, 45, 60], label: Format.minutes
                )
                ValuePicker(
                    "Skip the nudge on the", value: $preferences.latersBeforeSkip,
                    presets: [2, 3, 4, 5], label: { "\(Format.ordinal($0)) Later in a row" }
                )
            } header: {
                Text("Nudge card")
            } footer: {
                Text("If you leave the card alone, it tucks into a small pill at the screen edge.")
                    .foregroundStyle(.secondary)
            }
            Section("Pace") {
                ValuePicker(
                    "Time per rep", value: $preferences.secondsPerRep,
                    presets: [2, 3, 4, 5, 6], label: Format.seconds
                )
                ValuePicker(
                    "Celebration lasts", value: $preferences.celebrateSeconds,
                    presets: [2, 3, 5, 8], label: Format.seconds
                )
                ValuePicker(
                    "Snooze message shows for", value: $preferences.snoozeConfirmSeconds,
                    presets: [1, 2, 3, 5], label: Format.seconds
                )
            }
            Section {
                ValuePicker(
                    "Counts as active with input in the last", value: $preferences.activeWindowMinutes,
                    presets: [1, 2, 3, 5], label: Format.minutes
                )
                ValuePicker(
                    "Counts as a break after no input for", value: $preferences.awayMinutes,
                    presets: [3, 5, 10, 15, 20, 30], label: Format.minutes
                )
                ValuePicker(
                    "After a call or full-screen app, wait", value: $preferences.quietGraceMinutes,
                    presets: [0, 1, 2, 5], label: { $0 == 0 ? "No wait" : Format.minutes($0) }
                )
            } header: {
                Text("Activity")
            } footer: {
                Text("Avo stays quiet while your camera or microphone is in use or a full-screen app is in front.")
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") { preferences.resetTimings() }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Shared

/// A pop-up menu of preset values. A stored value that is not a preset (from an older version) still shows.
private struct ValuePicker: View {
    let title: String
    @Binding var value: Int
    let presets: [Int]
    let label: (Int) -> String

    init(_ title: String, value: Binding<Int>, presets: [Int], label: @escaping (Int) -> String) {
        self.title = title
        _value = value
        self.presets = presets
        self.label = label
    }

    var body: some View {
        Picker(title, selection: $value) {
            ForEach(Format.options(presets, including: value), id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
    }
}

/// Plain-language value labels for Settings.
enum Format {
    static func minutes(_ value: Int) -> String {
        value == 1 ? "1 minute" : "\(value) minutes"
    }

    static func seconds(_ value: Int) -> String {
        if value < 60 { return value == 1 ? "1 second" : "\(value) seconds" }
        if value % 60 == 0 { return minutes(value / 60) }
        return "\(value / 60) min \(value % 60) sec"
    }

    static func ordinal(_ value: Int) -> String {
        let suffix = switch value % 100 {
        case 11, 12, 13: "th"
        default: switch value % 10 {
            case 1: "st"
            case 2: "nd"
            case 3: "rd"
            default: "th"
            }
        }
        return "\(value)\(suffix)"
    }

    /// The presets plus the current value, sorted, without duplicates.
    static func options(_ presets: [Int], including current: Int) -> [Int] {
        Array(Set(presets + [current])).sorted()
    }
}

private extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
