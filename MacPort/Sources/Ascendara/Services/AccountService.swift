import Foundation
import Combine

struct AccountSession: Codable {
    var UserId: String
    var Email: String
    var DisplayName: String
    var IdToken: String
    var RefreshToken: String
    var ExpiresAt: Date
    var ProjectId: String?
}

struct AscendFriend: Identifiable {
    var Id: String
    var Name: String
    var Status: String
    var PhotoURL: URL?
    var id: String { Id }
}

struct AscendMessage: Identifiable {
    var Id: String
    var SenderId: String
    var Text: String
    var CreatedAt: String
    var id: String { Id }
}

struct CloudSave: Identifiable {
    var Id: String
    var GameName: String
    var Name: String
    var CreatedAt: String
    var id: String { Id }
}

final class AccountRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ Session: URLSession, task Task: URLSessionTask, willPerformHTTPRedirection Response: HTTPURLResponse,
                    newRequest Request: URLRequest, completionHandler Completion: @escaping (URLRequest?) -> Void) {
        Completion(nil)
    }
}

@MainActor
final class AccountService: ObservableObject {
    @Published private(set) var Session: AccountSession?
    @Published private(set) var Friends: [AscendFriend] = []
    @Published private(set) var Messages: [AscendMessage] = []
    @Published private(set) var Backups: [CloudSave] = []
    @Published private(set) var Bio = ""
    @Published private(set) var Subscription = ""
    var APIKey = ""
    var ProjectId = ""
    private let Network: URLSession
    private let ReadSecret: (String) -> String?
    private let WriteSecret: (String, String) throws -> Void
    private var ActiveConversation: String?
    private var SessionGeneration = UUID()
    private var ConfiguredProject: String?
    private var SessionKey: String { "AccountSession.\(ProjectId)" }

    init(Network: URLSession? = nil,
         ReadSecret: @escaping (String) -> String? = KeychainService.Read,
         WriteSecret: @escaping (String, String) throws -> Void = { try KeychainService.Write($0, For: $1) }) {
        self.Network = Network ?? URLSession(configuration: .ephemeral, delegate: AccountRedirectPolicy(), delegateQueue: nil)
        self.ReadSecret = ReadSecret
        self.WriteSecret = WriteSecret
    }

    func Configure(_ Settings: AppSettings) {
        APIKey = Settings.FirebaseAPIKey
        ProjectId = Settings.FirebaseProjectId
        guard ConfiguredProject != ProjectId else { return }
        ConfiguredProject = ProjectId
        ClearSession()
        if let Saved = ReadSecret(SessionKey), let Data = Saved.data(using: .utf8),
           let Restored = try? JSONDecoder().decode(AccountSession.self, from: Data), Restored.ProjectId == ProjectId {
            Session = Restored
        }
    }

    func SignIn(Email: String, Password: String) async throws {
        ClearSession()
        let Generation = SessionGeneration
        let Object = try await Auth("accounts:signInWithPassword", Body: ["email": Email, "password": Password, "returnSecureToken": true])
        guard SessionGeneration == Generation else { throw CancellationError() }
        try SaveSession(Object, Email: Email)
    }

