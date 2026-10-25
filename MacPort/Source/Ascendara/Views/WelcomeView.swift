import AppKit
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var Store: AppStore
    @State private var Step = 0
    @State private var AgreedToTerms = false
    @State private var AgreedToPrivacy = false
    @State private var ThemeGroup = "Light"
    @State private var ShowingImport = false
    @State private var TourStep = 0
    @State private var CompatibilityBusy = false
    @AppStorage("WelcomeDiscoverySource") private var DiscoverySource = ""

    private let Sources = ["A Friend", "TikTok", "Reddit", "Instagram", "Google Search", "Discord", "FMHY", "Other", "Rather Not Say"]
    private let LightThemes = ["light", "blue", "purple", "emerald", "rose", "amber"]
    private let DarkThemes = ["dark", "midnight", "cyberpunk", "ocean", "forest", "sunset"]

    var body: some View {
        GeometryReader { Geometry in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 28)
                        Content
                        Spacer(minLength: 28)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, Geometry.size.height - 70))
                    .padding(.horizontal, 32)
                }.scrollIndicators(.hidden)
                Footer
            }
            .background(Theme.Background.ignoresSafeArea())
            .foregroundStyle(Theme.Foreground)
            .MotionAnimation(Step)
        }
    }

    @ViewBuilder private var Content: some View {
        switch Step {
        case 0: LanguagePage
        case 1: WelcomePage
        case 2: FreePage
        case 3: DiscoveryPage
        case 4: FolderPage
        case 5: CompatibilityPage
        case 6: ThemePage
        case 7: ExtrasPage
        case 8: SummaryPage
        default: TourPage
        }
    }

    private var LanguagePage: some View {
        VStack(spacing: 30) {
            Heading("Choose your language", Subtitle: I18n.T("English is available for this Mac version."), Symbol: "globe")
            Button {} label: {
                HStack(spacing: 16) {
                    Text(I18n.T("🇺🇸")).font(.system(size: 28))
                    Text(I18n.T("English")).font(.system(size: 24, weight: .semibold))
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Accent)
                }
                .padding(26).frame(maxWidth: 470)
                .background(Theme.Card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Accent, lineWidth: 2))
            }.buttonStyle(MotionButtonStyle()).accessibilityLabel(I18n.T("English, selected"))
            Button(I18n.T("Next")) { Step += 1 }.buttonStyle(PrimaryButtonStyle())
        }.frame(maxWidth: 900)
    }

    private var WelcomePage: some View {
        VStack(spacing: 30) {
            Heading("Welcome to Ascendara", Subtitle: I18n.T("Set up the basics, then start exploring games on your Mac."), Symbol: "gamecontroller.fill")
            Text(I18n.T("Please review the Terms of Service and Privacy Policy before continuing."))
                .font(.system(size: 19)).foregroundStyle(Theme.SecondaryText)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 18) {
                AgreementRow(Value: $AgreedToTerms, Title: I18n.T("I agree to Ascendara's Terms of Service"), Link: "Read Terms", URL: "https://www.ascendara.app/terms")
                AgreementRow(Value: $AgreedToPrivacy, Title: I18n.T("I agree to Ascendara's Privacy Policy"), Link: "Read Privacy Policy", URL: "https://www.ascendara.app/privacy")
            }.padding(26).frame(maxWidth: 700)
                .background(Theme.Card, in: RoundedRectangle(cornerRadius: 16))
            Button(I18n.T("Get Started")) { Step += 1 }.buttonStyle(PrimaryButtonStyle())
                .disabled(!AgreedToTerms || !AgreedToPrivacy)
        }.frame(maxWidth: 900)
    }

    private var FreePage: some View {
        VStack(spacing: 26) {
            Heading("Free to use. No catch.", Subtitle: I18n.T("Here's what you can do on your Mac."), Symbol: "sparkles")
            HStack(alignment: .top, spacing: 14) {
                FeatureCard("Download and play", "Browse the game catalogue and manage supported downloads. No account is required.", "arrow.down.circle")
                FeatureCard("Play together", "Look for games marked Online. Each player needs their own game copy.", "person.2")
                FeatureCard("Your privacy", "Your local library and preferences stay on this Mac.", "shield")
            }.frame(maxWidth: 980)
            ContinueButton
        }.frame(maxWidth: 1030)
    }

    private var DiscoveryPage: some View {
        VStack(spacing: 25) {
            Heading("How did you find Ascendara?", Subtitle: I18n.T("This question is optional. Your choice stays on this Mac."), Symbol: "person.2")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(Sources, id: \.self) { Source in
                    Button(Source) { DiscoverySource = Source; Step += 1 }
                        .buttonStyle(WelcomeChoiceStyle(Selected: DiscoverySource == Source))
                }
            }.frame(maxWidth: 840)
            Button(I18n.T("Skip →")) { Step += 1 }.buttonStyle(.plain).foregroundStyle(Theme.Accent)
                .font(.system(size: 18, weight: .semibold))
        }.frame(maxWidth: 900)
    }

    private var FolderPage: some View {
        VStack(spacing: 28) {
            Heading("Where should your games go?", Subtitle: I18n.T("Pick a folder on a drive with room for your downloads."), Symbol: "folder.badge.plus")
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Text(Store.Settings.DownloadDirectory).font(.system(size: 17, design: .monospaced))
                        .lineLimit(2).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button(I18n.T("Browse")) { Store.ChooseDownloadDirectory() }.buttonStyle(PrimaryButtonStyle())
                }
                if let FreeSpace = FreeSpaceGB, FreeSpace < 40 {
                    Label(I18n.Interpolated("Only \(Int(FreeSpace)) GB free on this drive. Many games need 40 GB or more."), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 15)).foregroundStyle(.orange)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                }
                Divider()
                Label(I18n.T("Downloaded games are stored in this folder."), systemImage: "shippingbox")
                Label(I18n.T("You can change the folder later in Preferences."), systemImage: "plus.circle")
            }.padding(24).frame(maxWidth: 820)
                .background(Theme.Card, in: RoundedRectangle(cornerRadius: 16))
            ContinueButton
        }.frame(maxWidth: 900)
    }

    private var CompatibilityPage: some View {
        VStack(spacing: 28) {
            Heading("Compatibility Layer", Subtitle: I18n.T("Windows games on your Mac need a compatible runtime."), Symbol: "desktopcomputer")
            WelcomeCompatibilityView(OnBusyChanged: { CompatibilityBusy = $0 })
            ContinueButton.disabled(CompatibilityBusy)
        }.frame(maxWidth: 900)
    }

    private var FreeSpaceGB: Double? {
        var Folder = URL(fileURLWithPath: Store.Settings.DownloadDirectory, isDirectory: true)
        while !FileManager.default.fileExists(atPath: Folder.path) {
            let Parent = Folder.deletingLastPathComponent()
            if Parent == Folder { return nil }
            Folder = Parent
        }
        guard let Values = try? FileManager.default.attributesOfFileSystem(forPath: Folder.path),
              let Bytes = Values[.systemFreeSize] as? NSNumber else { return nil }
        return Bytes.doubleValue / 1_073_741_824
    }

    private var ThemePage: some View {
        VStack(spacing: 22) {
            Heading("Make it yours", Subtitle: I18n.T("Pick a look. You can change it anytime in Preferences."), Symbol: "paintpalette")
            HStack(spacing: 6) {
                ForEach(["Light", "Dark"], id: \.self) { Group in
                    Button(Group + " Themes") { ThemeGroup = Group }
                        .buttonStyle(WelcomeChoiceStyle(Selected: ThemeGroup == Group))
                }
            }.frame(maxWidth: 360)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(ThemeGroup == "Light" ? LightThemes : DarkThemes, id: \.self) { Name in
                    Button { Store.Settings.Theme = Name } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(ThemeColor(Name))
                                .frame(height: 75)
                                .overlay(alignment: .topLeading) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Capsule().fill(.white.opacity(0.8)).frame(width: 85, height: 7)
                                        Capsule().fill(.white.opacity(0.5)).frame(width: 55, height: 6)
                                    }.padding(14)
                                }
                            HStack {
                                Text(Name.capitalized).font(.system(size: 16, weight: .medium))
                                Spacer()
                                if Store.Settings.Theme == Name { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Accent) }
                            }
                        }.padding(12).frame(maxWidth: .infinity)
                            .background(Theme.Card, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13)
                                .stroke(Store.Settings.Theme == Name ? Theme.Accent : Theme.Border, lineWidth: Store.Settings.Theme == Name ? 2 : 1))
                    }.buttonStyle(MotionButtonStyle())
                }
            }.frame(maxWidth: 930)
            Toggle(isOn: $Store.Settings.ReduceMotion) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(I18n.T("Reduce motion")).font(.system(size: 18, weight: .semibold))
                    Text(I18n.T("Use gentler transitions throughout the app.")).font(.system(size: 14)).foregroundStyle(Theme.SecondaryText)
                }
            }.toggleStyle(.switch).padding(18).frame(maxWidth: 930, alignment: .leading)
                .background(Theme.Card, in: RoundedRectangle(cornerRadius: 12))
            ContinueButton
        }.frame(maxWidth: 1000)
            .onAppear { ThemeGroup = ["dark", "midnight", "cyberpunk", "ocean", "forest", "sunset"].contains(Store.Settings.Theme) ? "Dark" : "Light" }
    }

    private func ThemeColor(_ Name: String) -> Color {
        switch Name {
        case "light": return .blue.opacity(0.45)
        case "blue": return .blue
        case "purple": return .purple
        case "emerald", "forest": return .green
        case "rose", "cyberpunk": return .pink
        case "amber", "sunset": return .orange
        case "ocean": return .cyan
        default: return .indigo
        }
    }

    private var ExtrasPage: some View {
        VStack(spacing: 28) {
            Heading("Optional extras", Subtitle: I18n.T("You can do these later too."), Symbol: "plus.circle")
            HStack(alignment: .top, spacing: 16) {
                FeatureCard("Import games you already have", "Find installed Steam games or choose a game file on this Mac.", "gamecontroller",
                            ActionTitle: I18n.T("Import games")) { ShowingImport = true }
                FeatureCard("Browser links", "Ascendara can open supported game links from your browser.", "puzzlepiece.extension",
                            ActionTitle: I18n.T("Read the guide ↗")) { Store.OpenExternal("https://www.ascendara.app/docs") }
            }.frame(maxWidth: 900)
            ContinueButton
        }
        .sheet(isPresented: $ShowingImport) { ImportPage }
    }

    private var ImportPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(I18n.T("Bring in games from other launchers")).font(.system(size: 27, weight: .bold))
                Spacer()
                Button(I18n.T("Close")) { ShowingImport = false }.keyboardShortcut(.cancelAction)
            }
            Text(I18n.T("Bring installed games into Ascendara so your games are in one place."))
                .foregroundStyle(Theme.SecondaryText)
            Button {
                ShowingImport = false
                Store.ScanSteamLibrary()
            } label: {
                ImportChoice("Scan installed Steam games", "Finds games installed with Steam on this Mac. Nothing is moved or downloaded.", "internaldrive")
            }.buttonStyle(MotionButtonStyle())
            Button {
                ShowingImport = false
                Store.ImportGame()
            } label: {
                ImportChoice("Choose a game file", "Add a macOS app, executable, or Windows game you already have.", "folder")
            }.buttonStyle(MotionButtonStyle())
            Button {
                ShowingImport = false
                Store.ImportLibrary()
            } label: {
                ImportChoice("Import Ascendara library", "Choose a saved Ascendara library JSON file.", "books.vertical")
            }.buttonStyle(MotionButtonStyle())
            Text(I18n.T("Other launcher accounts are not connected in this Mac version."))
                .font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
        }.padding(30).frame(width: 620).background(Theme.Background)
    }

    private func ImportChoice(_ Title: String, _ Subtitle: String, _ Symbol: String) -> some View {
        HStack(spacing: 20) {
            Image(systemName: Symbol).font(.system(size: 30)).foregroundStyle(Theme.Accent).frame(width: 50)
            VStack(alignment: .leading, spacing: 6) {
                Text(I18n.T(Title)).font(.system(size: 18, weight: .semibold))
                Text(I18n.T(Subtitle)).font(.system(size: 14)).foregroundStyle(Theme.SecondaryText)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
        }.padding(22).background(Theme.Card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var SummaryPage: some View {
        VStack(spacing: 22) {
            Heading("You're all set", Subtitle: I18n.T("Here's how Ascendara is set up. You can change these in Preferences."), Symbol: "paperplane")
            VStack(spacing: 0) {
                SummaryRow("Download folder", Value: Store.Settings.DownloadDirectory, Symbol: "folder")
                Divider()
                SummaryRow("Windows games", Value: Store.Compatibility.Status.HighballAvailable || Store.Compatibility.Status.WineAvailable ? "Runtime detected" : "Set up in Compatibility", Symbol: "desktopcomputer")
                Divider()
                SummaryRow("Theme", Value: Store.Settings.Theme.capitalized, Symbol: "paintpalette")
            }.padding(.horizontal, 20).frame(maxWidth: 820)
                .background(Theme.Card, in: RoundedRectangle(cornerRadius: 16))
            Text(I18n.T("You can browse the catalogue now. Add a game whenever you're ready."))
                .font(.system(size: 16)).foregroundStyle(Theme.SecondaryText)
            Button(I18n.T("Take the Tour →")) { Step = 9 }.buttonStyle(PrimaryButtonStyle())
            Button(I18n.T("Skip Tour")) { Store.CompleteWelcome() }.buttonStyle(.plain).foregroundStyle(Theme.Accent)
        }.frame(maxWidth: 900)
    }

    private func SummaryRow(_ Title: String, Value: String, Symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: Symbol).foregroundStyle(Theme.Accent).frame(width: 25)
            Text(I18n.T(Title)).font(.system(size: 17))
            Spacer()
            Text(I18n.T(Value)).font(.system(size: 16, weight: .medium)).lineLimit(1).truncationMode(.middle)
        }.padding(.vertical, 20)
    }

    private var TourPage: some View {
        let Titles = ["Discover games", "Build your library", "Play your way"]
        let Messages = ["Search the catalogue, browse genres, and save games for later.",
                        "Add a game you already own, or download a supported game and import it.",
                        "Launch from your library or switch to Big Picture for a TV layout."]
        let Symbols = ["magnifyingglass", "books.vertical", "gamecontroller"]
        return VStack(spacing: 28) {
            Heading(Titles[TourStep], Subtitle: Messages[TourStep], Symbol: Symbols[TourStep])
            Text(I18n.Interpolated("\(TourStep + 1) of 3")).font(.system(size: 16)).foregroundStyle(Theme.SecondaryText)
            Button(TourStep == 2 ? "Start exploring" : "Next →") {
                if TourStep == 2 { Store.CompleteWelcome() } else { TourStep += 1 }
            }.buttonStyle(PrimaryButtonStyle())
            Button(I18n.T("Finish tour")) { Store.CompleteWelcome() }.buttonStyle(.plain).foregroundStyle(Theme.Accent)
        }.frame(maxWidth: 850)
    }

    private func Heading(_ Title: String, Subtitle: String, Symbol: String) -> some View {
        VStack(spacing: 17) {
            Image(systemName: Symbol).font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.Accent).frame(width: 64, height: 64)
                .background(Theme.Accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            Text(I18n.T(Title)).font(.system(size: 38, weight: .bold))
                .foregroundStyle(Theme.Accent).multilineTextAlignment(.center)
            Text(I18n.T(Subtitle)).font(.system(size: 18)).foregroundStyle(Theme.SecondaryText)
                .multilineTextAlignment(.center).frame(maxWidth: 760)
        }
    }

    private var ContinueButton: some View {
        Button(I18n.T("Continue →")) { Step += 1 }.buttonStyle(PrimaryButtonStyle())
    }

    private var Footer: some View {
        HStack {
            if Step > 0 {
                Button(I18n.T("← Back")) {
                    if Step == 9 { Step = 8; TourStep = 0 } else { Step -= 1 }
                }.buttonStyle(.plain).foregroundStyle(Theme.Foreground)
                    .font(.system(size: 16, weight: .medium)).disabled(CompatibilityBusy)
            }
            Spacer()
            if (2...8).contains(Step) {
                HStack(spacing: 6) {
                    ForEach(2...8, id: \.self) { Index in
                        Capsule().fill(Index == Step ? Theme.Accent : Theme.Accent.opacity(0.3))
                            .frame(width: Index == Step ? 27 : 7, height: 6)
                    }
                }.accessibilityLabel(I18n.Interpolated("Setup step \(Step - 1) of 7"))
            }
            Spacer()
            if Step > 0 { Color.clear.frame(width: 58, height: 1) }
        }.padding(.horizontal, 30).frame(height: 54)
    }

    private func FeatureCard(_ Title: String, _ Subtitle: String, _ Symbol: String,
                             ActionTitle: String? = nil, Action: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: Symbol).font(.system(size: 27)).foregroundStyle(Theme.Accent)
            Text(I18n.T(Title)).font(.system(size: 19, weight: .semibold))
            Text(I18n.T(Subtitle)).font(.system(size: 15)).foregroundStyle(Theme.SecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if let ActionTitle, let Action {
                Button(ActionTitle, action: Action).buttonStyle(.plain).foregroundStyle(Theme.Accent)
                    .font(.system(size: 16, weight: .semibold))
            }
        }.padding(21).frame(maxWidth: .infinity, minHeight: 208, alignment: .topLeading)
            .background(Theme.Card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Border.opacity(0.9)))
    }

    private func AgreementRow(Value: Binding<Bool>, Title: String, Link: String, URL: String) -> some View {
        HStack(spacing: 13) {
            Toggle(Title, isOn: Value).toggleStyle(.checkbox).font(.system(size: 16))
            Spacer()
            Button(Link) { Store.OpenExternal(URL) }.buttonStyle(.plain).foregroundStyle(Theme.Accent)
        }
    }
}

