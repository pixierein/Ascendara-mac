import AppKit
import SwiftUI

@main
struct AscendaraApp: App {
    @NSApplicationDelegateAdaptor(AscendaraDelegate.self) private var Delegate
    @StateObject private var Store = AppStore()

    var body: some Scene {
        WindowGroup("Ascendara", id: "Main") {
            AppShell().environmentObject(Store)
                .modifier(MotionScope(ReduceMotion: Store.Settings.ReduceMotion))
                .frame(minWidth: 960, minHeight: 640)
                .tint(Theme.Accent)
                .preferredColorScheme(Theme.IsDark ? .dark : .light)
                .task { Delegate.Store = Store; Store.Start() }
                .onOpenURL { Store.HandleURL($0) }
        }
        .defaultSize(width: 1280, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences…") { Store.Route = .Settings }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Game…") { Store.ImportGame() }.keyboardShortcut("o")
                Button("Import Catalogue…") { Store.ImportCatalog() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Navigate") {
                ForEach(Array([AppRoute.Home, .Search, .Library, .Downloads, .Profile, .Ascend, .Settings].enumerated()), id: \.element) { Index, Route in
                    Button(Route.Title) { Store.Route = Route }
                        .keyboardShortcut(KeyEquivalent(Character(String(Index + 1))))
                }
                Divider()
                Button("Search Games") { Store.Route = .Search }.keyboardShortcut("k")
                Button("Wishlist") { Store.Route = .Wishlist }.keyboardShortcut("w", modifiers: [.command, .shift])
                Button("Big Picture") { Store.ShowingBigPicture = true }.keyboardShortcut("b", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh Catalogue") { Store.RefreshCatalog() }.keyboardShortcut("r")
            }
            CommandGroup(replacing: .help) {
                Button("Ascendara Documentation") { Store.OpenExternal("https://ascendara.app/docs") }
                Button("View Source") { Store.OpenExternal("https://github.com/pixierein/ascendara") }
                Button("Show App Data") { NSWorkspace.shared.open(AppPaths.Support) }
            }
        }
    }
}

@MainActor
final class AscendaraDelegate: NSObject, NSApplicationDelegate {
    weak var Store: AppStore?
    private var IsTerminating = false
    func applicationDidFinishLaunching(_ Notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let Icon = AppResources.Icon {
            NSApplication.shared.applicationIconImage = Icon
        }
    }
    func applicationShouldTerminate(_ Sender: NSApplication) -> NSApplication.TerminateReply {
        guard !IsTerminating, let Store else { return .terminateNow }
        IsTerminating = true
        Task {
            await Store.PrepareForExit()
            Sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ Sender: NSApplication) -> Bool { true }
}
