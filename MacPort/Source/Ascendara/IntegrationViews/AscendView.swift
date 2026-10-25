import SwiftUI

struct AscendView: View {
    private let OfficialLauncher = URL(string: "https://www.ascendara.app/thank-you")!

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "at")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Theme.Accent)
                    .frame(width: 80, height: 80)
                    .background(Theme.Accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))

                Text(I18n.T("Ascend is not available in this macOS port."))
                    .font(.system(size: 27, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(I18n.T("If you want to get Ascend, please use the official Electron launcher here:"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.SecondaryText)
                    .multilineTextAlignment(.center)

                Link(destination: OfficialLauncher) {
                    Label(I18n.T("Official Electron launcher"), systemImage: "arrow.up.right.square")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: 650)
            .padding(42)
            .frame(maxWidth: .infinity)
            .background(Theme.Card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Border.opacity(0.7)))
            .padding(32)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .padding(.top, 50)
        }
        .background(Theme.Background)
        .foregroundStyle(Theme.Foreground)
    }
}
