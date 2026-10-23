import Foundation

final class UserService {
    private let authService: AuthService
    private let client: APIClient

    init(authService: AuthService = AuthService(), client: APIClient = .shared) {
        self.authService = authService
        self.client = client
    }

    func fetchCurrentUser() async throws -> User {
        try await authService.fetchCurrentUser()
    }

    func uploadAvatar(data: Data, mimeType: String) async throws -> User {
        guard data.count <= 10 * 1024 * 1024 else {
            throw APIError.server(message: "頭像不可超過 10 MB", statusCode: 400)
        }
        let file = MultipartFile(
            fieldName: "avatar",
            fileName: "avatar.\(mimeType.fileExtension)",
            mimeType: mimeType,
            data: data
        )
        let response: APIResponse<UserUpdateData> = try await client.multipart(
            "/users/me/avatar",
            fields: [:],
            files: [file],
            method: .patch
        )
        guard let user = response.data?.user else { throw APIError.missingData }
        return user
    }

    func updateProfile(field: String, values: [String: String]) async throws -> User {
        let response: APIResponse<UserUpdateData> = try await client.request(
            "/users/me/\(field)", method: .patch, body: values
        )
        guard let user = response.data?.user else { throw APIError.missingData }
        return user
    }

    func updatePassword(_ values: [String: String]) async throws {
        let _: APIResponse<EmptyResponse> = try await client.request(
            "/users/me/password", method: .patch, body: values
        )
    }

    func removeAvatar() async throws -> User {
        let response: APIResponse<UserUpdateData> = try await client.request("/users/me/avatar", method: .delete)
        guard let user = response.data?.user else { throw APIError.missingData }
        return user
    }
}

struct UserUpdateData: Decodable {
    let user: User
}

private extension String {
    var fileExtension: String {
        switch self {
        case "image/png":
            return "png"
        case "image/webp":
            return "webp"
        default:
            return "jpg"
        }
    }
}
