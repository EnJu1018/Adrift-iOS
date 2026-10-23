import Foundation

extension Notification.Name {
    static let adriftSessionExpired = Notification.Name("adrift.sessionExpired")
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum APIError: LocalizedError {
    case invalidURL
    case missingData
    case server(message: String, statusCode: Int)
    case decoding
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "API URL 設定不正確"
        case .missingData:
            return "伺服器沒有回傳資料"
        case .server(let message, let status):
            if message.range(of: "[\\p{Han}]", options: .regularExpression) != nil { return message }
            switch status {
            case 400: return "資料格式不正確，請檢查輸入內容"
            case 401: return "驗證失敗，請確認登入狀態與密碼"
            case 403: return "目前沒有權限執行這個操作"
            case 404: return "找不到這筆資料或服務"
            case 409: return "資料狀態已改變，請稍後再試"
            case 413: return "上傳的檔案太大"
            case 429: return "操作過於頻繁，請稍後再試"
            default: return "伺服器暫時無法處理請求"
            }
        case .decoding:
            return "資料格式暫時無法讀取"
        case .transport:
            return "網路連線失敗，請稍後再試"
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let tokenStore: TokenStore
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, tokenStore: TokenStore = .shared) {
        self.session = session
        self.tokenStore = tokenStore
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: value) {
                return date
            }
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO date")
        }
    }

    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        body: Encodable? = nil,
        authorized: Bool = true
    ) async throws -> APIResponse<T> {
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized, let token = tokenStore.read() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return try await perform(request)
    }

    func multipart<T: Decodable>(
        _ path: String,
        fields: [String: String],
        files: [MultipartFile] = [],
        method: HTTPMethod = .post,
        authorized: Bool = true
    ) async throws -> APIResponse<T> {
        let url = APIConfig.baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.httpMethod = method.rawValue
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized, let token = tokenStore.read() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = makeMultipartBody(fields: fields, files: files, boundary: boundary)

        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> APIResponse<T> {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.server(message: "伺服器回應不正確", statusCode: 0)
        }

        // A previous account's in-flight request must never populate a new session.
        if let authorization = request.value(forHTTPHeaderField: "Authorization"),
           authorization != tokenStore.read().map({ "Bearer \($0)" }) {
            throw CancellationError()
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let payload = try? JSONDecoder().decode(APIErrorPayload.self, from: data)
            let message = payload?.message ?? "伺服器暫時無法處理請求（\(httpResponse.statusCode)）"
            if httpResponse.statusCode == 401,
               request.value(forHTTPHeaderField: "Authorization") != nil,
               ["請先登入", "登入狀態已失效，請重新登入"].contains(message) {
                await MainActor.run {
                    NotificationCenter.default.post(name: .adriftSessionExpired, object: nil)
                }
            }
            throw APIError.server(message: message, statusCode: httpResponse.statusCode)
        }

        do {
            let decoded = try decoder.decode(APIResponse<T>.self, from: data)
            if !(200..<300).contains(httpResponse.statusCode) || decoded.success == false {
                throw APIError.server(message: decoded.message, statusCode: httpResponse.statusCode)
            }
            return decoded
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.decoding
        }
    }

    private func makeMultipartBody(fields: [String: String], files: [MultipartFile], boundary: String) -> Data {
        var data = Data()
        for (key, value) in fields {
            data.append("--\(boundary)\r\n")
            data.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            data.append("\(value)\r\n")
        }
        for file in files {
            data.append("--\(boundary)\r\n")
            data.append("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\r\n")
            data.append("Content-Type: \(file.mimeType)\r\n\r\n")
            data.append(file.data)
            data.append("\r\n")
        }
        data.append("--\(boundary)--\r\n")
        return data
    }
}

private struct APIErrorPayload: Decodable {
    let message: String
}

struct MultipartFile {
    let fieldName: String
    let fileName: String
    let mimeType: String
    let data: Data
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        encodeClosure = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