    func Register(Email: String, Password: String, Name: String) async throws {
        guard !Name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure.Message("Enter a display name.") }
        ClearSession()
        let Generation = SessionGeneration
        let Object = try await Auth("accounts:signUp", Body: ["email": Email, "password": Password, "returnSecureToken": true])
        guard SessionGeneration == Generation else { throw CancellationError() }
        try SaveSession(Object, Email: Email)
        guard let Session else { return }
        _ = try await Auth("accounts:update", Body: ["idToken": Session.IdToken, "displayName": Name, "returnSecureToken": false])
        try CheckSession(Generation, UserId: Session.UserId)
        let Document = DocumentName("users/\(Session.UserId)")
        _ = try await Firestore(":commit", Method: "POST", Body: ["writes": [[
            "update": ["name": Document, "fields": ["uid": ["stringValue": Session.UserId], "displayName": ["stringValue": Name]]],
            "updateTransforms": [["fieldPath": "createdAt", "setToServerValue": "REQUEST_TIME"], ["fieldPath": "updatedAt", "setToServerValue": "REQUEST_TIME"]]
        ]]])
        try CheckSession(Generation, UserId: Session.UserId)
        self.Session?.DisplayName = Name
        try PersistSession()
        try await SendVerification()
    }

    func SendVerification() async throws {
        let Token = try await Token()
        _ = try await Auth("accounts:sendOobCode", Body: ["requestType": "VERIFY_EMAIL", "idToken": Token])
    }

    func ResetPassword(Email: String) async throws {
        _ = try await Auth("accounts:sendOobCode", Body: ["requestType": "PASSWORD_RESET", "email": Email])
    }

    func SignOut() throws {
        try WriteSecret("", SessionKey)
        ClearSession()
    }
    private func ClearSession() {
        SessionGeneration = UUID()
        Session = nil; Friends = []; Messages = []; Backups = []; Bio = ""; Subscription = ""; ActiveConversation = nil
    }
    private func CheckSession(_ Generation: UUID, UserId: String) throws {
        guard SessionGeneration == Generation, Session?.UserId == UserId else { throw CancellationError() }
    }

    func RefreshProfile() async throws {
        guard let Session else { return }
        let Generation = SessionGeneration
        let Profile = try await ReadDocument("users/\(Session.UserId)")
        try CheckSession(Generation, UserId: Session.UserId)
        let FriendDocument = try await ReadDocument("friends/\(Session.UserId)")
        try CheckSession(Generation, UserId: Session.UserId)
        var Loaded: [AscendFriend] = []
        for Id in (FriendDocument["list"] as? [String] ?? []).prefix(200) {
            let Profile = try await ReadDocument("users/\(Id)")
            try CheckSession(Generation, UserId: Session.UserId)
            let Status = try await ReadDocument("userStatus/\(Id)")
            try CheckSession(Generation, UserId: Session.UserId)
            Loaded.append(AscendFriend(Id: Id, Name: Profile["displayName"] as? String ?? Id,
                                      Status: Status["status"] as? String ?? "offline",
                                      PhotoURL: (Profile["photoURL"] as? String).flatMap(URL.init(string:))))
        }
        Bio = Profile["bio"] as? String ?? ""
        self.Session?.DisplayName = Profile["displayName"] as? String ?? Session.DisplayName
        let Plan = Profile["ascendSubscription"] as? [String: Any]
        Subscription = Plan?["active"] as? Bool == true ? "Ascend subscription active" : "Ascend account"
        try PersistSession()
        Friends = Loaded.sorted { $0.Name.localizedStandardCompare($1.Name) == .orderedAscending }
    }

    func UpdateProfile(Name: String, Bio: String) async throws {
        guard let Session else { throw AppFailure.Message("Sign in first.") }
        let Generation = SessionGeneration
        guard !Name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure.Message("Enter a display name.") }
        _ = try await Firestore("/users/\(Session.UserId)?updateMask.fieldPaths=displayName&updateMask.fieldPaths=bio", Method: "PATCH",
                                Body: ["fields": ["displayName": ["stringValue": Name], "bio": ["stringValue": Bio]]])
        try CheckSession(Generation, UserId: Session.UserId)
        self.Session?.DisplayName = Name; self.Bio = Bio
        try PersistSession()
    }

    func LoadMessages(Friend: AscendFriend) async throws {
        guard let Session else { throw AppFailure.Message("Sign in first.") }
        let Generation = SessionGeneration
        let Conversation = [Session.UserId, Friend.Id].sorted().joined(separator: "_")
        ActiveConversation = Conversation
        let Result = try await Firestore("/conversations/\(Conversation):runQuery", Method: "POST", Body: [
            "structuredQuery": ["from": [["collectionId": "messages"]],
                                "orderBy": [["field": ["fieldPath": "createdAt"], "direction": "DESCENDING"]], "limit": 100]
        ])
        try CheckSession(Generation, UserId: Session.UserId)
        let Rows = Result as? [[String: Any]] ?? []
        let Loaded = Rows.compactMap { Row -> AscendMessage? in
            guard let Document = Row["document"] as? [String: Any], let Name = Document["name"] as? String else { return nil }
            let Values = Self.DecodeFields(Document["fields"] as? [String: Any] ?? [:])
            return AscendMessage(Id: Name.components(separatedBy: "/").last ?? Name,
                                 SenderId: Values["senderId"] as? String ?? "", Text: Values["text"] as? String ?? "",
                                 CreatedAt: Values["createdAt"] as? String ?? "")
        }.reversed()
        if ActiveConversation == Conversation { Messages = Array(Loaded) }
    }

    func SendMessage(_ Text: String, To Friend: AscendFriend) async throws {
        guard let Session else { throw AppFailure.Message("Sign in first.") }
        let Generation = SessionGeneration
        let Text = Text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Text.isEmpty, Text.count <= 10000 else { throw AppFailure.Message("Enter a message under 10,000 characters.") }
        let Conversation = [Session.UserId, Friend.Id].sorted().joined(separator: "_")
        let Name = DocumentName("conversations/\(Conversation)")
        let Message = Name + "/messages/" + UUID().uuidString
        let Writes: [[String: Any]] = [
            ["update": ["name": Message, "fields": ["senderId": ["stringValue": Session.UserId], "text": ["stringValue": Text], "read": ["booleanValue": false]]],
             "updateTransforms": [["fieldPath": "createdAt", "setToServerValue": "REQUEST_TIME"]]],
            ["update": ["name": Name, "fields": ["participants": ["arrayValue": ["values": [Session.UserId, Friend.Id].sorted().map { ["stringValue": $0] }]],
                                                     "lastMessage": ["stringValue": Text], "lastMessageSenderId": ["stringValue": Session.UserId]]],
             "updateMask": ["fieldPaths": ["participants", "lastMessage", "lastMessageSenderId"]],
             "updateTransforms": [["fieldPath": "lastMessageAt", "setToServerValue": "REQUEST_TIME"],
                                  ["fieldPath": "unreadCount.\(Self.FieldSegment(Friend.Id))", "increment": ["integerValue": "1"]]]]
        ]
        _ = try await Firestore(":commit", Method: "POST", Body: ["writes": Writes])
        try CheckSession(Generation, UserId: Session.UserId)
        try await LoadMessages(Friend: Friend)
    }

    func LoadBackups() async throws {
        guard let Session else { throw AppFailure.Message("Sign in first.") }
        let Generation = SessionGeneration
        let Result = try await AscendAPI("/ascend/backups/list", Query: [URLQueryItem(name: "userId", value: Session.UserId)])
        try CheckSession(Generation, UserId: Session.UserId)
        Backups = (Result["backups"] as? [[String: Any]] ?? []).compactMap { Row in
            guard let Id = Row["id"] as? String ?? Row["backupId"] as? String else { return nil }
            return CloudSave(Id: Id, GameName: Row["gameName"] as? String ?? "Game", Name: Row["backupName"] as? String ?? "Backup", CreatedAt: Row["createdAt"] as? String ?? "")
        }
    }

    func BackupDownloadURL(_ Save: CloudSave) async throws -> String {
        guard let Session else { throw AppFailure.Message("Sign in first.") }
        let Generation = SessionGeneration
        let Result = try await AscendAPI("/ascend/backups/download/\(SafeSegment(Save.Id))", Query: [URLQueryItem(name: "userId", value: Session.UserId)])
        try CheckSession(Generation, UserId: Session.UserId)
        guard let Link = Result["downloadUrl"] as? String else { throw AppFailure.Message("The server did not return a download URL.") }
        return Link
    }

    func UploadBackup(File: URL, GameName: String, Name: String) async throws {
        guard let Session else { throw AppFailure.Message("Sign in first.") }
        let Generation = SessionGeneration
        let Boundary = "Ascendara-" + UUID().uuidString
        var Body = Data()
        for (Key, Value) in [("gameName", GameName), ("backupName", Name), ("userId", Session.UserId)] {
            Body.append(Data("--\(Boundary)\r\nContent-Disposition: form-data; name=\"\(Key)\"\r\n\r\n\(Value)\r\n".utf8))
        }
        let Filename = File.lastPathComponent.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_")
        Body.append(Data("--\(Boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(Filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        Body.append(try Data(contentsOf: File)); Body.append(Data("\r\n--\(Boundary)--\r\n".utf8))
        var Request = URLRequest(url: URL(string: "https://api.ascendara.app/ascend/backups/upload")!)
        Request.httpMethod = "POST"; Request.httpBody = Body
        Request.setValue("multipart/form-data; boundary=\(Boundary)", forHTTPHeaderField: "Content-Type")
        Request.setValue("Bearer \(try await Token())", forHTTPHeaderField: "Authorization")
        Request.setValue("11.6.0", forHTTPHeaderField: "X-Ascendara-Version")
        _ = try await Send(Request)
        try CheckSession(Generation, UserId: Session.UserId)
        try await LoadBackups()
    }

    private func SaveSession(_ Object: [String: Any], Email: String) throws {
        guard let Id = Object["localId"] as? String, let Token = Object["idToken"] as? String,
              let Refresh = Object["refreshToken"] as? String else { throw AppFailure.Message("The sign-in response was incomplete.") }
        Session = AccountSession(UserId: Id, Email: Email, DisplayName: Object["displayName"] as? String ?? Email,
                                 IdToken: Token, RefreshToken: Refresh,
                                 ExpiresAt: Date().addingTimeInterval(Double(Object["expiresIn"] as? String ?? "3600") ?? 3600), ProjectId: ProjectId)
        try PersistSession()
    }
    private func PersistSession() throws {
        guard let Session else { return }
        try WriteSecret(String(decoding: JSONEncoder().encode(Session), as: UTF8.self), SessionKey)
    }
    private func Token() async throws -> String {
        guard let Session else { throw AppFailure.Message("Sign in to access Ascend.") }
        let Generation = SessionGeneration
        if Session.ExpiresAt.timeIntervalSinceNow > 60 { return Session.IdToken }
        guard !APIKey.isEmpty else { throw AppFailure.Message("Enter your Firebase client API key in Account configuration.") }
        var Components = URLComponents(string: "https://securetoken.googleapis.com/v1/token")!
        Components.queryItems = [URLQueryItem(name: "key", value: APIKey)]
        var Request = URLRequest(url: Components.url!)
        Request.httpMethod = "POST"
        Request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var Form = URLComponents()
        Form.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"), URLQueryItem(name: "refresh_token", value: Session.RefreshToken)]
        Request.httpBody = Form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        guard let Object = try await Send(Request) as? [String: Any], let Token = Object["id_token"] as? String else {
            throw AppFailure.Message("Your sign-in expired. Sign out and sign in again.")
        }
        try CheckSession(Generation, UserId: Session.UserId)
        self.Session?.IdToken = Token
        self.Session?.RefreshToken = Object["refresh_token"] as? String ?? Session.RefreshToken
        self.Session?.ExpiresAt = Date().addingTimeInterval(Double(Object["expires_in"] as? String ?? "3600") ?? 3600)
        try PersistSession()
        return Token
    }
    private func Auth(_ Method: String, Body: [String: Any]) async throws -> [String: Any] {
        guard !APIKey.isEmpty else { throw AppFailure.Message("This source checkout does not include Firebase credentials. Set the client API key and project ID in Account configuration.") }
        var Components = URLComponents(string: "https://identitytoolkit.googleapis.com/v1/\(Method)")!
        Components.queryItems = [URLQueryItem(name: "key", value: APIKey)]
        var Request = URLRequest(url: Components.url!)
        Request.httpMethod = "POST"; Request.httpBody = try JSONSerialization.data(withJSONObject: Body)
        Request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await Send(Request) as? [String: Any] ?? [:]
    }
    private func Firestore(_ Path: String, Method: String = "GET", Body: [String: Any]? = nil) async throws -> Any {
        guard let Session else { throw AppFailure.Message("Sign in first.") }
        let Generation = SessionGeneration
        guard ProjectId.range(of: "^[a-z][a-z0-9-]{4,61}[a-z0-9]$", options: .regularExpression) != nil else {
            throw AppFailure.Message("Enter a valid Firebase project ID in Account configuration.")
        }
        let URL = URL(string: "https://firestore.googleapis.com/v1/projects/\(ProjectId)/databases/(default)/documents" + Path)!
        var Request = URLRequest(url: URL)
        Request.httpMethod = Method
        Request.setValue("Bearer \(try await Token())", forHTTPHeaderField: "Authorization")
        if let Body {
            Request.httpBody = try JSONSerialization.data(withJSONObject: Body)
            Request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let Result = try await Send(Request, MissingIsEmpty: Method == "GET")
        try CheckSession(Generation, UserId: Session.UserId)
        return Result
    }
    private func ReadDocument(_ Path: String) async throws -> [String: Any] {
        let Result = try await Firestore("/" + Path) as? [String: Any] ?? [:]
        return Self.DecodeFields(Result["fields"] as? [String: Any] ?? [:])
    }
    private func DocumentName(_ Path: String) -> String { "projects/\(ProjectId)/databases/(default)/documents/" + Path }
    private func SafeSegment(_ Text: String) -> String { Text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
    private func AscendAPI(_ Path: String, Query: [URLQueryItem] = []) async throws -> [String: Any] {
        guard let Session else { throw AppFailure.Message("Sign in first.") }
        let Generation = SessionGeneration
        var Components = URLComponents(string: "https://api.ascendara.app" + Path)!
        Components.queryItems = Query
        var Request = URLRequest(url: Components.url!)
        Request.setValue("Bearer \(try await Token())", forHTTPHeaderField: "Authorization")
        Request.setValue("11.6.0", forHTTPHeaderField: "X-Ascendara-Version")
        let Result = try await Send(Request) as? [String: Any] ?? [:]
        try CheckSession(Generation, UserId: Session.UserId)
        return Result
    }
    private func Send(_ Request: URLRequest, MissingIsEmpty: Bool = false) async throws -> Any {
        var Request = Request; Request.timeoutInterval = 35
        let (Data, Response) = try await Network.data(for: Request)
        guard let HTTP = Response as? HTTPURLResponse else { throw AppFailure.Message("The server returned an invalid response.") }
        if HTTP.statusCode == 404 && MissingIsEmpty { return [String: Any]() }
        let Object = try? JSONSerialization.jsonObject(with: Data)
        guard (200..<300).contains(HTTP.statusCode) else {
            let Fields = Object as? [String: Any] ?? [:]
            let Message = (Fields["error"] as? [String: Any])?["message"] as? String ?? Fields["error"] as? String ?? "Account request failed (HTTP \(HTTP.statusCode))."
            throw AppFailure.Message(Message)
        }
        guard let Object else { throw AppFailure.Message("The account server returned an unreadable response.") }
        return Object
    }
    static func FieldSegment(_ Value: String) -> String {
        "`" + Value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`") + "`"
    }
    static func DecodeFields(_ Fields: [String: Any]) -> [String: Any] {
        Fields.mapValues { Raw -> Any in
            guard let Value = Raw as? [String: Any] else { return NSNull() }
            if let Text = Value["stringValue"] { return Text }
            if let Timestamp = Value["timestampValue"] { return Timestamp }
            if let Boolean = Value["booleanValue"] { return Boolean }
            if let Integer = Value["integerValue"] as? String { return Int(Integer) ?? 0 }
            if let Number = Value["doubleValue"] { return Number }
            if let Map = Value["mapValue"] as? [String: Any] { return DecodeFields(Map["fields"] as? [String: Any] ?? [:]) }
            if let Array = Value["arrayValue"] as? [String: Any] {
                return (Array["values"] as? [[String: Any]] ?? []).map { DecodeFields(["Value": $0])["Value"] ?? NSNull() }
            }
            return NSNull()
        }
    }
}
