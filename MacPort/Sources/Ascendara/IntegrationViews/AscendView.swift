import AppKit
import SwiftUI

struct AscendView: View {
    @EnvironmentObject private var Store: AppStore
    @StateObject private var Account = AccountService()
    @State private var Email = ""
    @State private var Password = ""
    @State private var DisplayName = ""
    @State private var Bio = ""
    @State private var IsRegistering = false
    @State private var IsBusy = false
    @State private var Message: String?
    @State private var Tab = "Friends"
    @State private var SelectedFriend: AscendFriend?
    @State private var Draft = ""
    @State private var BackupGame = ""
    @State private var BackupName = ""
    @State private var ShowConfiguration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Ascend").font(.system(size: 36, weight: .bold))
                        Text("Your games. Your friends. Everywhere.").foregroundStyle(Theme.SecondaryText)
                    }
                    Spacer()
                    if IsBusy { ProgressView().controlSize(.small) }
                    Button { ShowConfiguration.toggle() } label: { Label("Account configuration", systemImage: "gearshape") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                if ShowConfiguration || Store.Settings.FirebaseAPIKey.isEmpty || Store.Settings.FirebaseProjectId.isEmpty { Configuration }
                if let Message {
                    HStack {
                        Image(systemName: "info.circle").foregroundStyle(Theme.Accent)
                        Text(Message).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button { self.Message = nil } label: { Image(systemName: "xmark") }.buttonStyle(MotionButtonStyle())
                    }.padding(16).background(Theme.Muted.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                }
                if let Session = Account.Session {
                    Profile(Session)
                    Picker("Ascend", selection: $Tab) {
                        Text("Friends & messages").tag("Friends")
                        Text("Cloud saves").tag("Backups")
                        Text("My profile").tag("Profile")
                    }.pickerStyle(.segmented)
                    if Tab == "Friends" { Friends }
                    else if Tab == "Backups" { CloudBackups }
                    else { ProfileEditor }
                } else { SignIn }
            }.padding(32).frame(maxWidth: 1300).frame(maxWidth: .infinity)
        }
        .MotionAnimation(Tab)
        .MotionAnimation(IsRegistering)
        .MotionAnimation(ShowConfiguration)
        .MotionAnimation(Message)
        .MotionAnimation(IsBusy)
        .task {
            Account.Configure(Store.Settings)
            if Account.Session != nil { await Refresh() }
        }
        .task(id: SelectedFriend?.Id) {
            guard let Friend = SelectedFriend else { return }
            do { try await Account.LoadMessages(Friend: Friend) } catch { Message = error.localizedDescription }
        }
        .onChange(of: Tab) { _, Tab in if Tab == "Backups" { Run { try await Account.LoadBackups() } } }
        .onChange(of: Account.Session?.UserId) { _, _ in
            SelectedFriend = nil; Draft = ""; Message = nil; DisplayName = ""; Bio = ""
        }
    }

    private var Configuration: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Firebase client configuration", systemImage: "key").font(.headline)
                Text("The source repository leaves account configuration empty. Use the Firebase client configuration for your Ascendara deployment.")
                    .font(.callout).foregroundStyle(Theme.SecondaryText)
                HStack {
                    SecureField("Firebase API key", text: $Store.Settings.FirebaseAPIKey)
                    TextField("Firebase project ID", text: $Store.Settings.FirebaseProjectId)
                    Button("Save") { Store.SaveSettings(); Account.Configure(Store.Settings); ShowConfiguration = false }
                        .buttonStyle(PrimaryButtonStyle())
                }.textFieldStyle(.roundedBorder)
            }
        }
    }

    private var SignIn: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "at.circle.fill").font(.system(size: 80)).foregroundStyle(Theme.Accent)
                Text("A home for your\ngaming life.").font(.system(size: 42, weight: .bold))
                Label("Keep up with your friends", systemImage: "person.2")
                Label("Send messages while you play", systemImage: "bubble.left.and.bubble.right")
                Label("Take your saves with you", systemImage: "icloud")
                Button("Explore Ascend ↗") { Store.OpenExternal("https://ascendara.app/ascend") }.buttonStyle(MotionButtonStyle()).foregroundStyle(Theme.Accent)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            Panel {
                VStack(alignment: .leading, spacing: 18) {
                    Text(IsRegistering ? "Create your account" : "Welcome back").font(.title2.bold())
                    if IsRegistering { TextField("Display name", text: $DisplayName) }
                    TextField("Email", text: $Email).textContentType(.emailAddress)
                    SecureField("Password", text: $Password).textContentType(IsRegistering ? .newPassword : .password)
                    Button(IsRegistering ? "Create account" : "Sign in") {
                        Run {
                            Account.Configure(Store.Settings)
                            if IsRegistering { try await Account.Register(Email: Email, Password: Password, Name: DisplayName) }
                            else { try await Account.SignIn(Email: Email, Password: Password) }
                            Password = ""
                            await Refresh()
                        }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(IsBusy || Email.isEmpty || Password.isEmpty)
                    HStack {
                        Button(IsRegistering ? "Already have an account?" : "Create an account") { IsRegistering.toggle() }.buttonStyle(MotionButtonStyle())
                        Spacer()
                        Button("Reset password") {
                            Run { try await Account.ResetPassword(Email: Email); Message = "Password reset requested. Check your inbox." }
                        }.buttonStyle(MotionButtonStyle()).disabled(Email.isEmpty)
                    }.font(.caption).foregroundStyle(Theme.Accent)
                }.textFieldStyle(.roundedBorder).padding(10)
            }.frame(width: 420)
        }.padding(.top, 20)
    }

    private func Profile(_ Session: AccountSession) -> some View {
        Panel {
            HStack(spacing: 17) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 52)).foregroundStyle(Theme.Accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text(Session.DisplayName).font(.title2.bold())
                    Text(Account.Subscription.isEmpty ? Session.Email : Account.Subscription).foregroundStyle(Theme.SecondaryText)
                }
                Spacer()
                Button("Refresh") { Run { await Refresh() } }.buttonStyle(SecondaryButtonStyle()).disabled(IsBusy)
                Button("Sign out") { do { try Account.SignOut() } catch { Message = error.localizedDescription } }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var Friends: some View {
        HStack(alignment: .top, spacing: 20) {
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Friends · \(Account.Friends.count)").font(.headline)
                    if Account.Friends.isEmpty { Text("Your friends will appear here.").font(.callout).foregroundStyle(Theme.SecondaryText) }
                    ForEach(Account.Friends) { Friend in
                        Button { SelectedFriend = Friend } label: {
                            HStack(spacing: 12) {
                                Circle().fill(Friend.Status == "offline" ? .gray : .green).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(Friend.Name).font(.callout.bold())
                                    Text(Friend.Status.capitalized).font(.caption).foregroundStyle(Theme.SecondaryText)
                                }
                                Spacer()
                            }.padding(9).background(SelectedFriend?.Id == Friend.Id ? Theme.Muted : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(MotionButtonStyle())
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 250)
            Panel {
                VStack(alignment: .leading, spacing: 16) {
                    if let Friend = SelectedFriend {
                        HStack {
                            Text(Friend.Name).font(.headline)
                            Spacer()
                            Button("Refresh messages") { Run { try await Account.LoadMessages(Friend: Friend) } }.buttonStyle(MotionButtonStyle())
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(Account.Messages) { Message in
                                    HStack {
                                        if Message.SenderId == Account.Session?.UserId { Spacer(minLength: 60) }
                                        Text(Message.Text).padding(12).background(Message.SenderId == Account.Session?.UserId ? Theme.Accent.opacity(0.15) : Theme.Muted, in: RoundedRectangle(cornerRadius: 12))
                                            .textSelection(.enabled)
                                        if Message.SenderId != Account.Session?.UserId { Spacer(minLength: 60) }
                                    }
                                }
                            }.padding(.vertical, 8)
                        }.frame(height: 290)
                        HStack {
                            TextField("Message \(Friend.Name)", text: $Draft).textFieldStyle(.roundedBorder)
                            Button("Send") { Run { try await Account.SendMessage(Draft, To: Friend); Draft = "" } }
                                .buttonStyle(PrimaryButtonStyle()).disabled(IsBusy || Draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    } else {
                        ContentUnavailableView("Your conversations", systemImage: "bubble.left.and.bubble.right", description: Text("Choose a friend to read and send messages."))
                            .frame(height: 350)
                    }
                }
            }
        }
    }

    private var CloudBackups: some View {
        VStack(spacing: 18) {
            Panel {
                HStack {
                    TextField("Game name", text: $BackupGame)
                    TextField("Backup name", text: $BackupName)
                    Button("Upload backup…") {
                        let Panel = NSOpenPanel()
                        Panel.title = "Choose a save archive"
                        guard Panel.runModal() == .OK, let File = Panel.url else { return }
                        Run { try await Account.UploadBackup(File: File, GameName: BackupGame, Name: BackupName); Message = "Backup uploaded." }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(IsBusy || BackupGame.isEmpty || BackupName.isEmpty)
                }.textFieldStyle(.roundedBorder)
            }
            if Account.Backups.isEmpty {
                ContentUnavailableView("No cloud saves", systemImage: "icloud", description: Text("Upload a save archive to your Ascend account. Cloud storage availability follows your account plan."))
            }
            ForEach(Account.Backups) { Save in
                Panel {
                    HStack {
                        Image(systemName: "icloud").font(.title2).foregroundStyle(Theme.Accent)
                        VStack(alignment: .leading, spacing: 5) { Text(Save.GameName).font(.headline); Text(Save.Name).foregroundStyle(Theme.SecondaryText) }
                        Spacer()
                        Text(Save.CreatedAt).font(.caption).foregroundStyle(Theme.SecondaryText)
                        Button("Download") { Run { Store.StartDirectDownload(Name: Save.Name, Link: try await Account.BackupDownloadURL(Save)) } }
                            .buttonStyle(SecondaryButtonStyle()).disabled(IsBusy)
                    }
                }
            }
        }
    }

    private var ProfileEditor: some View {
        Panel {
            VStack(alignment: .leading, spacing: 15) {
                Text("Your profile").font(.title2.bold())
                TextField("Display name", text: $DisplayName).textFieldStyle(.roundedBorder)
                TextEditor(text: $Bio).frame(height: 110).padding(5).background(Theme.Muted, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button("Save profile") { Run { try await Account.UpdateProfile(Name: DisplayName, Bio: Bio); Message = "Profile updated." } }.buttonStyle(PrimaryButtonStyle())
                    Button("Send verification email") { Run { try await Account.SendVerification(); Message = "Verification email requested." } }.buttonStyle(SecondaryButtonStyle())
                }.disabled(IsBusy)
            }
        }
    }
    private func Run(_ Action: @escaping @MainActor () async throws -> Void) {
        guard !IsBusy else { return }
        IsBusy = true
        Task {
            defer { IsBusy = false }
            do { try await Action() } catch { Message = error.localizedDescription }
        }
    }
    private func Refresh() async {
        do {
            try await Account.RefreshProfile()
            DisplayName = Account.Session?.DisplayName ?? ""
            Bio = Account.Bio
        } catch { Message = error.localizedDescription }
    }
}
