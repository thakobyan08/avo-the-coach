import AppKit
import SwiftUI
import Testing
@testable import Avo

/// Renders every nudge state to PNG for a visual check of the card design.
/// Off by default. Run with `TEST_RUNNER_AVO_SNAPSHOTS=1 xcodebuild … test`; images land in build/snapshots/.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AVO_SNAPSHOTS"] == "1"))
struct CardSnapshotTests {
    private let chinTuck = Exercise[.chinTuck]
    private let outputDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "build/snapshots")

    @Test func `render all states`() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let dose = chinTuck.defaultDose

        try render("1-shows-up", ShowsUpCard(
            exercise: chinTuck, dose: dose, todayCount: 2, showHowTo: .constant(false),
            onStart: {}, onLater: {}, onHowTo: {}
        ))
        try render("1b-how-to", ShowsUpCard(
            exercise: chinTuck, dose: dose, todayCount: 2, showHowTo: .constant(true),
            onStart: {}, onLater: {}, onHowTo: {}
        ))
        try render("2-in-progress", InProgressCard(
            exercise: chinTuck, dose: dose, secondsPerRep: 3,
            started: .now.addingTimeInterval(-9.5), onDone: {}, onStop: {}
        ))
        try render("3-done", DoneCard(exercise: chinTuck, todayCount: 3, goal: 6))
        try render("4-snoozed", SnoozedCard(minutes: 10, backAt: .now.addingTimeInterval(600), onNow: {}))
        try render("5-pill", NudgePill(exercise: chinTuck, isHovering: false, onStart: {}, onDismiss: {}), pill: true)
        try render("5b-pill-hover", NudgePill(exercise: chinTuck, isHovering: true, onStart: {}, onDismiss: {}), pill: true)
        for exercise in Exercise.all {
            try render("move-\(exercise.id.rawValue)", HowToSection(exercise: exercise, dose: exercise.defaultDose)
                .padding(14).frame(width: 344).background(.white))
        }
    }

    private func render(_ name: String, _ view: some View, pill: Bool = false) throws {
        let content = view
            .padding(pill ? NudgeContent.pillInsets : NudgeContent.cardInsets)
            .background(Color(hex: 0xF3F5F8))
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: outputDirectory.appending(path: "\(name).png"))
    }
}
