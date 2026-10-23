import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var map: MapDiaryViewModel
    @EnvironmentObject private var refresh: AppRefreshManager
    @State private var selected: Diary?

    var body: some View {
        NavigationStack {
            List {
                Picker("搜尋範圍", selection: $map.exploreRadius) {
                    Text("1 公里").tag(1000)
                    Text("5 公里").tag(5000)
                    Text("20 公里").tag(20000)
                    Text("50 公里").tag(50000)
                }
                if map.isExploring && map.exploreDiaries.isEmpty { ProgressView("探索中...") }
                if let error = map.exploreError { Text(error).foregroundStyle(.secondary) }
                if !map.isExploring && map.exploreDiaries.isEmpty && map.exploreError == nil {
                    ContentUnavailableView("附近沒有公開日記", systemImage: "globe.asia.australia")
                }
                ForEach(map.exploreDiaries) { diary in
                    Button { selected = diary } label: { DiaryCard(diary: diary) }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                }
            }
            .adriftPageNavigation("探索")
            .sheet(item: $selected) { DiaryDetailView(diary: $0) }
            .task { await refresh.refreshIfNeeded(scopes: [.explore]) }
            .onChange(of: map.exploreRadius) { _, _ in
                Task { await refresh.refreshIfNeeded(scopes: [.explore], force: true) }
            }
        }
    }
}
