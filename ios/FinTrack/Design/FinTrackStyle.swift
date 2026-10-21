import SwiftUI

enum FinTrackStyle {
    static let purple = Color(red: 0.43, green: 0.25, blue: 0.83)
    static let green = Color(red: 0.18, green: 0.65, blue: 0.35)
    static let ink = Color(red: 0.12, green: 0.14, blue: 0.23)
    static let border = Color(red: 0.90, green: 0.91, blue: 0.94)
    static let background = Color(red: 0.985, green: 0.985, blue: 0.995)
}

struct FinanceCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(FinTrackStyle.border))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(FinTrackStyle.purple, in: RoundedRectangle(cornerRadius: 13))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
