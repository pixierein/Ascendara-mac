import AppKit
import SwiftUI

struct BigPictureView: View {
    @EnvironmentObject private var Store: AppStore
    @EnvironmentObject private var Window: WindowController
    @Environment(\.MotionEnabled) private var MotionEnabled
    @StateObject private var Input = BigPictureInput()
    @StateObject private var Focus = BigPictureFocus()
    @State private var NavigationFocused = false
    @State private var NavigationIndex = 0

    private let Routes: [AppRoute] = [.Home, .Search, .Library, .Wishlist, .Downloads, .Retro, .Profile, .Ascend, .TorBox, .Workshop, .Settings, .Sources, .Tools]
    private let RailRoutes: [AppRoute] = [.Home, .Search, .Library, .Wishlist, .Downloads, .Retro]

    var body: some View {
        GeometryReader { Geometry in
            let Scale = max(0.72, min(Geometry.size.width / 1280, Geometry.size.height / 800))
            ZStack(alignment: .leading) {
                TVStyle.Background.ignoresSafeArea()
                HStack(spacing: 0) {
                    Rail(Scale: Scale).frame(width: 92 * Scale)
                        .accessibilityHidden(NavigationFocused)
                        .allowsHitTesting(!NavigationFocused)
                    Page(Scale: Scale)
                        .padding(.bottom, 42 * Scale)
                        .disabled(NavigationFocused)
                        .accessibilityHidden(NavigationFocused)
                        .overlay(alignment: .bottomTrailing) {
                            Hints(Scale: Scale).padding(.horizontal, 42 * Scale).padding(.bottom, 15 * Scale)
                        }
                }
                if NavigationFocused {
                    Color.black.opacity(0.6).ignoresSafeArea()
                        .onTapGesture { EnterContent() }.accessibilityHidden(true)
                    Navigation(Scale: Scale)
                        .frame(width: 310 * Scale)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .environment(\.TVScale, Scale)
            .MotionAnimation(NavigationFocused, Animation: AppMotion.Quick)
        }
        .environment(\.BigPictureActive, true)
        .foregroundStyle(TVStyle.Text)
        .tint(TVStyle.Accent)
        .preferredColorScheme(.dark)
        .onAppear {
            Theme.BigPictureActive = true
            NavigationIndex = Routes.firstIndex(of: Store.Route) ?? 0
            StartInput()
        }
        .onChange(of: Window.Window?.windowNumber) { _, _ in StartInput() }
        .onChange(of: Store.Route) { _, Route in
            NavigationIndex = Routes.firstIndex(of: Route) ?? 0
            Store.SelectedGame = nil
            Focus.Reset()
        }
        .onChange(of: Store.SelectedGame) { _, Game in
            if Game != nil { NavigationFocused = false }
            Focus.Reset()
        }
        .onDisappear {
            Input.Stop()
            Focus.Reset()
            Theme.BigPictureActive = false
            Window.EndBigPicture()
        }
    }

    private func Rail(Scale: CGFloat) -> some View {
        VStack(spacing: 12 * Scale) {
            Button { ShowNavigation() } label: {
                if let Icon = AppResources.Icon {
                    Image(nsImage: Icon).resizable().scaledToFit().frame(width: 32 * Scale, height: 32 * Scale)
                } else {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 28 * Scale))
                }
            }.buttonStyle(MotionButtonStyle()).accessibilityLabel(I18n.T("Ascendara menu"))
                .padding(.top, 30 * Scale).padding(.bottom, 12 * Scale)
            Spacer(minLength: 12 * Scale)
            ForEach(RailRoutes) { Route in
                RailButton(Symbol: Route.Icon, Title: Title(Route), Active: Store.Route == Route, Scale: Scale) { OpenRoute(Route) }
            }
            RailButton(Symbol: "ellipsis", Title: I18n.T("All sections"), Active: false, Scale: Scale, Action: ShowNavigation)
            Spacer(minLength: 12 * Scale)
            RailButton(Symbol: "person.crop.circle", Title: I18n.T("Profile"), Active: Store.Route == .Profile, Scale: Scale) { OpenRoute(.Profile) }
            RailButton(Symbol: "gearshape", Title: I18n.T("Preferences"), Active: Store.Route == .Settings, Scale: Scale) { OpenRoute(.Settings) }
            RailButton(Symbol: "rectangle.portrait.and.arrow.right", Title: I18n.T("Exit Big Picture"), Active: false, Scale: Scale, Action: Exit)
                .padding(.bottom, 28 * Scale)
        }
        .frame(maxHeight: .infinity)
        .background(LinearGradient(colors: [Color.black.opacity(0.7), TVStyle.Background], startPoint: .leading, endPoint: .trailing))
    }

