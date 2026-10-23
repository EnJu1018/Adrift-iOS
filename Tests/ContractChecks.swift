import Foundation
import CoreLocation

// URLProtocol intercepts every request. These fixtures never enter the App or MongoDB.
final class ContractProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
struct ContractChecks {
    static let user: [String: Any] = ["_id": "user-a", "name": "測試使用者", "email": "a@example.test", "userCode": "user_a", "avatar": "/uploads/avatars/a.jpg", "createdAt": "2026-09-10T10:00:00.123Z"]
    static let diary: [String: Any] = [
        "_id": "diary-a", "title": "臺北", "text": "日記內容", "mood": ["type": "nostalgic", "intensity": 4],
        "visibility": "friends", "user": user, "imageUrl": "/uploads/a.jpg",
        "location": ["type": "Point", "coordinates": [121.5654, 25.0330], "placeName": "臺北市"],
        "createdAt": "2026-09-10T10:00:00.123Z", "canEdit": true, "editExpiresAt": "2026-09-10T11:00:00Z"
    ]

    static func stub(_ path: String, method: String = "GET", data: Any? = nil, status: Int = 200,
                     message: String = "成功", token: String? = "contract-token", inspect: ((URLRequest) throws -> Void)? = nil) {
        ContractProtocol.handler = { request in
            precondition(request.url!.path == "/api" + path, "Wrong endpoint: \(request.url!.path)")
            precondition(request.httpMethod == method)
            precondition(request.value(forHTTPHeaderField: "Authorization") == token.map { "Bearer \($0)" })
            try inspect?(request)
            var payload: [String: Any] = ["success": status < 400, "message": message]
            if let data { payload["data"] = data }
            return (status, try JSONSerialization.data(withJSONObject: payload))
        }
    }

