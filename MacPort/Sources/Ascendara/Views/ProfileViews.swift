import AppKit
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var Store: AppStore
    @AppStorage("NativeProfileNotes") private var Notes = ""
    @State private var EditingName = false
    private var Played: [LibraryGame] { Store.Library.filter { $0.LastPlayedAt != nil }.sorted { $0.PlayTimeSeconds > $1.PlayTimeSeconds } }
    private var TotalTime: Double { Store.Library.reduce(0) { $0 + $1.PlayTimeSeconds } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Panel(Padding: 28) {
                    HStack(spacing: 23) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 76, weight: .ultraLight)).foregroundStyle(Theme.Accent)
                        VStack(alignment: .leading, spacing: 9) {
                            if EditingName {
                                TextField("Display name", text: $Store.Settings.DisplayName).textFieldStyle(.roundedBorder).frame(width: 250).onSubmit { Store.SaveSettings(); EditingName = false }
                            } else {
                                Text(Store.Settings.DisplayName).font(.system(size: 30, weight: .bold))
                            }
                            Text("Your space. Your games.").font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
                            Label("Local profile", systemImage: "desktopcomputer").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.Accent)
                        }
                        Spacer()
                        Button(EditingName ? "Save name" : "Edit profile") {
                            if EditingName { Store.SaveSettings() }
                            EditingName.toggle()
                        }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                HStack(spacing: 16) {
                    StatCard(Title: "In your library", Value: "\(Store.Library.count)", Symbol: "books.vertical")
                    StatCard(Title: "Games played", Value: "\(Played.count)", Symbol: "gamecontroller")
                    StatCard(Title: "Time played", Value: FormatPlayTime(TotalTime), Symbol: "clock")
                    StatCard(Title: "Favorites", Value: "\(Store.Library.filter(\.Favorite).count)", Symbol: "star")
                }
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 22) {
                        Panel {
                            VStack(alignment: .leading, spacing: 18) {
                                SectionHeading(Title: "Most played", Symbol: "chart.bar")
                                if Played.isEmpty {
                                    Text("Play a game from your library to start tracking time.").font(.system(size: 12)).foregroundStyle(Theme.SecondaryText).padding(.vertical, 30)
                                } else {
                                    ForEach(Array(Played.prefix(6).enumerated()), id: \.element.Id) { Index, Game in
                                        HStack(spacing: 12) {
                                            Text("\(Index + 1)").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.SecondaryText).frame(width: 20)
                                            GameArtwork(URL: Game.ArtworkURL, Name: Game.Name).frame(width: 78, height: 44)
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(Game.Name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                                ProgressView(value: Game.PlayTimeSeconds, total: max(1, Played.first?.PlayTimeSeconds ?? 1)).tint(Theme.Accent)
                                            }
                                            Spacer(minLength: 10)
                                            Text(FormatPlayTime(Game.PlayTimeSeconds)).font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                                        }
                                    }
                                }
                            }
                        }
                        Panel {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeading(Title: "Private notes", Symbol: "note.text")
                                Text("A little space for your thoughts, goals, and next adventures.").font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                                TextEditor(text: $Notes).font(.system(size: 13)).scrollContentBackground(.hidden).frame(height: 140).padding(10).background(Theme.Background, in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }.frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 22) {
                        Panel {
                            VStack(alignment: .leading, spacing: 18) {
                                SettingsHeading("Your Mac", "System information", "desktopcomputer")
                                DeviceRow("Computer", Host.current().localizedName ?? "Mac")
                                DeviceRow("System", ProcessInfo.processInfo.operatingSystemVersionString)
                                DeviceRow("Memory", ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
                                DeviceRow("Processors", "\(ProcessInfo.processInfo.processorCount) cores")
                                #if arch(arm64)
                                DeviceRow("Architecture", "Apple Silicon")
                                #else
                                DeviceRow("Architecture", "Intel")
                                #endif
                            }
                        }
                        Panel {
                            VStack(alignment: .leading, spacing: 13) {
                                Image(systemName: "at").font(.system(size: 27, weight: .semibold)).foregroundStyle(Theme.Accent)
                                Text("Connect with Ascend").font(.system(size: 17, weight: .semibold))
                                Text("Manage your account and connected community services.").font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                                Button("Open Ascend") { Store.CurrentRoute = .Ascend }.buttonStyle(PrimaryButtonStyle())
                            }
                        }
                    }.frame(width: 315)
                }
            }.padding(30).padding(.bottom, 100).frame(maxWidth: 1350).frame(maxWidth: .infinity)
        }
    }
    private func DeviceRow(_ Title: String, _ Value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(Title).font(.system(size: 11)).foregroundStyle(Theme.SecondaryText); Text(Value).font(.system(size: 12)).textSelection(.enabled) }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var Store: AppStore
    @State private var Step = 0
    var body: some View {
        VStack(spacing: 26) {
            HStack(spacing: 6) {
                ForEach(0..<3) { Index in Capsule().fill(Index <= Step ? Theme.Accent : Theme.Muted).frame(width: Index == Step ? 35 : 15, height: 4) }
            }.padding(.top, 12)
            Image(systemName: Step == 0 ? "gamecontroller.fill" : Step == 1 ? "folder.fill" : "sparkles").font(.system(size: 58, weight: .light)).foregroundStyle(Theme.Accent).frame(height: 95)
            VStack(spacing: 12) {
                Text(Step == 0 ? "Welcome to Ascendara" : Step == 1 ? "A home for your games" : "Make it yours").font(.system(size: 30, weight: .bold))
                Text(Step == 0 ? "Discover, download, and play. Your game library, together on your Mac." : Step == 1 ? "Choose where downloads and extracted games are stored." : "Choose a name and a look. You can change both in Preferences.")
                    .font(.system(size: 14)).foregroundStyle(Theme.SecondaryText).multilineTextAlignment(.center).frame(maxWidth: 460)
            }
            ZStack {
                Group {
                    if Step == 0 {
                        HStack(spacing: 30) {
                            WelcomeFeature("Discover", "magnifyingglass")
                            WelcomeFeature("Download", "arrow.down.circle")
                            WelcomeFeature("Play", "play.circle")
                        }.padding(.vertical, 20)
                    } else if Step == 1 {
                        VStack(spacing: 15) {
                            Text(Store.Settings.DownloadDirectory).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(16).frame(maxWidth: .infinity).background(Theme.Card, in: RoundedRectangle(cornerRadius: 10))
                            Button("Choose folder…") { Store.ChooseDownloadDirectory() }.buttonStyle(SecondaryButtonStyle())
                        }.frame(width: 450)
                    } else {
                        VStack(spacing: 15) {
                            TextField("Your name", text: $Store.Settings.DisplayName).textFieldStyle(.roundedBorder)
                            Picker("Theme", selection: $Store.Settings.Theme) {
                                Text("Purple").tag("purple")
                                Text("Dark").tag("dark")
                                Text("Light").tag("light")
                                Text("Midnight").tag("midnight")
                            }.pickerStyle(.segmented)
                        }.frame(width: 400)
                    }
                }.id(Step).MotionTransition()
            }.frame(height: 110)
            HStack {
                if Step > 0 { Button("Back") { Step -= 1 }.buttonStyle(SecondaryButtonStyle()) }
                Spacer()
                Button(Step == 2 ? "Start exploring" : "Continue") {
                    if Step == 2 { Store.CompleteWelcome() } else { Step += 1 }
                }.buttonStyle(PrimaryButtonStyle())
            }.frame(width: 470)
        }.padding(36).frame(width: 590, height: 530).background(Theme.Background).foregroundStyle(Theme.Foreground)
            .MotionAnimation(Step)
    }
    private func WelcomeFeature(_ Title: String, _ Symbol: String) -> some View {
        VStack(spacing: 10) { Image(systemName: Symbol).font(.system(size: 24)).foregroundStyle(Theme.Accent); Text(Title).font(.system(size: 12, weight: .medium)) }.frame(width: 95)
    }
}
