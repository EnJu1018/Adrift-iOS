import Foundation

final class DiaryService {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func fetchDiaries() async throws -> [Diary] {
        let response: APIResponse<DiaryListData> = try await client.request("/diaries")
        guard let diaries = response.data?.diaries else { throw APIError.missingData }
        return diaries
    }

    func fetchDiary(id: String) async throws -> Diary {
        let response: APIResponse<DiaryDetailData> = try await client.request("/diaries/\(id)")
        guard let diary = response.data?.diary else { throw APIError.missingData }
        return diary
    }

    func explore(latitude: Double, longitude: Double, radius: Int) async throws -> [Diary] {
        let response: APIResponse<[Diary]> = try await client.request("/diaries/explore", queryItems: [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude)),
            URLQueryItem(name: "radius", value: String(radius))
        ])
        guard let diaries = response.data else { throw APIError.missingData }
        return diaries
    }

    func updateDiary(id: String, request: UpdateDiaryRequest) async throws -> Diary {
        let response: APIResponse<DiaryDetailData> = try await client.request(
            "/diaries/\(id)", method: .patch, body: request
        )
        guard let diary = response.data?.diary else { throw APIError.missingData }
        return diary
    }

    func deleteDiary(id: String) async throws {
        let _: APIResponse<EmptyResponse> = try await client.request("/diaries/\(id)", method: .delete)
    }

    func createDiary(_ request: CreateDiaryRequest) async throws -> Diary {
        let fields: [String: String] = [
            "title": request.title,
            "text": request.text,
            "moodType": request.mood.apiValue,
            "moodIntensity": "\(request.intensity)",
            "visibility": request.visibility.rawValue,
            "lat": "\(request.latitude)",
            "lng": "\(request.longitude)",
            "placeName": request.placeName,
            "locationAccuracy": request.locationAccuracy
        ]
        var files: [MultipartFile] = []
        if let imageData = request.imageData {
            guard imageData.count <= 5 * 1024 * 1024 else {
                throw APIError.server(message: "圖片不可超過 5 MB", statusCode: 400)
            }
            files.append(
                MultipartFile(
                    fieldName: "image",
                    fileName: "adrift-diary-\(UUID().uuidString).\(request.imageMimeType == "image/png" ? "png" : request.imageMimeType == "image/webp" ? "webp" : "jpg")",
                    mimeType: request.imageMimeType ?? "image/jpeg",
                    data: imageData
                )
            )
        }

        let response: APIResponse<DiaryDetailData> = try await client.multipart("/diaries", fields: fields, files: files)
        guard let diary = response.data?.diary else { throw APIError.missingData }
        return diary
    }
}

struct DiaryDetailData: Decodable {
    let diary: Diary
}

struct UpdateDiaryRequest: Encodable {
    let title: String
    let content: String
    let moodType: String
    let moodIntensity: Int
    let visibility: DiaryVisibility
    let currentLocation: CurrentDiaryLocation
}

struct CurrentDiaryLocation: Encodable {
    let lat: Double
    let lng: Double
    let accuracyType: String
}