    private func RailButton(Symbol: String, Title: String, Active: Bool, Scale: CGFloat, Action: @escaping () -> Void) -> some View {
        Button(action: Action) {
            Image(systemName: Symbol).font(.system(size: 23 * Scale, weight: Active ? .semibold : .regular))
                .foregroundStyle(Active ? Color.white : TVStyle.Secondary.opacity(0.8))
                .frame(width: 58 * Scale, height: 46 * Scale)
                .background(Active ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8 * Scale))
                .overlay(alignment: .leading) {
                    if Active { Capsule().fill(TVStyle.Accent).frame(width: 3 * Scale, height: 22 * Scale).offset(x: -10 * Scale) }
                }
        }.buttonStyle(MotionButtonStyle()).help(Title).accessibilityLabel(Title)
            .accessibilityAddTraits(Active ? .isSelected : [])
    }

    private func Navigation(Scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24 * Scale) {
            HStack(spacing: 14 * Scale) {
                if let Icon = AppResources.Icon {
                    Image(nsImage: Icon).resizable().scaledToFit().frame(width: 36 * Scale, height: 36 * Scale)
                }
                Text(I18n.T("Ascendara")).font(.system(size: 26 * Scale, weight: .bold))
            }.padding(.horizontal, 24 * Scale).padding(.top, 38 * Scale)
            ScrollViewReader { Reader in
                ScrollView {
                    VStack(spacing: 6 * Scale) {
                        ForEach(Array(Routes.enumerated()), id: \.element) { Index, Route in
                            MenuButton(Title: Title(Route), Symbol: Route.Icon, Index: Index, Scale: Scale) { OpenRoute(Route) }
                                .id(Index)
                        }
                        MenuButton(Title: I18n.T("Exit Big Picture"), Symbol: "rectangle.portrait.and.arrow.right", Index: Routes.count, Scale: Scale, Action: Exit)
                            .id(Routes.count).padding(.top, 18 * Scale)
                    }.padding(.horizontal, 16 * Scale).padding(.vertical, 8 * Scale)
                }.scrollIndicators(.hidden)
                    .task(id: NavigationIndex) {
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        withAnimation(MotionEnabled ? AppMotion.Quick : nil) { Reader.scrollTo(NavigationIndex, anchor: .center) }
                    }
            }
            Text(I18n.T("B / Esc to return")).font(.system(size: 15 * Scale)).foregroundStyle(TVStyle.Secondary)
                .padding(.horizontal, 28 * Scale).padding(.bottom, 30 * Scale)
        }
        .background(TVStyle.Background)
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
        .shadow(color: .black.opacity(0.55), radius: 35 * Scale, x: 18 * Scale)
    }

    private func MenuButton(Title: String, Symbol: String, Index: Int, Scale: CGFloat, Action: @escaping () -> Void) -> some View {
        let Selected = NavigationIndex == Index
        return Button(action: Action) {
            HStack(spacing: 18 * Scale) {
                Image(systemName: Symbol).frame(width: 25 * Scale)
                Text(I18n.T(Title)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 18 * Scale, weight: .semibold))
            .padding(.horizontal, 20 * Scale).frame(height: 56 * Scale)
            .foregroundStyle(Selected ? TVStyle.Background : .white)
            .background(Selected ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 7 * Scale))
            .overlay(RoundedRectangle(cornerRadius: 7 * Scale).stroke(Selected ? TVStyle.Accent : .clear, lineWidth: 3 * Scale))
        }.buttonStyle(MotionButtonStyle()).accessibilityLabel(Title)
    }

    private func Page(Scale: CGFloat) -> some View {
        GeometryReader { Geometry in
            ZStack(alignment: .topLeading) {
                PageContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .font(.system(size: 20 * Scale)).controlSize(.large)
                    .simultaneousGesture(TapGesture().onEnded { Focus.Reset() })
                if !NavigationFocused, let Frame = Focus.Frame {
                    RoundedRectangle(cornerRadius: 8 * Scale)
                        .stroke(.white.opacity(0.95), lineWidth: 5 * Scale)
                        .overlay(RoundedRectangle(cornerRadius: 8 * Scale).stroke(TVStyle.Accent, lineWidth: 3 * Scale))
                        .frame(width: max(0, Frame.width + 6 * Scale), height: max(0, Frame.height + 6 * Scale))
                        .position(x: Frame.midX, y: Frame.midY)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .background(BigPictureFocusArea(Controller: Focus))
            .clipped()
            .task(id: BigPicturePageFocus(Route: Store.Route, Game: Store.SelectedGame,
                                         NavigationFocused: NavigationFocused, Size: Geometry.size)) {
                await Task.yield()
                guard !Task.isCancelled else { return }
                Focus.Reset()
                if !NavigationFocused { _ = Focus.Handle(.Down) }
            }
        }
    }

    @ViewBuilder private var PageContent: some View {
        if let Game = Store.SelectedGame {
            TVGameDetailView(Game: Game).id(Game)
        } else {
            switch Store.Route {
            case .Home: TVHomeView()
            case .Search: TVSearchView()
            case .Library: TVLibraryView()
            case .Wishlist: TVSearchView(Wishlist: true)
            case .Downloads: TVDownloadsView()
            case .Profile: TVProfileView()
            case .Settings: TVSettingsView()
            case .Ascend: AscendView()
            case .TorBox: TorBoxView()
            case .Workshop: WorkshopView()
            case .Retro: RetroView()
            case .Sources: SourcesView()
            case .Tools: ToolsView()
            }
        }
    }

    private func Hints(Scale: CGFloat) -> some View {
        HStack(spacing: 22 * Scale) {
            Text(I18n.T("↑↓←→  Browse"))
            Text(I18n.T("A / Return  Select"))
            Text(I18n.T("B / Esc  Back"))
            Text(I18n.T("☰ / Tab  Menu"))
        }.font(.system(size: 12 * Scale, weight: .medium)).foregroundStyle(TVStyle.Secondary.opacity(0.75))
            .accessibilityHidden(true)
    }

    private func Title(_ Route: AppRoute) -> String { Route == .Wishlist ? "Play Later" : Route.Title }

    private func StartInput() {
        guard Window.Window != nil else { return }
        Window.BeginBigPicture()
        Input.Start(Window: Window.Window) { Handle($0) }
    }

    private func Handle(_ Action: BigPictureAction) -> Bool {
        if Focus.HasSheet { return Focus.Handle(Action) }
        switch Action {
        case .Menu: ToggleNavigation(); return true
        case .Back: Back(); return true
        case .PreviousPage: MovePage(-1); return true
        case .NextPage: MovePage(1); return true
        default: break
        }
        if NavigationFocused {
            switch Action {
            case .Up: NavigationIndex = max(0, NavigationIndex - 1)
            case .Down: NavigationIndex = min(Routes.count, NavigationIndex + 1)
            case .Right, .Activate:
                if NavigationIndex == Routes.count { Exit() } else { OpenRoute(Routes[NavigationIndex]) }
            case .Left: EnterContent()
            default: return false
            }
            return true
        }
        if Focus.Handle(Action) { return true }
        if Action == .Left { ShowNavigation(); return true }
        return false
    }

    private func OpenRoute(_ Route: AppRoute) {
        Store.SelectedGame = nil
        Store.Route = Route
        NavigationIndex = Routes.firstIndex(of: Route) ?? 0
        EnterContent()
    }

    private func MovePage(_ Offset: Int) {
        let Index = Routes.firstIndex(of: Store.Route) ?? 0
        OpenRoute(Routes[(Index + Offset + Routes.count) % Routes.count])
    }

    private func EnterContent() { NavigationFocused = false; Focus.Reset() }

    private func ShowNavigation() {
        NavigationIndex = Routes.firstIndex(of: Store.Route) ?? 0
        NavigationFocused = true
        Focus.Reset()
    }

    private func ToggleNavigation() { NavigationFocused ? EnterContent() : ShowNavigation() }

    private func Back() {
        if NavigationFocused { EnterContent() }
        else if Store.SelectedGame != nil { Store.SelectedGame = nil; Focus.Reset() }
        else { ShowNavigation() }
    }

    private func Exit() {
        Input.Stop()
        Focus.Reset()
        Store.ShowingBigPicture = false
    }
}

private struct BigPicturePageFocus: Equatable {
    let Route: AppRoute
    let Game: Game?
    let NavigationFocused: Bool
    let Size: CGSize
}
