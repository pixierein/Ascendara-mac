import AppKit
import Observation
import SwiftUI

@Observable
private final class ThemeState {
    var Name = "purple"
}

enum Theme {
    private static let State = ThemeState()
    static var Name: String {
        get { State.Name }
        set { State.Name = newValue }
    }
    static var IsDark: Bool { ["dark", "midnight", "cyberpunk", "ocean", "forest", "sunset"].contains(Name) }
    private static let Palettes: [String: [Int]] = [
        "light": [0xFFFFFF, 0x0F172A, 0x3B82F6, 0xF1F5F9, 0x64748B, 0xE2E8F0, 0xFFFFFF, 0x0F172A],
        "dark": [0x0F172A, 0xF1F5F9, 0x3B82F6, 0x334155, 0x94A3B8, 0x334155, 0x1E293B, 0xF1F5F9],
        "blue": [0xDBEAFE, 0x1E3A8A, 0x2563EB, 0xBFDBFE, 0x1E3A8A, 0x93C5FD, 0xFFFFFF, 0x0F172A],
        "purple": [0xEDE9FE, 0x581C87, 0x7C3AED, 0xDDD6FE, 0x581C87, 0xA78BFA, 0xFFFFFF, 0x0F172A],
        "emerald": [0xD1FAE5, 0x064E3B, 0x10B981, 0xA7F3D0, 0x064E3B, 0x34D399, 0xFFFFFF, 0x0F172A],
        "rose": [0xFEE2E2, 0x9F1239, 0xE11D48, 0xFECDD3, 0x9F1239, 0xFB7185, 0xFFFFFF, 0x0F172A],
        "cyberpunk": [0x111827, 0xEC4899, 0xF472B6, 0x374151, 0xF9A8D4, 0x374151, 0x1F2937, 0xEC4899],
        "sunset": [0x1E293B, 0xFB923C, 0xF97316, 0x475569, 0xFDBA74, 0x475569, 0x334155, 0xFB923C],
        "forest": [0x141E1B, 0x22C55E, 0x16A34A, 0x28332D, 0x4ADE80, 0x28332D, 0x1E2923, 0x22C55E],
        "midnight": [0x020617, 0xC7D2FE, 0x818CF8, 0x334155, 0xA5B4FC, 0x334155, 0x1E293B, 0xC7D2FE],
        "amber": [0xFFFBEB, 0x78350F, 0xD97706, 0xFCE779, 0x78350F, 0xF59E0B, 0xFEF3C7, 0x78350F],
        "ocean": [0x0F172A, 0xA5F3FC, 0x22D3EE, 0x334155, 0x67E8F9, 0x334155, 0x1E293B, 0xA5F3FC],
    ]
    static func RGB(_ Red: Double, _ Green: Double, _ Blue: Double) -> Color {
        Color(red: Red / 255, green: Green / 255, blue: Blue / 255)
    }
    private static func ColorAt(_ Index: Int) -> Color {
        let Value = (Palettes[Name] ?? Palettes["purple"]!)[Index]
        return RGB(Double((Value >> 16) & 255), Double((Value >> 8) & 255), Double(Value & 255))
    }
    static var Background: Color { ColorAt(0) }
    static var Foreground: Color { ColorAt(1) }
    static var Accent: Color { ColorAt(2) }
    static var Muted: Color { ColorAt(3) }
    static var SecondaryText: Color { ColorAt(4) }
    static var Border: Color { ColorAt(5) }
    static var Card: Color { ColorAt(6) }
    static var CardForeground: Color { ColorAt(7) }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 11)
            .background(Theme.Accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 9))
            .ButtonFeedback(Pressed: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.Foreground).padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.Card.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.Border.opacity(0.8), lineWidth: 1))
            .ButtonFeedback(Pressed: configuration.isPressed)
    }
}

struct IconButton: View {
    let Symbol: String
    let Help: String
    let Action: () -> Void
    var body: some View {
        Button(action: Action) { Image(systemName: Symbol).font(.system(size: 14, weight: .medium)).frame(width: 34, height: 34) }
            .buttonStyle(MotionButtonStyle()).background(Theme.Muted.opacity(0.45), in: RoundedRectangle(cornerRadius: 8)).help(Help)
            .accessibilityLabel(Help)
    }
}

struct SectionHeading: View {
    let Title: String
    var Subtitle: String? = nil
    var Symbol: String? = nil
    var body: some View {
        HStack(spacing: 9) {
            if let Symbol { Image(systemName: Symbol).foregroundStyle(Theme.Accent) }
            VStack(alignment: .leading, spacing: 5) {
                Text(Title).font(.system(size: 22, weight: .bold))
                if let Subtitle { Text(Subtitle).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText) }
            }
            Spacer()
        }.foregroundStyle(Theme.Foreground)
    }
}

struct PageHeading: View {
    let Title: String
    let Subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(Title).font(.system(size: 30, weight: .bold))
            Text(Subtitle).font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Panel<ContentView: View>: View {
    var Padding: CGFloat = 22
    @ViewBuilder let Content: ContentView
    var body: some View {
        Content.padding(Padding).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Theme.CardForeground)
            .background(Theme.Card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.Border.opacity(0.65), lineWidth: 1))
    }
}

struct EmptyPanel: View {
    let Symbol: String
    let Title: String
    let Message: String
    var ActionTitle: String? = nil
    var Action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: Symbol).font(.system(size: 36, weight: .light)).foregroundStyle(Theme.Accent.opacity(0.65))
                .frame(width: 76, height: 76).background(Theme.Accent.opacity(0.08), in: Circle())
            Text(Title).font(.system(size: 19, weight: .semibold))
            Text(Message).font(.system(size: 13)).foregroundStyle(Theme.SecondaryText).multilineTextAlignment(.center).frame(maxWidth: 400)
            if let ActionTitle, let Action { Button(ActionTitle, action: Action).buttonStyle(PrimaryButtonStyle()).padding(.top, 4) }
        }.frame(maxWidth: .infinity).padding(.vertical, 55).padding(.horizontal, 24)
            .background(Theme.Card.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Border, style: StrokeStyle(lineWidth: 1, dash: [5])))
    }
}

