import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CompatibilityView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.dismiss) private var Dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeading(Title: "Windows compatibility", Subtitle: "Wine and Highball for your Windows games", Symbol: "desktopcomputer")
                Button("Done") { Dismiss() }.buttonStyle(SecondaryButtonStyle())
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
    @State private var ShowingLicense = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Your Mac").font(.headline)
                            Spacer()
                            if Busy { ProgressView().controlSize(.small) }
                            Button("Refresh") { Refresh() }.disabled(Busy)
                        }
                        StatusRow("Apple Silicon", Available: Service.Status.AppleSilicon)
                        StatusRow("Rosetta 2", Available: Service.Status.RosettaInstalled)
                        if Service.Status.AppleSilicon && !Service.Status.RosettaInstalled {
                            Text("Rosetta is required by Highball. macOS may ask for your administrator password when you install it.").font(.caption).foregroundStyle(Theme.SecondaryText)
                            Button("Install Rosetta 2") { InstallRosetta() }.buttonStyle(SecondaryButtonStyle()).disabled(Busy)
                        }
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Wine").font(.headline)
                        StatusRow("Wine runtime", Available: Service.Status.WineAvailable)
                        Text(Service.Status.WinePath ?? "Choose an installed Wine executable.").font(.caption).foregroundStyle(Theme.SecondaryText).textSelection(.enabled)
                        HStack {
                            TextField("Custom Wine path", text: $Store.Settings.WinePath).textFieldStyle(.roundedBorder)
                            Button("Choose…") { ChooseRuntime(Wine: true) }
                        }
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("Highball").font(.headline)
                        StatusRow("Highball runtime", Available: Service.Status.HighballAvailable)
                        HStack {
                            TextField("Custom Highball path", text: $Store.Settings.HighballPath).textFieldStyle(.roundedBorder)
                            Button("Choose…") { ChooseRuntime(Wine: false) }
                        }
                        if let Error = Service.Status.ErrorMessage { Notice(Message: Error, Symbol: "exclamationmark.triangle") }
                        HStack {
                            Text("Installed engines").font(.subheadline)
                            Spacer()
                            Menu("Install engine") {
                                Button("Install bundled engine") { InstallDefaultEngine() }.disabled(Service.DefaultManifestURL == nil)
                                Button("Choose engine manifest…") { InstallEngine() }
                            }.disabled(Service.Status.HighballPath == nil || Busy)
                        }
                        if Service.Status.Engines.isEmpty { Text("No installed engines detected.").font(.caption).foregroundStyle(Theme.SecondaryText) }
                        else {
                            Picker("Engine", selection: $Engine) { ForEach(Service.Status.Engines, id: \.self) { Engine in Text(Engine).tag(Engine) } }
                            HStack {
                                TextField("Bottle name", text: $Bottle).textFieldStyle(.roundedBorder)
                                Button("Create bottle") { CreateBottle() }.disabled(Busy || Bottle.isEmpty || Engine.isEmpty)
                            }
                            Button("Review D3DMetal license…") { ShowingLicense = true }.disabled(Busy || Service.D3DMetalLicenseText == nil || Engine.isEmpty)
                        }
                        Text(Service.Status.Bottles.isEmpty ? "No bottles detected." : "Bottles: " + Service.Status.Bottles.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.SecondaryText)
                        Text("Select a game's runner, bottle, and renderer in its library settings.").font(.caption).foregroundStyle(Theme.SecondaryText)
                    }
                }
                if let Result { Notice(Message: Result) }
                Button("Save paths") { Store.SaveSettings(); Refresh() }.buttonStyle(PrimaryButtonStyle())
            }
        }.MotionAnimation(Busy).MotionAnimation(Result).task { Refresh() }
            .sheet(isPresented: $ShowingLicense) {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(Title: "D3DMetal license", Subtitle: "Review the license before enabling this renderer for \(Engine).")
                    ScrollView { Text(Service.D3DMetalLicenseText ?? "The license text is unavailable.").font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack {
                        Spacer()
                        Button("Cancel") { ShowingLicense = false }.buttonStyle(SecondaryButtonStyle())
                        Button("Accept license") {
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
            Text(Title).font(.subheadline)
            Spacer()
            Text(Available ? "Available" : "Not detected").font(.caption).foregroundStyle(Theme.SecondaryText)
        }
    }

    private func Refresh() {
        Busy = true
        Task {
            await Service.Detect()
            if !Service.Status.Engines.contains(Engine) { Engine = Service.Status.Engines.first ?? "" }
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
