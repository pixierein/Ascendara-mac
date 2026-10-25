import Foundation
import Combine
import UserNotifications

struct AppNotification: Codable, Identifiable {
    let Id: UUID
    var id: UUID { Id }
    let Date: Date
    let Title: String
    let Message: String
    let Kind: String
    var Read = false
    enum CodingKeys: String, CodingKey { case Id = "id", Date, Title, Message, Kind, Read }
}

@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var Items: [AppNotification] = []
    private let File: URL
    private var Settings = AppSettings()

    init(Directory: URL = AppPaths.Support) {
        File = Directory.appendingPathComponent("notifications.json")
        Items = (try? AppPaths.Read([AppNotification].self, From: File)) ?? []
    }

    var UnreadCount: Int { Items.filter { !$0.Read }.count }
    func Configure(_ Settings: AppSettings) { self.Settings = Settings }

    func RequestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func Post(_ Title: String, Message: String, Kind: String) {
        let Enabled = Kind == "download" ? Settings.NotifyDownloads : Kind == "failure" ? Settings.NotifyFailures
            : Kind == "achievement" ? Settings.NotifyAchievements : Settings.NotifyUpdates
        guard Enabled else { return }
        if let Last = Items.first(where: { $0.Title == Title && $0.Message == Message }), Date().timeIntervalSince(Last.Date) < 3600 { return }
        let Item = AppNotification(Id: UUID(), Date: Date(), Title: Title, Message: Message, Kind: Kind)
        Items.insert(Item, at: 0)
        Items = Array(Items.prefix(200))
        Save()
        guard Settings.SystemNotifications else { return }
        Task {
            let Center = UNUserNotificationCenter.current()
            let Authorization = await Center.notificationSettings().authorizationStatus
            guard Authorization == .authorized || Authorization == .provisional else { return }
            let Content = UNMutableNotificationContent()
            Content.title = I18n.T(Title); Content.body = Message; Content.sound = .default
            try? await Center.add(UNNotificationRequest(identifier: Item.id.uuidString, content: Content, trigger: nil))
        }
    }

    func MarkRead() {
        for Index in Items.indices { Items[Index].Read = true }
        Save()
    }
    func Clear() { Items = []; Save() }
    private func Save() { try? AppPaths.Write(Items, To: File) }
}
