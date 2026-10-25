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
            CommandGroup(replacing: .appInfo) {
                Button(I18n.T("About Ascendara")) {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Ascendara for macOS",
                        .applicationVersion: AppVersion.Current,
                        .credits: NSAttributedString(string: I18n.T("An unofficial native macOS port of Ascendara.") + "\n" + I18n.T("Based on the original Ascendara project by tagoWorks."))
                    ])
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button(I18n.T("Preferences…")) { Store.SelectedGame = nil; Store.Route = .Settings }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button(I18n.T("Add Game…")) { Store.ImportGame() }.keyboardShortcut("o")
                Button(I18n.T("Import Catalogue…")) { Store.ImportCatalog() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Navigate") {
                ForEach(Array([AppRoute.Home, .Search, .Library, .Downloads, .Profile, .Ascend, .Settings].enumerated()), id: \.element) { Index, Route in
                    Button(Route.Title) { Store.SelectedGame = nil; Store.Route = Route }
                        .keyboardShortcut(KeyEquivalent(Character(String(Index + 1))))
                }
                Divider()
                Button(I18n.T("Search Games")) { Store.SelectedGame = nil; Store.Route = .Search }.keyboardShortcut("k")
                Button(I18n.T("Wishlist")) { Store.SelectedGame = nil; Store.Route = .Wishlist }.keyboardShortcut("w", modifiers: [.command, .shift])
                Button(I18n.T("Big Picture")) { Store.ShowingBigPicture = true }.keyboardShortcut("b", modifiers: [.command, .shift]).disabled(Store.ShowingWelcome)
            }
            CommandGroup(after: .toolbar) {
                Button(I18n.T("Refresh Catalogue")) { Store.RefreshCatalog() }.keyboardShortcut("r")
            }
            CommandGroup(replacing: .help) {
                Button(I18n.T("Ascendara Documentation")) { Store.OpenExternal("https://ascendara.app/docs") }
                Button(I18n.T("View Source")) { Store.OpenExternal("https://github.com/pixierein/Ascendara-mac") }
                Button(I18n.T("Show App Data")) { NSWorkspace.shared.open(AppPaths.Support) }
            }
        }
    }
}

@MainActor
final class AscendaraDelegate: NSObject, NSApplicationDelegate {
    weak var Store: AppStore?
    private var IsTerminating = false
    func applicationDidFinishLaunching(_ Notification: Notification) {
        CrashReporterBridge.Install()
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

enum AppResources {
    static let Icon: NSImage? = {
        if let URL = Foundation.Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let Image = NSImage(contentsOf: URL) {
            return Image
        }
        guard let URL = Bundle.url(forResource: "AppIcon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: URL)
    }()

    static let Bundle: Foundation.Bundle = {
        if let URL = Foundation.Bundle.main.resourceURL?.appendingPathComponent("AscendaraMac_Ascendara.bundle"),
           let Packaged = Foundation.Bundle(url: URL) {
            return Packaged
        }
        return Foundation.Bundle.module
    }()
}