private struct WelcomeChoiceStyle: ButtonStyle {
    let Selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(Theme.Foreground)
            .background(Selected ? Theme.Accent.opacity(0.15) : Theme.Card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Selected ? Theme.Accent : Theme.Border.opacity(0.4)))
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .ButtonFeedback(Pressed: configuration.isPressed)
    }
}

struct WelcomeCompatibilityView: View {
    @EnvironmentObject private var Store: AppStore
    var OnBusyChanged: (Bool) -> Void = { _ in }

    var body: some View {
        WelcomeCompatibilityCard(Service: Store.Compatibility, OnBusyChanged: OnBusyChanged)
            .environmentObject(Store)
    }
}

private struct WelcomeCompatibilityCard: View {
    @EnvironmentObject private var Store: AppStore
    @ObservedObject var Service: CompatibilityService
    let OnBusyChanged: (Bool) -> Void
    @State private var HasChecked = false
    @State private var BusyMessage: String?
    @State private var Result: String?
    @State private var Failure: String?
    @State private var ShowingOptions = false

    private var HighballReady: Bool { Service.IsHighballReady }

    private var IsConfigured: Bool { HasChecked && (HighballReady || Service.Status.WineAvailable) }

    private var CanPrepare: Bool {
        HasChecked && Service.Status.HighballAvailable && Service.DefaultManifestURL != nil
    }

