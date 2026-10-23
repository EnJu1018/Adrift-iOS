import CoreLocation
import SwiftUI

@MainActor
final class PlaceNameResolver {
    static let shared = PlaceNameResolver()
    private var cache: [String: String] = [:]
    private var pending: [String: Task<String, Never>] = [:]

    func name(for coordinate: CLLocationCoordinate2D, fallback: String?) async -> String {
        if let fallback, fallback.range(of: "[\\p{Han}]+[市縣區鄉鎮]", options: .regularExpression) != nil {
            return fallback
        }
        let key = String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
        if let cached = cache[key] { return cached }
        if let task = pending[key] { return await task.value }
        let task = Task<String, Never> {
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let places = try? await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_TW")),
               let place = places.first,
               let city = place.locality ?? place.administrativeArea,
               city.range(of: "[\\p{Han}]", options: .regularExpression) != nil {
                let district = place.subLocality ?? ""
                let name = city + (city == district ? "" : district)
                cache[key] = name
                return name
            }
            // Never expose coordinates or an untranslated geocoder string as a city label.
            if let fallback, fallback.range(of: "[\\p{Han}]", options: .regularExpression) != nil {
                return fallback
            }
            return "地點暫時無法取得"
        }
        pending[key] = task
        let result = await task.value
        pending[key] = nil
        return result
    }
}

struct DiaryPlaceLabel: View {
    let diary: Diary
    @State private var name = "地點載入中"

    var body: some View {
        Label(name, systemImage: "mappin.and.ellipse")
            .font(.caption)
            .foregroundStyle(.secondary)
            .task(id: diary.id) {
                guard let coordinate = diary.coordinate else {
                    name = "未提供地點"
                    return
                }
                name = await PlaceNameResolver.shared.name(for: coordinate, fallback: diary.location.placeName)
            }
    }
}
