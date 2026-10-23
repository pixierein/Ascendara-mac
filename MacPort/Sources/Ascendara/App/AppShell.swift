import AppKit
import SwiftUI

struct AppShell: View {
    @EnvironmentObject private var Store: AppStore
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
                    Screen.id(Store.Route).MotionTransition()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .MotionAnimation(Store.Route)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 94) }
            .zIndex(1)
            Dock.padding(.bottom, 18).zIndex(2)
            if let Notice = Store.Notice {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Theme.Accent)
                        Text(Notice).font(.callout).textSelection(.enabled)
                        Button { Store.Notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(MotionButtonStyle())
                    }
                    .padding(14).background(Theme.Card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Border)).shadow(color: .black.opacity(0.1), radius: 15)
                    .padding(.top, 64).padding(.horizontal, 32)
                    Spacer()
                }.MotionTransition(Distance: -8).zIndex(3)
            }
        }
        .background(Theme.Background.ignoresSafeArea())
        .MotionAnimation(Store.Notice)
        .MotionAnimation(Store.Settings.Theme)
        .ignoresSafeArea(.container, edges: .top)
        .foregroundStyle(Theme.Foreground)
        .sheet(item: $Store.SelectedGame) { Game in
            GameDetailView(Game: Game).environmentObject(Store)
                .frame(minWidth: 880, idealWidth: 1020, minHeight: 650, idealHeight: 780)
        }
        .sheet(isPresented: $Store.ShowingWelcome) {
            WelcomeView().environmentObject(Store).interactiveDismissDisabled()
        }
        .sheet(isPresented: $Store.ShowingBigPicture) {
            BigPictureView().environmentObject(Store).frame(minWidth: 940, minHeight: 660)
        }
        .alert("Ascendara", isPresented: Binding(get: { Store.ErrorMessage != nil }, set: { if !$0 { Store.ErrorMessage = nil } })) {
            Button("OK") { Store.ErrorMessage = nil }
        } message: { Text(Store.ErrorMessage ?? "") }
        .onChange(of: Store.Settings.Theme) { _, _ in Store.SaveSettings() }
    }

    @ViewBuilder private var Screen: some View {
        switch Store.Route {
        case .Home: HomeView()
        case .Search: SearchView()
        case .Library: LibraryView()
        case .Downloads: DownloadsView()
        case .Wishlist: WishlistView()
        case .Profile: ProfileView()
        case .Settings: SettingsView()
        case .Sources: SourcesView()
        case .Tools: ToolsView()
        case .Ascend: AscendView()
        case .TorBox: TorBoxView()
        case .Workshop: WorkshopView()
        case .Retro: RetroView()
        }
    }

    private var Dock: some View {
        HStack(spacing: 8) {
            ForEach(DockRoutes) { Route in
                Button { Store.Route = Route } label: {
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

struct BigPictureView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.dismiss) private var Dismiss
    @State private var Selection = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Label("BIG PICTURE", systemImage: "gamecontroller").font(.title2.bold())
                Spacer()
                Text("← → Select · Return Play · Esc Close").foregroundStyle(.secondary)
                Button("Close") { Dismiss() }.keyboardShortcut(.escape, modifiers: [])
            }
            if Store.Library.isEmpty {
                ContentUnavailableView("Your library is empty", systemImage: "gamecontroller", description: Text("Add a game to start playing."))
            } else {
                let Game = Store.Library[min(Selection, Store.Library.count - 1)]
                HStack(spacing: 32) {
                    ZStack {
                        GameArtwork(URL: Game.ArtworkURL, Name: Game.Name, CornerRadius: 22)
                            .id(Game.Id).MotionTransition(Distance: 0)
                    }.frame(width: 430, height: 290)
                    ZStack(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(Game.Name).font(.system(size: 38, weight: .bold))
                            Text("\(Int(Game.PlayTimeSeconds / 3600)) hours played").foregroundStyle(.secondary)
                            Button(Store.IsRunning(Game) ? "Stop Game" : "Play Now") {
                                if Store.IsRunning(Game) { Store.StopGame(Game) } else { Store.LaunchGame(Game) }
                            }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.return, modifiers: [])
                        }.id(Game.Id).MotionTransition()
                    }
                    Spacer()
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(Array(Store.Library.enumerated()), id: \.element.Id) { Index, Entry in
                            Button { Selection = Index } label: {
                                Text(Entry.Name).lineLimit(2).frame(width: 160, height: 65).padding(12)
                                    .background(Selection == Index ? Theme.Accent.opacity(0.25) : Theme.Card, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Selection == Index ? Theme.Accent : .clear, lineWidth: 2))
                            }.buttonStyle(MotionButtonStyle())
                        }
                    }.padding(3)
                }
            }
            Spacer()
        }.padding(36).background(Theme.Background).foregroundStyle(Theme.Foreground)
            .MotionAnimation(Selection)
            .onMoveCommand { Direction in
                if Direction == .left { Selection = max(0, Selection - 1) }
                if Direction == .right { Selection = min(max(0, Store.Library.count - 1), Selection + 1) }
            }
    }
}
