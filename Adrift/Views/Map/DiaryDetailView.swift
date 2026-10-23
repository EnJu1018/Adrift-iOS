import SwiftUI

struct DiaryDetailView: View {
    let diary: Diary
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var map: MapDiaryViewModel
    @EnvironmentObject private var refresh: AppRefreshManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var current: Diary?
    @State private var error: String?
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var busy = false
    @State private var loading = false
    private let service = DiaryService()

    var body: some View {
        NavigationStack {
            AppPageScrollContainer {
                if let current {
                    DiaryCard(diary: current)
                    if current.author?.id == auth.currentUser?.id {
                        HStack {
                            Button { editing = true } label: { Label("編輯", systemImage: "pencil") }
                                .disabled(!current.canEdit || (current.editExpiresAt ?? .distantPast) < Date() || busy)
                            Spacer()
                            Button(role: .destructive) { confirmingDelete = true } label: { Label("刪除", systemImage: "trash") }
                                .disabled(busy)
                        }
                        .buttonStyle(.bordered)
                    }
                } else if loading { ProgressView("讀取日記...") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .adriftPageNavigation("日記詳情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("關閉") { dismiss() } }
            }
            .task { await load() }
            .onChange(of: map.diaries) { _, diaries in
                guard current != nil else { return }
                if let updated = diaries.first(where: { $0.id == diary.id }) {
                    current = updated
                } else {
                    current = nil
                    Task { await load() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await load() } }
            }
            .sheet(isPresented: $editing) {
                if let current {
                    EditDiaryView(diary: current) { updated in
                        self.current = updated
                        map.upsert(updated)
                        Task { await refresh.refreshIfNeeded(scopes: [.diaries, .explore], force: true) }
                    }
                }
            }
            .confirmationDialog("確定刪除這篇日記？此操作無法復原。", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("刪除日記", role: .destructive) { Task { await delete() } }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func load() async {
        guard !loading, !busy else { return }
        loading = true
        let revision = map.revision
        defer { loading = false }
        do {
            let result = try await service.fetchDiary(id: diary.id)
            guard revision == map.revision else {
                loading = false
                await load()
                return
            }
            current = result
            error = nil
        } catch {
            current = nil
            self.error = error.localizedDescription
            if case APIError.server(_, let status) = error, status == 404 || status == 403 {
                map.removeDiary(id: diary.id)
            }
        }
    }

    private func delete() async {
        busy = true
        defer { busy = false }
        do {
            try await service.deleteDiary(id: diary.id)
            current = nil
            map.removeDiary(id: diary.id)
            dismiss()
            await refresh.refreshIfNeeded(scopes: [.diaries, .explore], force: true)
        } catch { self.error = error.localizedDescription }
    }
}

private struct EditDiaryView: View {
    let diary: Diary
    let onSave: (Diary) -> Void
    @EnvironmentObject private var map: MapDiaryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var content: String
    @State private var mood: MoodKind
    @State private var intensity: Int
    @State private var visibility: DiaryVisibility
    @State private var busy = false
    @State private var error: String?

    init(diary: Diary, onSave: @escaping (Diary) -> Void) {
        self.diary = diary
        self.onSave = onSave
        _title = State(initialValue: diary.title)
        _content = State(initialValue: diary.text)
        _mood = State(initialValue: diary.mood.type)
        _intensity = State(initialValue: diary.mood.intensity)
        _visibility = State(initialValue: diary.visibility)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("日記") {
                    TextField("標題", text: $title)
                    TextEditor(text: $content).frame(minHeight: 160)
                    DiaryPlaceLabel(diary: diary)
                }
                Section("心情與可見性") {
                    Picker("心情", selection: $mood) {
                        ForEach(MoodKind.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper("強度：\(intensity)", value: $intensity, in: 1...5)
                    Picker("可見性", selection: $visibility) {
                        ForEach(DiaryVisibility.allCases) { Text($0.label).tag($0) }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("編輯日記")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if busy { ProgressView() } else { Label("儲存", systemImage: "checkmark") }
                    }
                    .disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }

    private func save() async {
        guard !busy else { return }
        guard title.utf16.count <= 50, content.utf16.count <= 2000 else {
            error = "標題最多 50 字，內容最多 2000 字"
            return
        }
        busy = true
        defer { busy = false }
        do {
            let location = try await map.locationManager.freshLocation()
            let updated = try await DiaryService().updateDiary(id: diary.id, request: UpdateDiaryRequest(
                title: title, content: content, moodType: mood.apiValue, moodIntensity: intensity,
                visibility: visibility, currentLocation: CurrentDiaryLocation(
                    lat: location.coordinate.latitude, lng: location.coordinate.longitude,
                    accuracyType: map.locationManager.accuracyType
                )
            ))
            onSave(updated)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
