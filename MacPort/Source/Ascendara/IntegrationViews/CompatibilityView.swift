import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CompatibilityView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.dismiss) private var Dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeading(Title: I18n.T("Windows compatibility"), Subtitle: I18n.T("Wine and Highball for your Windows games"), Symbol: "desktopcomputer")
                Button(I18n.T("Done")) { Dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
            CompatibilityPanel(Service: Store.Compatibility).environmentObject(Store)
        }.padding(28).frame(width: 720, height: 680).background(Theme.Background)
    }
}

private struct CompatibilityPanel: View {
    @EnvironmentObject private var Store: AppStore
    @ObservedObject var Service: CompatibilityService
    @State private var Busy = false
    @State private var Engine = ""
    @State private var Bottle = "ascendara"
    @State private var Result: String?
    @State private var Failure: String?
    @State private var ShowingLicense = false
    @State private var AdvancedExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(Service.IsReady ? "Ready to play Windows games" : "Set up Windows games", systemImage: Service.IsReady ? "checkmark.shield.fill" : "desktopcomputer")
                            .font(.system(size: 18, weight: .semibold))
                        Text(Service.IsReady
                             ? "Your compatibility runtime is ready."
                             : Service.Status.AppleSilicon
                                ? "Download the compatibility files and Ascendara will set up the game environment for you."
                                : "Highball needs Apple Silicon. Choose an installed Wine executable in Advanced options.")
                            .font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
                        if !Service.IsReady && Service.Status.AppleSilicon {
                            Button { AutoSetup() } label: {
                                HStack {
                                    if Busy { ProgressView().controlSize(.small) }
                                    Text(Busy ? "Setting up…" : "Download")
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(PrimaryButtonStyle()).disabled(Busy)
                        }
                        if Busy {
                            CompatibilitySetupProgressView(Service: Service)
                        }
                        if let Result { Notice(Message: Result) }
                        if let Failure { Notice(Message: Failure, Symbol: "exclamationmark.triangle") }
                        if let Error = Service.Status.ErrorMessage { Notice(Message: Error, Symbol: "exclamationmark.triangle") }
                    }
                }
                DisclosureGroup(I18n.T("Advanced options"), isExpanded: $AdvancedExpanded) {
                    VStack(alignment: .leading, spacing: 18) {
                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(I18n.T("Your Mac")).font(.headline)
                            Spacer()
                            if Busy { ProgressView().controlSize(.small) }
                            Button(I18n.T("Refresh")) { Refresh() }.disabled(Busy)
                        }
                        StatusRow("Apple Silicon", Available: Service.Status.AppleSilicon)
                        StatusRow("Rosetta 2", Available: Service.Status.RosettaInstalled)
                        if Service.Status.AppleSilicon && !Service.Status.RosettaInstalled {
                            Text(I18n.T("Rosetta is required by Highball. macOS may ask for your administrator password when you install it.")).font(.caption).foregroundStyle(Theme.SecondaryText)
                            Button(I18n.T("Install Rosetta 2")) { InstallRosetta() }.buttonStyle(SecondaryButtonStyle()).disabled(Busy)
                        }
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(I18n.T("Wine")).font(.headline)
                        StatusRow("Wine runtime", Available: Service.Status.WineAvailable)
                        Text(Service.Status.WinePath ?? "Choose an installed Wine executable.").font(.caption).foregroundStyle(Theme.SecondaryText).textSelection(.enabled)
                        HStack {
                            TextField(I18n.T("Custom Wine path"), text: $Store.Settings.WinePath).textFieldStyle(.roundedBorder)
                            Button(I18n.T("Choose…")) { ChooseRuntime(Wine: true) }
                        }
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 13) {
                        Text(I18n.T("Highball")).font(.headline)
                        StatusRow("Highball runtime", Available: Service.Status.HighballAvailable)
                        HStack {
                            TextField(I18n.T("Custom Highball path"), text: $Store.Settings.HighballPath).textFieldStyle(.roundedBorder)
                            Button(I18n.T("Choose…")) { ChooseRuntime(Wine: false) }
                        }
                        Text(I18n.T("The bundled Highball tool downloads a checksum-verified Wine engine and prepares the ascendara environment on this Mac. Games also run setup automatically when needed."))
                            .font(.caption).foregroundStyle(Theme.SecondaryText)
                        HStack {
                            Button(I18n.T("Set up automatically")) { AutoSetup() }
                                .buttonStyle(PrimaryButtonStyle())
                            Button(I18n.T("Download latest compatibility files")) { DownloadLatest() }
                                .buttonStyle(SecondaryButtonStyle())
                        }.disabled(Busy || !Service.Status.HighballAvailable || !Store.RunningIds.isEmpty)
                        if let ID = Service.Status.BottleEngines["ascendara"] {
                            Text(I18n.Interpolated("Active engine: \(ID)")).font(.caption).foregroundStyle(Theme.SecondaryText)
                        } else if let ID = Service.DefaultEngineID {
                            Text(I18n.Interpolated("Bundled engine: \(ID)")).font(.caption).foregroundStyle(Theme.SecondaryText)
                        }
                        if let Error = Service.Status.ErrorMessage { Notice(Message: Error, Symbol: "exclamationmark.triangle") }
                        HStack {
                            Text(I18n.T("Installed engines")).font(.subheadline)
                            Spacer()
                            Menu(I18n.T("Install engine")) {
                                Button(I18n.T("Install bundled engine")) { InstallDefaultEngine() }.disabled(Service.DefaultManifestURL == nil)
                                Button(I18n.T("Choose engine manifest…")) { InstallEngine() }
                            }.disabled(Service.Status.HighballPath == nil || Busy)
                        }
                        if Service.Status.Engines.isEmpty { Text(I18n.T("No installed engines detected.")).font(.caption).foregroundStyle(Theme.SecondaryText) }
                        else {
                            Picker(I18n.T("Engine"), selection: $Engine) { ForEach(Service.Status.Engines, id: \.self) { Engine in Text(Engine).tag(Engine) } }
                            HStack {
                                TextField(I18n.T("Bottle name"), text: $Bottle).textFieldStyle(.roundedBorder)
                                Button(I18n.T("Create bottle")) { CreateBottle() }.disabled(Busy || Bottle.isEmpty || Engine.isEmpty)
                            }
                            Button(I18n.T("Use engine for bottle")) { SwitchBottleEngine() }
                                .disabled(Busy || Engine.isEmpty || !Service.Status.Bottles.contains(Bottle) || !Store.RunningIds.isEmpty)
                            Button(I18n.T("Review D3DMetal license…")) { ShowingLicense = true }.disabled(Busy || Service.D3DMetalLicenseText == nil || Engine.isEmpty)
                        }
                        Text(Service.Status.Bottles.isEmpty ? "No bottles detected." : "Bottles: " + Service.Status.Bottles.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.SecondaryText)
                        Text(I18n.T("Select a game's runner, bottle, and renderer in its library settings.")).font(.caption).foregroundStyle(Theme.SecondaryText)
                    }
                }
                Button(I18n.T("Save paths")) { Store.SaveSettings(); Refresh() }.buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.top, 15)
                }
                .font(.system(size: 13, weight: .medium))
            }
        }.MotionAnimation(Busy).MotionAnimation(Result).task { Refresh() }
            .sheet(isPresented: $ShowingLicense) {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(Title: I18n.T("D3DMetal license"), Subtitle: I18n.Interpolated("Review the license before enabling this renderer for \(Engine)."))
                    ScrollView { Text(Service.D3DMetalLicenseText ?? "The license text is unavailable.").font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack {
                        Spacer()
                        Button(I18n.T("Cancel")) { ShowingLicense = false }.buttonStyle(SecondaryButtonStyle())
                        Button(I18n.T("Accept license")) {
                            ShowingLicense = false
                            Busy = true
                            Task {
                                do { try await Service.AcceptD3DMetalLicense(Engine: Engine); Result = "D3DMetal license accepted for \(Engine)." }
                                catch { Store.Report(error) }
                                Busy = false
                            }
                        }.buttonStyle(PrimaryButtonStyle()).disabled(Service.D3DMetalLicenseText == nil)
                    }
                }.padding(26).frame(width: 670, height: 560).background(Theme.Background)
            }
    }

    private func StatusRow(_ Title: String, Available: Bool) -> some View {
        HStack {
            Image(systemName: Available ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(Available ? .green : Theme.SecondaryText)
            Text(I18n.T(Title)).font(.subheadline)
            Spacer()
            Text(Available ? "Available" : "Not detected").font(.caption).foregroundStyle(Theme.SecondaryText)
        }
    }

    private func Refresh() {
        Busy = true
        Task {
            await Service.Detect()
            if !Service.Status.Engines.contains(Engine) {
                Engine = Service.Status.BottleEngines["ascendara"] ?? Service.Status.Engines.first ?? ""
            }
            Busy = false
        }
    }

    private func ChooseRuntime(Wine: Bool) {
        let Panel = NSOpenPanel()
        Panel.title = Wine ? "Choose the Wine executable" : "Choose the Highball executable"
        Panel.treatsFilePackagesAsDirectories = true
        if Panel.runModal() == .OK, let URL = Panel.url {
            if Wine { Store.Settings.WinePath = URL.path } else { Store.Settings.HighballPath = URL.path }
            Store.SaveSettings()
            Refresh()
        }
    }

    private func InstallEngine() {
        let Panel = NSOpenPanel()
        Panel.title = "Choose a Highball engine manifest"
        Panel.allowedContentTypes = [.json]
        guard Panel.runModal() == .OK, let URL = Panel.url else { return }
        Busy = true
        Task {
            do {
                try await Service.InstallEngine(ManifestURL: URL)
                Result = "Engine installed. Choose it and create a bottle."
                Engine = Service.Status.Engines.first ?? ""
            } catch { Store.Report(error) }
            Busy = false
        }
    }

    private func InstallDefaultEngine() {
        Busy = true
        Task {
            do {
                try await Service.InstallDefaultEngine()
                Result = "Bundled engine installed. Choose it and create a bottle."
                Engine = Service.Status.Engines.first ?? ""
            } catch { Store.Report(error) }
            Busy = false
        }
    }

    private func CreateBottle() {
        Busy = true
        Task {
            do { try await Service.CreateBottle(Name: Bottle, Engine: Engine); Result = "Bottle ‘\(Bottle)’ created." }
            catch { Store.Report(error) }
            Busy = false
        }
    }

    private func SwitchBottleEngine() {
        Busy = true
        Task {
            do {
                try await Service.SetBottleEngine(Name: Bottle, Engine: Engine)
                Result = "Bottle ‘\(Bottle)’ now uses \(Engine)."
            } catch { Store.Report(error) }
            Busy = false
        }
    }

    private func AutoSetup() {
        Busy = true
        Result = nil
        Failure = nil
        Task {
            do {
                try await Service.EnsureReady()
                await Service.Detect()
                guard Service.IsHighballReady else {
                    throw RuntimeError.Message("Setup finished, but the game environment could not be verified.")
                }
                Engine = Service.Status.BottleEngines["ascendara"] ?? Service.DefaultEngineID ?? Service.Status.Engines.first ?? ""
                Result = "Compatibility files and the game environment are ready."
            } catch { Failure = error.localizedDescription }
            Busy = false
        }
    }

    private func DownloadLatest() {
        Busy = true
        Result = nil
        Task {
            do {
                try await Service.InstallLatestEngine()
                Engine = Service.DefaultEngineID ?? Service.Status.Engines.first ?? ""
                Result = "Latest Highball compatibility files are installed and the game environment is ready."
            } catch { Store.Report(error) }
            Busy = false
        }
    }

    private func InstallRosetta() {
        Busy = true
        Task {
            do {
                _ = try await NativeProcess.Checked(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"])
                await Service.Detect()
                Result = Service.Status.RosettaInstalled ? "Rosetta 2 installed." : "Rosetta installation finished, but the runtime is not yet detected."
            } catch { Store.Report(error) }
            Busy = false
        }
    }
}