    private var StatusText: String {
        if let Message = Service.SetupMessage { return Message }
        if let BusyMessage { return BusyMessage }
        if !HasChecked { return "Checking this Mac…" }
        if HighballReady { return "Highball engine and game environment are ready." }
        if Service.Status.WineAvailable { return "An installed Wine runtime was detected." }
        if !Service.Status.AppleSilicon { return "Choose an installed Wine runtime for this Mac." }
        if !Service.Status.HighballAvailable { return "This build does not include the Highball helper. Open Advanced options." }
        return "Download once to set up Windows game support automatically."
    }

    private var ActionTitle: String {
        if BusyMessage != nil { return "Please wait…" }
        if IsConfigured { return "Manage setup" }
        if CanPrepare { return "Download" }
        return "Advanced options"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text(I18n.T("Windows games on your Mac")).font(.system(size: 22, weight: .semibold))
                Text(I18n.T("Set up a compatibility runtime to play supported Windows games. Native Mac games do not need these files."))
                    .font(.system(size: 14)).foregroundStyle(Theme.SecondaryText).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.Accent.opacity(0.09))
                    Image(systemName: IsConfigured ? "checkmark.shield" : "shippingbox")
                        .font(.system(size: 24, weight: .medium)).foregroundStyle(Theme.Accent)
                }.frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 7) {
                    Text(I18n.T("Game compatibility files")).font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 7) {
                        if BusyMessage != nil { ProgressView().controlSize(.small) }
                        else if IsConfigured { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        Text(StatusText).foregroundStyle(Theme.SecondaryText)
                    }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(ActionTitle) { BeginSetup() }.buttonStyle(PrimaryButtonStyle())
                    .disabled(BusyMessage != nil || !HasChecked)
            }.padding(18)
                .background(Theme.Background.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Border.opacity(0.65)))
            if BusyMessage != nil {
                CompatibilitySetupProgressView(Service: Service)
            }
            if let Failure {
                Feedback(Failure, Symbol: "exclamationmark.triangle", Color: .orange)
            } else if let Result {
                Feedback(Result, Symbol: "checkmark.circle", Color: .green)
            } else if HasChecked, let Error = Service.Status.ErrorMessage {
                Feedback(Error, Symbol: "exclamationmark.triangle", Color: .orange)
            }
            HStack(spacing: 16) {
                Button(I18n.T("Advanced options")) { ShowingOptions = true }
                    .buttonStyle(MotionButtonStyle()).foregroundStyle(Theme.Accent)
                Button(I18n.T("Check again")) { Task { await Refresh() } }
                    .buttonStyle(MotionButtonStyle()).foregroundStyle(Theme.SecondaryText)
                Spacer(minLength: 0)
            }.font(.system(size: 13, weight: .medium)).disabled(BusyMessage != nil)
            Text(I18n.T("You can change this later in Settings → Compatibility. Game support varies by title."))
                .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
        }
        .padding(26)
        .frame(maxWidth: 780, alignment: .leading)
        .foregroundStyle(Theme.CardForeground)
        .background(Theme.Card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Border.opacity(0.55)))
        .task { await Refresh() }
        .sheet(isPresented: $ShowingOptions, onDismiss: { Task { await Refresh() } }) {
            CompatibilityView().environmentObject(Store)
        }
    }

    private func Feedback(_ Message: String, Symbol: String, Color: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: Symbol).foregroundStyle(Color)
            Text(I18n.T(Message)).foregroundStyle(Theme.SecondaryText).textSelection(.enabled)
        }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
    }

    private func SetBusy(_ Message: String?) {
        BusyMessage = Message
        OnBusyChanged(Message != nil)
    }

    private func Refresh() async {
        guard BusyMessage == nil else { return }
        SetBusy("Checking this Mac…")
        await Service.Detect()
        HasChecked = true
        SetBusy(nil)
    }

    private func BeginSetup() {
        guard BusyMessage == nil else { return }
        guard !IsConfigured, CanPrepare else {
            ShowingOptions = true
            return
        }
        Failure = nil
        Result = nil
        SetBusy("Setting up compatibility…")
        Task {
            defer { SetBusy(nil) }
            do {
                try await Service.EnsureReady()
                await Service.Detect()
                HasChecked = true
                guard HighballReady else {
                    throw RuntimeError.Message(Service.Status.ErrorMessage ?? "Setup finished, but the game environment could not be verified. Open Advanced options to check it.")
                }
                Result = "Compatibility files are installed. Windows games can use the ascendara environment automatically."
            } catch {
                Failure = error.localizedDescription
                await Service.Detect()
                HasChecked = true
            }
        }
    }
}
