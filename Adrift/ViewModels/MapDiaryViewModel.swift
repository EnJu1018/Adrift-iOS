import CoreLocation
import Foundation
import MapKit
import SwiftUI

@MainActor
final class MapDiaryViewModel: ObservableObject {
    @Published var diaries: [Diary] = []
    @Published var selectedDiary: Diary?
    @Published var isLoading = false
    @Published var isCreating = false
    @Published var isLocating = false
    @Published var errorMessage: String?
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var lastLocatedAt: Date?
    @Published var exploreDiaries: [Diary] = []
    @Published var exploreRadius = 5000
    @Published var exploreError: String?
    @Published var isExploring = false
    @Published private(set) var revision = 0

    let locationManager = LocationManager()

    private let diaryService: DiaryService
    private var isRefreshing = false

    init(diaryService: DiaryService = DiaryService()) {
        self.diaryService = diaryService
    }

    func prepareLocation() {
        locationManager.requestAuthorization()
    }

    func loadDiaries(silently: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let startingRevision = revision
        let showsInitialLoading = diaries.isEmpty && !silently
        if showsInitialLoading {
            isLoading = true
            errorMessage = nil
        }

        defer {
            isRefreshing = false
            if showsInitialLoading {
                isLoading = false
            }
        }

        do {
            let nextDiaries = try await diaryService.fetchDiaries()
            guard startingRevision == revision else { return }
            let shouldSetInitialCamera = diaries.isEmpty
            diaries = nextDiaries
            if let selectedDiary {
                self.selectedDiary = diaries.first { $0.id == selectedDiary.id }
            }
            errorMessage = nil

            if shouldSetInitialCamera {
                if let coordinate = locationManager.lastLocation?.coordinate {
                    focusCamera(on: coordinate, distance: 1_600, pitch: 30, animated: false)
                } else if let first = diaries.compactMap(\.coordinate).first {
                    focusCamera(on: first, distance: 2_800, pitch: 18, animated: false)
                }
            }
        } catch {
            if !silently || diaries.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadExplore() async {
        guard !isExploring else { return }
        guard let coordinate = locationManager.lastLocation?.coordinate else {
            exploreError = locationManager.errorMessage ?? "等待目前位置"
            return
        }
        isExploring = true
        let startingRevision = revision
        let radius = exploreRadius
        defer { isExploring = false }
        do {
            let result = try await diaryService.explore(
                latitude: coordinate.latitude, longitude: coordinate.longitude, radius: radius
            )
            guard startingRevision == revision, radius == exploreRadius else { return }
            exploreDiaries = result
            exploreError = nil
        } catch {
            exploreError = error.localizedDescription
        }
    }

    func upsert(_ diary: Diary) {
        revision += 1
        if let index = diaries.firstIndex(where: { $0.id == diary.id }) {
            diaries[index] = diary
        } else {
            diaries.insert(diary, at: 0)
        }
        if selectedDiary?.id == diary.id { selectedDiary = diary }
        if let index = exploreDiaries.firstIndex(where: { $0.id == diary.id }) {
            if diary.visibility == .public {
                exploreDiaries[index] = diary
            } else {
                exploreDiaries.remove(at: index)
            }
        }
    }

    func removeDiary(id: String) {
        revision += 1
        diaries.removeAll { $0.id == id }
        exploreDiaries.removeAll { $0.id == id }
        if selectedDiary?.id == id { selectedDiary = nil }
    }

    func invalidateFriendVisibility() {
        revision += 1
        diaries.removeAll { $0.visibility == .friends }
        if selectedDiary?.visibility == .friends { selectedDiary = nil }
    }

    func selectDiary(id: String?) {
        guard let id else {
            selectedDiary = nil
            return
        }
        selectedDiary = diaries.first { $0.id == id }
    }

    func recenterOnCurrentLocation() {
        locationManager.requestAuthorization()
        isLocating = true

        if let coordinate = locationManager.lastLocation?.coordinate {
            focusCamera(on: coordinate, distance: 1_200, pitch: 35, animated: true)
            isLocating = false
            lastLocatedAt = Date()
        }
    }

    func focusCamera(
        on coordinate: CLLocationCoordinate2D,
        distance: CLLocationDistance = 1_200,
        pitch: CGFloat = 35,
        animated: Bool = true
    ) {
        let camera = MapCamera(
            centerCoordinate: coordinate,
            distance: distance,
            heading: 0,
            pitch: pitch
        )

        if animated {
            withAnimation(.smooth(duration: 0.85)) {
                cameraPosition = .camera(camera)
            }
        } else {
            cameraPosition = .camera(camera)
        }
    }

    func createDiary(
        title: String,
        text: String,
        mood: MoodKind,
        intensity: Int,
        visibility: DiaryVisibility,
        imageData: Data?,
        imageMimeType: String?
    ) async -> Bool {
        guard !isCreating else { return false }
        isCreating = true
        errorMessage = nil
        do {
            let location = try await locationManager.freshLocation()
            let coordinate = location.coordinate
            let resolvedPlace = await PlaceNameResolver.shared.name(for: coordinate, fallback: nil)
            let diary = try await diaryService.createDiary(
                CreateDiaryRequest(
                    title: title,
                    text: text,
                    mood: mood,
                    intensity: intensity,
                    visibility: visibility,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    placeName: resolvedPlace,
                    imageData: imageData,
                    imageMimeType: imageMimeType,
                    locationAccuracy: locationManager.accuracyType
                )
            )
            upsert(diary)
            selectedDiary = diary
            isCreating = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
            return false
        }
    }
}
