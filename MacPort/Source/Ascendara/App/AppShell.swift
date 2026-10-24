import AppKit
import Combine
import SwiftUI

struct AppShell: View {
    @EnvironmentObject private var Store: AppStore
    @StateObject private var Window = WindowController()
    @Namespace private var DockSelection
    private var DockRoutes: [AppRoute] {
        var Routes: [AppRoute] = [.Home, .Search, .Library, .Downloads]
        if !Store.Settings.TorBoxAPIKey.isEmpty { Routes.append(.TorBox) }
        Routes += [.Profile, .Ascend]
        if Store.Settings.ShowWorkshop { Routes.append(.Workshop) }
        Routes.append(.Settings)
        return Routes
    }
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                AppTitlebar().zIndex(1)
                ZStack {
                    if !Store.ShowingBigPicture {
                        if Store.ShowingWelcome { WelcomeView() }
                        else if let Game = Store.SelectedGame {
                            GameDetailView(Game: Game).id(Game.Id).MotionTransition()
                        }
                        else { AppScreen().id(Store.Route) }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .opacity(Store.ShowingBigPicture ? 0 : 1)
            .allowsHitTesting(!Store.ShowingBigPicture)
            .disabled(Store.ShowingBigPicture)
            .accessibilityHidden(Store.ShowingBigPicture)
            .zIndex(1)
            Dock.padding(.bottom, 18)
                .opacity(Store.ShowingBigPicture || Store.ShowingWelcome ? 0 : 1)
                .allowsHitTesting(!Store.ShowingBigPicture && !Store.ShowingWelcome)
                .disabled(Store.ShowingBigPicture)
                .accessibilityHidden(Store.ShowingBigPicture)
                .zIndex(2)
            if Store.ShowingBigPicture {
                BigPictureView().MotionTransition(Distance: 0).zIndex(3)
            }
            if let Notice = Store.Notice {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Theme.Accent)
                        Text(Notice).font(.system(size: Store.ShowingBigPicture ? 20 : 13)).textSelection(.enabled)
                        Button { Store.Notice = nil } label: {
                            Image(systemName: "xmark").frame(width: Store.ShowingBigPicture ? 40 : 20, height: Store.ShowingBigPicture ? 40 : 20)
                        }.buttonStyle(MotionButtonStyle()).accessibilityLabel("Dismiss notice")
                    }
                    .padding(14).background(Theme.Card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Border)).shadow(color: .black.opacity(0.1), radius: 15)
                    .padding(.top, Store.ShowingBigPicture ? 100 : Store.SelectedGame == nil ? 64 : 116)
                    .padding(.horizontal, Store.ShowingBigPicture ? 60 : 32)
                    Spacer()
                }.MotionTransition(Distance: -8).zIndex(4)
            }
        }
        .environmentObject(Window)
        .background(Theme.Background.ignoresSafeArea())
        .scrollIndicators(Store.Settings.ShowScrollBar ? .visible : .hidden)
        .MotionAnimation(Store.ShowingBigPicture)
        .MotionAnimation(Store.Notice)
        .MotionAnimation(Store.Settings.Theme)
        .ignoresSafeArea(.container, edges: .top)
        .foregroundStyle(Theme.Foreground)
        .alert("Ascendara", isPresented: Binding(get: { Store.ErrorMessage != nil }, set: { if !$0 { Store.ErrorMessage = nil } })) {
            Button("OK") { Store.ErrorMessage = nil }
        } message: { Text(Store.ErrorMessage ?? "") }
        .onChange(of: Store.ShowingWelcome) { _, Active in
            if Active && Store.ShowingBigPicture { Store.ShowingBigPicture = false }
        }
        .onChange(of: Store.Route) { _, _ in
            if !Store.ShowingBigPicture { Store.SelectedGame = nil }
        }
        .onChange(of: Window.IsBigPicture) { _, Active in
            if !Active { Store.ShowingBigPicture = false }
        }
        .onChange(of: Store.Settings.Theme) { _, _ in Store.SaveSettings() }
        .onReceive(Timer.publish(every: 3600, on: .main, in: .common).autoconnect()) { _ in
            if Store.Settings.AutoRefreshIndex && !Store.IsLoading { Store.RefreshCatalog(Force: false) }
        }
    }

    private var Dock: some View {
        HStack(spacing: 8) {
            ForEach(DockRoutes) { Route in
                Button { Store.SelectedGame = nil; Store.Route = Route } label: {
                    VStack(spacing: 0) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: Route.Icon).font(.system(size: 20, weight: Store.Route == Route ? .semibold : .regular))
                                .frame(width: 29, height: 24)
                            if Route == .Downloads && Store.ActiveDownloadCount > 0 {
                                Text(String(Store.ActiveDownloadCount)).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                    .contentTransition(.numericText())
                                    .padding(3).background(.orange, in: Circle()).offset(x: 8, y: -5)
                            }
                        }
                    }
                    .frame(width: 48, height: 48)
                    .foregroundStyle(Store.Route == Route ? .white : Theme.SecondaryText)
                    .background {
                        if Store.Route == Route {
                            RoundedRectangle(cornerRadius: 11).fill(DockColor(Route))
                                .matchedGeometryEffect(id: "DockSelection", in: DockSelection)
                        }
                    }
                }.buttonStyle(MotionButtonStyle()).help(Route.Title).accessibilityLabel(Route.Title)
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Border.opacity(0.7)))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 7)
        .scaleEffect(Store.Settings.DockScale, anchor: .bottom)
        .MotionAnimation(Store.Route, Animation: AppMotion.Spring)
        .MotionAnimation(Store.Settings.DockScale)
        .MotionAnimation(Store.ActiveDownloadCount)
        .MotionAnimation(DockRoutes)
    }
    private func DockColor(_ Route: AppRoute) -> Color {
        switch Route {
        case .Home: return .cyan
        case .Search: return .purple
        case .Library: return .green
        case .Downloads, .TorBox: return .orange
        case .Profile: return .pink
        case .Ascend: return .purple
        default: return Theme.Accent
        }
    }
}

struct AppScreen: View {
    @EnvironmentObject private var Store: AppStore

    var body: some View {
        switch Store.Route {
        case .Home: HomeView()
        case .Search: SearchView()
        case .Library: LibraryDashboardView()
        case .Downloads: DownloadsView()
        case .Wishlist: WishlistView()
        case .Profile: ProfileView()
        case .Settings: PreferencesDashboardView()
        case .Sources: SourcesView()
        case .Tools: ToolsView()
        case .Ascend: AscendView()
        case .TorBox: TorBoxView()
        case .Workshop: WorkshopView()
        case .Retro: LibraryDashboardView(InitialSection: "Retro")
        }
    }
}

struct AppTitlebar: View {
    @EnvironmentObject private var Store: AppStore
    @EnvironmentObject private var Window: WindowController

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
            if !Store.ShowingWelcome { Actions }
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
            Button { Store.SelectedGame = nil; Store.Route = .Search } label: {
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
