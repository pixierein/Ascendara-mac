import SwiftUI

private struct TVScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var TVScale: CGFloat {
        get { self[TVScaleKey.self] }
        set { self[TVScaleKey.self] = newValue }
    }
}

enum TVStyle {
    static let Background = Color(red: 0.025, green: 0.035, blue: 0.055)
    static let Panel = Color(red: 0.065, green: 0.085, blue: 0.12)
    static let Accent = Color(red: 0.15, green: 0.76, blue: 1)
    static let Text = Color.white
    static let Secondary = Color(red: 0.65, green: 0.70, blue: 0.78)
}

struct TVButtonStyle: ButtonStyle {
    var Prominent = false
    var Selected = false
    @Environment(\.TVScale) private var Scale
    @Environment(\.isEnabled) private var IsEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18 * Scale, weight: .semibold))
            .padding(.horizontal, 25 * Scale)
            .padding(.vertical, 17 * Scale)
            .foregroundStyle(Prominent ? TVStyle.Background : .white)
            .background(Prominent ? Color.white : Selected ? TVStyle.Accent.opacity(0.2) : Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8 * Scale))
            .overlay(RoundedRectangle(cornerRadius: 8 * Scale)
                .stroke(Selected ? TVStyle.Accent : Color.white.opacity(Prominent ? 0 : 0.18), lineWidth: Selected ? 3 * Scale : 1))
            .contentShape(RoundedRectangle(cornerRadius: 8 * Scale))
            .opacity(IsEnabled ? 1 : 0.35)
            .ButtonFeedback(Pressed: configuration.isPressed)
    }
}

struct TVPageHeading: View {
    let Title: String
    let Subtitle: String
    @Environment(\.TVScale) private var Scale

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * Scale) {
            Text(I18n.T(Title)).font(.system(size: 44 * Scale, weight: .bold)).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            if !Subtitle.isEmpty {
                Text(I18n.T(Subtitle)).font(.system(size: 19 * Scale)).foregroundStyle(TVStyle.Secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TVPanel<ContentView: View>: View {
    @Environment(\.TVScale) private var Scale
    @ViewBuilder let Content: ContentView

    var body: some View {
        Content.padding(28 * Scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 12 * Scale))
            .overlay(RoundedRectangle(cornerRadius: 12 * Scale).stroke(.white.opacity(0.08)))
    }
}

struct TVEmptyState: View {
    let Symbol: String
    let Title: String
    let Message: String
    @Environment(\.TVScale) private var Scale

    var body: some View {
        VStack(spacing: 20 * Scale) {
            Image(systemName: Symbol).font(.system(size: 56 * Scale, weight: .light)).foregroundStyle(TVStyle.Accent)
            Text(I18n.T(Title)).font(.system(size: 30 * Scale, weight: .semibold)).foregroundStyle(.white)
            Text(I18n.T(Message)).font(.system(size: 20 * Scale)).foregroundStyle(TVStyle.Secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 650 * Scale)
        }.frame(maxWidth: .infinity).padding(.vertical, 65 * Scale).padding(.horizontal, 32 * Scale)
    }
}

struct TVGameTile: View {
    let Name: String
    var Subtitle = ""
    let Artwork: URL?
    let Width: CGFloat
    let Action: () -> Void
    @Environment(\.TVScale) private var Scale
    @Environment(\.MotionEnabled) private var MotionEnabled
    @State private var Hovering = false

    var body: some View {
        Button(action: Action) {
            VStack(alignment: .leading, spacing: 13 * Scale) {
                GameArtwork(URL: Artwork, Name: Name, CornerRadius: 8 * Scale)
                    .frame(width: Width, height: Width * 9 / 16)
                    .overlay(RoundedRectangle(cornerRadius: 8 * Scale)
                        .stroke(Hovering ? TVStyle.Accent : .white.opacity(0.12), lineWidth: Hovering ? 3 * Scale : 1))
                Text(Name).font(.system(size: 19 * Scale, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !Subtitle.isEmpty {
                    Text(I18n.T(Subtitle)).font(.system(size: 15 * Scale)).foregroundStyle(TVStyle.Secondary).lineLimit(1)
                }
            }.frame(width: Width, alignment: .topLeading)
                .scaleEffect(MotionEnabled && Hovering ? 1.025 : 1)
        }.buttonStyle(MotionButtonStyle())
            .accessibilityLabel(Name)
            .onHover { Hovering = $0 }
            .MotionAnimation(Hovering, Animation: AppMotion.Quick)
    }
}

struct TVBackdrop: View {
    let URL: URL?
    let Name: String

    var body: some View {
        GeometryReader { Geometry in
            ZStack(alignment: .trailing) {
                TVStyle.Background
                if URL != nil {
                    GameArtwork(URL: URL, Name: Name, CornerRadius: 0)
                        .frame(width: Geometry.size.width * 0.88, height: Geometry.size.height)
                        .opacity(0.9)
                } else {
                    RadialGradient(colors: [TVStyle.Accent.opacity(0.2), Color.indigo.opacity(0.13), TVStyle.Background],
                                   center: .topTrailing, startRadius: 0, endRadius: Geometry.size.width)
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: Geometry.size.height * 0.55, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.035)).padding(.trailing, Geometry.size.width * 0.08)
                }
                LinearGradient(stops: [
                    .init(color: TVStyle.Background, location: 0),
                    .init(color: TVStyle.Background.opacity(0.92), location: 0.22),
                    .init(color: TVStyle.Background.opacity(0.65), location: 0.43),
                    .init(color: TVStyle.Background.opacity(0.12), location: 0.74),
                    .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [
                    .init(color: TVStyle.Background.opacity(0.25), location: 0),
                    .init(color: .clear, location: 0.35),
                    .init(color: TVStyle.Background.opacity(0.55), location: 0.72),
                    .init(color: TVStyle.Background, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }.frame(width: Geometry.size.width, height: Geometry.size.height).clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct TVIntegrationFieldStyle: ViewModifier {
    @Environment(\.TVScale) private var Scale

    func body(content Content: Content) -> some View {
        Content
            .textFieldStyle(.plain)
            .font(.system(size: 21 * Scale))
            .padding(.horizontal, 20 * Scale)
            .padding(.vertical, 18 * Scale)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12 * Scale))
            .overlay(RoundedRectangle(cornerRadius: 12 * Scale).stroke(.white.opacity(0.15)))
    }
}

struct TVIntegrationTabs: View {
    @Environment(\.TVScale) private var Scale
    let Titles: [String]
    @Binding var Selection: String

    var body: some View {
        HStack(spacing: 14 * Scale) {
            ForEach(Titles, id: \.self) { Title in
                Button(I18n.T(Title)) { Selection = Title }
                    .buttonStyle(TVButtonStyle(Selected: Selection == Title))
            }
            Spacer(minLength: 0)
        }
    }
}
