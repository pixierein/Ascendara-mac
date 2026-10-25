import SwiftUI

struct ReinstallView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.dismiss) private var Dismiss
    let Request: ReinstallRequest
    @State private var Parent = ""
    @State private var FolderName = ""
    @State private var KeepPlaytime = true
    @State private var KeepAchievements = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(I18n.Interpolated("Reinstall \(Request.Game.Name)")).font(.title2.bold())
            Text(I18n.T("The current installation stays available until the new files are ready. Choose where to install the replacement and what to retain."))
                .foregroundStyle(Theme.SecondaryText)
            HStack {
                TextField(I18n.T("Installation parent folder"), text: $Parent).textFieldStyle(.roundedBorder)
                Button(I18n.T("Choose…")) { if let Folder = Store.ChooseFolder(Title: I18n.T("Choose the installation parent folder")) { Parent = Folder.path } }
            }
            TextField(I18n.T("Installation folder name"), text: $FolderName).textFieldStyle(.roundedBorder)
            Text(URL(fileURLWithPath: Parent).appendingPathComponent(RuntimePaths.SafeName(FolderName)).path)
                .font(.caption).foregroundStyle(Theme.SecondaryText).textSelection(.enabled)
            Toggle(I18n.T("Keep playtime and launch history"), isOn: $KeepPlaytime)
            Toggle(I18n.T("Keep achievements"), isOn: $KeepAchievements)
            if !Request.Installed.IsManaged {
                Text(I18n.T("The original imported game files will stay in their current location.")).font(.caption).foregroundStyle(Theme.SecondaryText)
            }
            HStack {
                Button(I18n.T("Cancel")) { Dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(I18n.T("Download and reinstall")) {
                    let Destination = URL(fileURLWithPath: (Parent as NSString).expandingTildeInPath)
                        .appendingPathComponent(RuntimePaths.SafeName(FolderName))
                    let Plan = InstallationPlan(ReplaceGameId: Request.Installed.Id, DestinationPath: Destination.path,
                                                KeepPlaytime: KeepPlaytime, KeepAchievements: KeepAchievements)
                    Store.StartDownload(Request.Game, Link: Request.Link, Installation: Plan)
                    Dismiss()
                }.buttonStyle(PrimaryButtonStyle()).disabled(Parent.isEmpty || FolderName.isEmpty || Store.IsRunning(Request.Installed))
            }
        }.padding(28).frame(width: 620).background(Theme.Background).foregroundStyle(Theme.Foreground)
            .onAppear {
                let Existing = Request.Installed.ManagedFilesPath.map { URL(fileURLWithPath: $0) }
                Parent = Existing?.deletingLastPathComponent().path ?? Store.Settings.DownloadDirectory
                FolderName = Existing?.lastPathComponent ?? RuntimePaths.SafeName(Request.Game.Name)
            }
    }
}
