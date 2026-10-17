import AppKit
import Testing
@testable import Avo

/// The character art lives in Assets.xcassets (Poses/ and Faces/, no namespace),
/// and the app loads it by exact name, e.g. `Image("avo-chinTuck")`.
struct ArtTests {
    nonisolated static let poseNames: [String] =
        ExerciseID.allCases.map { "avo-\($0.rawValue)" }
        + ["avo-wave", "avo-cheer", "avo-snooze", "avo-idle"]

    nonisolated static let faceNames = ["calm", "focus", "grin", "happy", "proud", "sleepy", "wink"]
        .map { "avo-face-\($0)" }

    @Test(arguments: poseNames + faceNames)
    func `art loads from the app bundle`(name: String) throws {
        let image = try #require(NSImage(named: name), "missing asset \(name)")
        // Every piece of art shares the 200x280 viewBox, exported at 2x (400x560).
        #expect(image.size == NSSize(width: 400, height: 560))
    }

    @Test func `every exercise has a pose`() {
        #expect(Self.poseNames.count == ExerciseID.allCases.count + 4)
    }

    @Test func `app icon is in the bundle`() {
        #expect(NSImage(named: NSImage.applicationIconName) != nil)
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String == "AppIcon")
    }
}
