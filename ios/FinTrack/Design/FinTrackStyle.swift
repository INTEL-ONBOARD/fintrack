import SwiftUI

enum FinTrackStyle {
    static let black = Color(red: 0.035, green: 0.045, blue: 0.047)
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.09)
    static let muted = Color(red: 0.48, green: 0.49, blue: 0.49)
    static let green = Color(red: 0.22, green: 0.68, blue: 0.34)
    static let border = Color(red: 0.89, green: 0.89, blue: 0.89)
    static let background = Color.white
    static let soft = Color(red: 0.965, green: 0.965, blue: 0.965)
    static let pageInset: CGFloat = 22
    static let cardRadius: CGFloat = 24
}

struct FinanceCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: FinTrackStyle.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: FinTrackStyle.cardRadius).stroke(FinTrackStyle.border))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white)
            .background(FinTrackStyle.black, in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(FinTrackStyle.ink)
            .background(.white, in: Capsule())
            .overlay(Capsule().stroke(FinTrackStyle.border))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct DarkPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 42)
            .background(.white.opacity(configuration.isPressed ? 0.18 : 0.10), in: Capsule())
    }
}

struct BrandPageIntro: View {
    let title: String
    let subtitle: String
    let icon: String
    var showsTitle = true
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 30

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text("FINTRACK")
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.55))
                if showsTitle {
                    Text(title)
                        .font(.system(size: titleSize, design: .serif))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 8)
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(.white.opacity(0.3)))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FinTrackStyle.black, in: RoundedRectangle(cornerRadius: 26))
    }
}

extension View {
    func finTrackGroupedScreen() -> some View {
        self.scrollContentBackground(.hidden).background(FinTrackStyle.soft)
    }
}
