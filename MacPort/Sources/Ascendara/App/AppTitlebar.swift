import AppKit
import SwiftUI

struct AppTitlebar: View {
    @EnvironmentObject private var Store: AppStore
    @StateObject private var Window = WindowController()

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                WindowButton(Symbol: "xmark", Title: "Close window", IsClose: true) { Window.Close() }
                WindowButton(Symbol: "minus", Title: "Minimize window") { Window.Minimize() }
                    .disabled(Window.IsFullscreen)
                WindowButton(Symbol: Window.IsZoomed ? "square.on.square" : "square",
                             Title: Window.IsZoomed ? "Restore window" : "Maximize window") { Window.ToggleZoom() }
                    .disabled(Window.IsFullscreen)
                WindowButton(Symbol: Window.IsFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                             Title: Window.IsFullscreen ? "Exit full screen" : "Enter full screen") { Window.ToggleFullscreen() }
            }
            Spacer(minLength: 0)
            Actions
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .overlay {
            HStack(spacing: 9) {
                if let Icon = AppResources.Icon {
                    Image(nsImage: Icon).resizable().scaledToFit().frame(width: 27, height: 27)
                        .accessibilityHidden(true)
                }
                Text("Ascendara").font(.system(size: 15, weight: .bold))
            }
            .allowsHitTesting(false)
        }
        .background(WindowDragArea(Controller: Window))
        .background(Theme.Background)
        .overlay(alignment: .bottom) { Theme.Border.opacity(0.35).frame(height: 1).allowsHitTesting(false) }
        .foregroundStyle(Theme.Foreground)
    }

    private var Actions: some View {
        HStack(spacing: 12) {
            if Store.IsLoading {
                ProgressView().controlSize(.small).help("Refreshing catalogue")
            } else {
                Circle().fill(Store.CatalogWarning == nil ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                    .help(Store.CatalogWarning ?? "Catalogue ready")
            }
            Button { Store.Route = .Search } label: {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                    Text("Search anything")
                    Text("⌘K").foregroundStyle(Theme.SecondaryText)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12).frame(height: 30)
                .background(Theme.Card.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(MotionButtonStyle()).accessibilityLabel("Search games")
            Button { Store.ShowingBigPicture = true } label: {
                Image(systemName: "gamecontroller").font(.system(size: 15)).frame(width: 30, height: 30)
            }.buttonStyle(MotionButtonStyle()).help("Big Picture").accessibilityLabel("Big Picture")
        }
    }
}

private struct WindowButton: View {
    let Symbol: String
    let Title: String
    var IsClose = false
    let Action: () -> Void
    @Environment(\.isEnabled) private var IsEnabled
    @State private var IsHovered = false

    var body: some View {
        Button(action: Action) {
            Image(systemName: Symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(MotionButtonStyle())
        .foregroundStyle(IsClose && IsHovered ? Color.white : Theme.Foreground)
        .background(IsHovered ? (IsClose ? Color.red : Theme.Muted) : Theme.Card.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: 7))
        .opacity(IsEnabled ? 1 : 0.35)
        .onHover { IsHovered = $0 }
        .MotionAnimation(IsHovered, Animation: AppMotion.Quick)
        .help(Title)
        .accessibilityLabel(Title)
    }
}