struct Notice: View {
    let Message: String
    var Symbol = "info.circle"
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: Symbol)
            Text(Message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.foregroundStyle(Theme.SecondaryText).padding(13)
            .background(Theme.Muted.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct SearchField: View {
    @Binding var Text: String
    @FocusState private var Focused: Bool
    var Placeholder = "Search games…"
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Accent)
            TextField(Placeholder, text: $Text).textFieldStyle(.plain).font(.system(size: 14)).focused($Focused)
            if !Text.isEmpty { Button { Text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.SecondaryText) }.buttonStyle(MotionButtonStyle()).accessibilityLabel("Clear search") }
        }.padding(14).background(Theme.Card, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Focused ? Theme.Accent : Theme.Border, lineWidth: Focused ? 1.5 : 1))
            .MotionAnimation(Focused, Animation: AppMotion.Quick)
            .MotionAnimation(Text.isEmpty, Animation: AppMotion.Quick)
    }
}

struct GameArtwork: View {
    @Environment(\.MotionEnabled) private var MotionEnabled
    let URL: URL?
    let Name: String
    var CornerRadius: CGFloat = 12
    private var Tint: Color {
        let Colors: [Color] = [.purple, .blue, .teal, .orange, .pink, .indigo]
        return Colors[Name.utf8.reduce(0) { ($0 + Int($1)) % Colors.count }]
    }
    var body: some View {
        GeometryReader { Geometry in
            Group {
                if let URL, URL.isFileURL, let LocalImage = NSImage(contentsOf: URL) {
                    Image(nsImage: LocalImage).resizable().scaledToFill()
                } else {
                    AsyncImage(url: URL, transaction: Transaction(animation: MotionEnabled ? AppMotion.Standard : nil)) { Phase in
                        if let Image = Phase.image {
                            Image.resizable().scaledToFill().transition(.opacity)
                        } else {
                            ZStack {
                                LinearGradient(colors: [Tint, Tint.opacity(0.3), Theme.Background], startPoint: .topLeading, endPoint: .bottomTrailing)
                                Image(systemName: "gamecontroller.fill").font(.system(size: 42, weight: .light)).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                }
            }.frame(width: Geometry.size.width, height: Geometry.size.height).clipped()
        }.clipShape(RoundedRectangle(cornerRadius: CornerRadius))
    }
}

struct GameBadge: View {
    let Text: String
    var Symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let Symbol { Image(systemName: Symbol) }
            SwiftUI.Text(Text)
        }.font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.Muted.opacity(0.65), in: Capsule())
    }
}

struct GameCard: View {
    @EnvironmentObject var Store: AppStore
    let Game: Game
    var Width: CGFloat? = nil
    @State private var Hovering = false
    var body: some View {
        Button { Store.OpenGame(Game) } label: {
            VStack(alignment: .leading, spacing: 0) {
                GameArtwork(URL: Game.ArtworkURL, Name: Game.Name).aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if Store.Wishlist.contains(Game.Id) { Image(systemName: "bookmark.fill").foregroundStyle(.white).padding(8).background(Theme.Accent, in: Circle()).padding(9) }
                    }
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 5) {
                            if Game.Online { GameBadge(Text: "Online", Symbol: "globe") }
                            if Game.Dlc { GameBadge(Text: "DLC", Symbol: "gift") }
                        }.padding(9)
                    }
                VStack(alignment: .leading, spacing: 7) {
                    Text(Game.Name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    HStack {
                        Text(Game.Categories.prefix(2).joined(separator: " · ")).lineLimit(1)
                        Spacer(minLength: 4)
                        if let Size = Game.Size { Text(Size).lineLimit(1) }
                    }.font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                }.padding(12)
            }.foregroundStyle(Theme.CardForeground).background(Theme.Card, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Hovering ? Theme.Accent.opacity(0.65) : Theme.Border.opacity(0.5), lineWidth: 1))
                .shadow(color: Theme.Accent.opacity(Hovering ? 0.12 : 0), radius: 12, y: 6)
        }.buttonStyle(MotionButtonStyle()).frame(width: Width).onHover { Hovering = $0 }
            .MotionAnimation(Hovering, Animation: AppMotion.Quick)
            .MotionAnimation(Store.Wishlist.contains(Game.Id), Animation: AppMotion.Spring)
            .contextMenu {
                Button("View game") { Store.OpenGame(Game) }
                Button(Store.Wishlist.contains(Game.Id) ? "Remove from Play Later" : "Add to Play Later") { Store.ToggleWishlist(Game) }
                if let Installed = Store.LibraryMatch(Game) { Button("Play") { Store.LaunchGame(Installed) } }
            }
    }
}

struct StatCard: View {
    let Title: String
    let Value: String
    let Symbol: String
    var body: some View {
        Panel(Padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text(Title).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText); Spacer(); Image(systemName: Symbol).foregroundStyle(Theme.Accent) }
                Text(Value).font(.system(size: 26, weight: .bold)).contentTransition(.numericText())
                    .MotionAnimation(Value)
            }
        }
    }
}

func FormatPlayTime(_ Seconds: Double) -> String {
    let Minutes = Int(max(0, Seconds) / 60)
    return Minutes < 60 ? "\(Minutes)m" : "\(Minutes / 60)h \(Minutes % 60)m"
}