    static func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }

    static func main() async throws {
        let store = TokenStore(service: "com.adrift.contract.\(UUID().uuidString)")
        defer { store.clear() }
        try store.save("contract-token")
        precondition(store.read() == "contract-token")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ContractProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = APIClient(session: session, tokenStore: store)
        let diaries = DiaryService(client: client)
        let friends = FriendService(client: client)
        let users = UserService(client: client)
        let auth = AuthService(client: client, tokenStore: store)

        stub("/auth/register", method: "POST", data: ["token": "contract-token", "user": user], token: nil) { request in
            let json = try JSONSerialization.jsonObject(with: body(request)) as! [String: String]
            precondition(json["userCode"] == "user_a")
        }
        let registered = try await auth.register(name: "測試使用者", email: "a@example.test", password: "test-password", userCode: "user_a")
        precondition(registered.user.id == "user-a" && store.read() == registered.token)
        stub("/auth/login", method: "POST", data: ["token": "contract-token", "user": user], token: nil)
        let loggedIn = try await auth.login(email: "a@example.test", password: "test-password")
        precondition(loggedIn.user.avatarUrl == "/uploads/avatars/a.jpg")
        stub("/users/me", data: user)
        let me = try await auth.fetchCurrentUser()
        precondition(me.createdAt != nil && me.email == "a@example.test")

        stub("/diaries", data: ["diaries": [diary]])
        let list = try await diaries.fetchDiaries()
        let decoded = list[0]
        precondition(decoded.id == "diary-a" && decoded.author?.id == "user-a")
        precondition(decoded.mood.type == .nostalgic && decoded.visibility == .friends)
        precondition(decoded.coordinate!.latitude == 25.033 && decoded.coordinate!.longitude == 121.5654)
        precondition(decoded.createdAt != nil && decoded.editExpiresAt != nil && decoded.canEdit)
        precondition(decoded.imageURLs[0].absoluteString == "https://adrifttw.com/api/uploads/a.jpg")
        stub("/diaries/diary-a", data: ["diary": diary])
        let detail = try await diaries.fetchDiary(id: "diary-a")
        precondition(detail == decoded)

        var explore = diary
        explore.removeValue(forKey: "text")
        explore.removeValue(forKey: "user")
        explore["content"] = "探索內容"
        explore["author"] = user
        explore["location"] = ["lat": 25.033, "lng": 121.5654, "placeName": "臺北市"]
        explore["visibility"] = "public"
        stub("/diaries/explore", data: [explore]) { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.contains(URLQueryItem(name: "radius", value: "5000")))
        }
        let nearby = try await diaries.explore(latitude: 25.033, longitude: 121.5654, radius: 5000)
        precondition(nearby[0].text == "探索內容" && nearby[0].coordinate!.longitude == 121.5654)

        stub("/diaries", method: "POST", data: ["diary": diary]) { request in
            let multipart = String(decoding: body(request), as: UTF8.self)
            precondition(request.value(forHTTPHeaderField: "Content-Type")!.contains("multipart/form-data"))
            for field in ["title", "text", "moodType", "moodIntensity", "visibility", "lat", "lng", "image", "locationAccuracy"] {
                precondition(multipart.contains("name=\"\(field)\""))
            }
            precondition(multipart.contains("nostalgic") && multipart.contains("approximate"))
        }
        _ = try await diaries.createDiary(CreateDiaryRequest(title: "臺北", text: "內容", mood: .nostalgic, intensity: 4,
            visibility: .friends, latitude: 25.033, longitude: 121.5654, placeName: "臺北市", imageData: Data([1, 2]),
            imageMimeType: "image/jpeg", locationAccuracy: "approximate"))
        stub("/diaries/diary-a", method: "PATCH", data: ["diary": diary]) { request in
            let json = try JSONSerialization.jsonObject(with: body(request)) as! [String: Any]
            precondition(json["moodType"] as? String == "other")
            precondition(json["visibility"] as? String == "private")
            let location = json["currentLocation"] as! [String: Any]
            precondition(location["lat"] as? Double == 25.033)
            precondition(json["location"] == nil && json["imageUrl"] == nil)
        }
        _ = try await diaries.updateDiary(id: "diary-a", request: UpdateDiaryRequest(title: "修正", content: "內容", moodType: "other",
            moodIntensity: 2, visibility: .private, currentLocation: CurrentDiaryLocation(lat: 25.033, lng: 121.5654, accuracyType: "precise")))
        stub("/diaries/diary-a", method: "DELETE")
        try await diaries.deleteDiary(id: "diary-a")

        stub("/friends", data: [user])
        let listFriends = try await friends.fetchFriends()
        precondition(listFriends[0].avatarUrl == "/uploads/avatars/a.jpg")
        stub("/friends/requests", data: [["requestId": "request-a", "from": user, "createdAt": "2026-09-10T10:00:00Z"]])
        let received = try await friends.fetchRequests()
        precondition(received[0].id == "request-a" && received[0].from?.id == "user-a")
        stub("/friends/requests/sent", data: [["requestId": "request-a", "to": user]])
        let sent = try await friends.fetchSentRequests()
        precondition(sent[0].to?.id == "user-a")
        var search = user
        search["friendshipStatus"] = "sent_request"
        stub("/users/search", data: search)
        let found = try await friends.searchUser(userCode: "user_a")
        precondition(found.friendshipStatus == "sent_request")
        stub("/friends/request", method: "POST", status: 201)
        try await friends.sendFriendRequest(targetUserId: "user-a")
        stub("/friends/requests/request-a/accept", method: "POST")
        try await friends.acceptRequest(id: "request-a")
        stub("/friends/requests/request-a/reject", method: "POST")
        try await friends.rejectRequest(id: "request-a")
        stub("/friends/requests/request-a/cancel", method: "DELETE")
        try await friends.cancelRequest(id: "request-a")
        stub("/friends/user-a", method: "DELETE")
        try await friends.removeFriend(id: "user-a")

        for field in ["name", "email"] {
            stub("/users/me/\(field)", method: "PATCH", data: ["user": user])
            _ = try await users.updateProfile(field: field, values: [field: "test"])
        }
        stub("/users/me/avatar", method: "PATCH", data: ["user": user]) { request in
            precondition(String(decoding: body(request), as: UTF8.self).contains("name=\"avatar\""))
        }
        _ = try await users.uploadAvatar(data: Data([1, 2]), mimeType: "image/jpeg")
        stub("/users/me/avatar", method: "DELETE", data: ["user": user])
        _ = try await users.removeAvatar()
        stub("/users/me/password", method: "PATCH", data: [:])
        try await users.updatePassword(["currentPassword": "test", "newPassword": "test-new", "confirmPassword": "test-new"])

        stub("/users/me/password", method: "PATCH", status: 401, message: "目前密碼錯誤")
        do {
            try await users.updatePassword([:])
            preconditionFailure("Expected password rejection")
        } catch APIError.server(let message, let status) {
            precondition(message == "目前密碼錯誤" && status == 401)
            precondition(store.read() == "contract-token")
        }
        stub("/diaries/diary-a", status: 404, message: "找不到日記")
        do {
            _ = try await diaries.fetchDiary(id: "diary-a")
            preconditionFailure("Expected visibility rejection")
        } catch APIError.server(let message, let status) { precondition(status == 404 && message == "找不到日記") }
        ContractProtocol.handler = { request in (502, Data("Bad gateway".utf8)) }
        do {
            _ = try await diaries.fetchDiaries()
            preconditionFailure("Expected server error")
        } catch APIError.server(let message, let status) { precondition(status == 502 && message.contains("伺服器")) }
        stub("/diaries", data: ["diaries": "invalid"])
        do {
            _ = try await diaries.fetchDiaries()
            preconditionFailure("Expected decoding error")
        } catch APIError.decoding {}
        precondition(APIError.server(message: "Validation failed", statusCode: 400).localizedDescription == "資料格式不正確，請檢查輸入內容")

        for value in ["calm", "joy", "sad", "wonder", "anxious", "confused", "nostalgic", "other"] {
            precondition(MoodKind.fromAPI(value).apiValue == value)
        }
        for path in ["/uploads/a.jpg", "uploads/a.jpg", "/api/uploads/a.jpg"] {
            precondition(APIConfig.assetURL(from: path)!.absoluteString == "https://adrifttw.com/api/uploads/a.jpg")
        }
        precondition(APIConfig.assetURL(from: "https://cdn.example.test/a.jpg")!.host == "cdn.example.test")
        precondition(APIConfig.assetURL(from: "blob:local") == nil)
        precondition(APIConfig.assetURL(from: "") == nil)
        precondition(APIConfig.assetURL(from: "/uploads/a.jpg", baseURL: URL(string: "http://localhost:5000")!)!.absoluteString == "http://localhost:5000/uploads/a.jpg")
        auth.logout()
        precondition(store.read() == nil)
        print("PASS: auth/Keychain/Bearer, diary CRUD/explore/multipart, friends, profile, errors, mood and image URL contracts")
    }
}
