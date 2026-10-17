import SwiftUI

/// White rounded card from the Flow design: 344 pt wide, 20 pt corners, soft two-layer shadow.
struct CardShell<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(14)
        .frame(width: 344, alignment: .leading)
        .background {
            // Shadow on the shape only, so the buttons inside don't get their own.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
                .shadow(color: Theme.ink.opacity(0.12), radius: 17, y: 14)
                .shadow(color: Theme.ink.opacity(0.06), radius: 1, y: 1)
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}

/// Avo on the light green tile, 84 × 112.
struct ArtTile: View {
    let pose: String
    let label: String

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.tile)
            .frame(width: 84, height: 112)
            .overlay {
                Image(pose)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 66, height: 92)
            }
            .accessibilityElement()
            .accessibilityLabel(label)
    }
}

struct CardHeader: View {
    let trailing: String

    var body: some View {
        HStack {
            Text("Coach Avo")
                .font(Theme.body(12, weight: .bold))
                .foregroundStyle(Theme.accentText)
            Spacer(minLength: 8)
            Text(trailing)
                .font(Theme.body(12))
                .foregroundStyle(Theme.mutedText)
                .monospacedDigit()
        }
    }
}

struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.display(19))
            .foregroundStyle(Theme.ink)
    }
}

struct CardBody: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.body(13))
            .foregroundStyle(Theme.bodyText)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Buttons

struct AvoButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13, weight: .bold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(kind == .primary ? Color.white : Theme.ink)
            .padding(.horizontal, kind == .primary ? 18 : 16)
            .frame(height: 40)
            .background(Capsule().fill(kind == .primary ? Theme.ink : Theme.cardButtonLight))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AvoLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(12, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(configuration.isPressed ? Theme.ink : Theme.bodyText)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == AvoButtonStyle {
    static var avoPrimary: AvoButtonStyle { AvoButtonStyle(kind: .primary) }
    static var avoSecondary: AvoButtonStyle { AvoButtonStyle(kind: .secondary) }
}

extension ButtonStyle where Self == AvoLinkButtonStyle {
    static var avoLink: AvoLinkButtonStyle { AvoLinkButtonStyle() }
}
