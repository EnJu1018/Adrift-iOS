import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var map: MapDiaryViewModel
    @EnvironmentObject private var refresh: AppRefreshManager
    @State private var selected: Diary?

    var body: some View {
        NavigationStack {
            List {
                if let user = auth.currentUser {
                    Section {
                        HStack {
                            AvatarView(name: user.name, avatarUrl: user.avatarUrl, size: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name).font(.headline)
                                Text("@\(user.userCode)").foregroundStyle(.secondary)
                                if let email = user.email { Text(email).font(.caption) }
                            }
                        }
                    }
                    Section("我的日記") {
                        let diaries = map.diaries.filter { $0.author?.id == user.id }
                        if diaries.isEmpty { Text("目前沒有日記").foregroundStyle(.secondary) }
                        ForEach(diaries) { diary in
                            Button { selected = diary } label: { DiaryCard(diary: diary) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .adriftPageNavigation("個人頁")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { SettingsView() } label: { Label("設定", systemImage: "gearshape") }
                }
            }
            .sheet(item: $selected) { DiaryDetailView(diary: $0) }
            .task { await refresh.refreshIfNeeded(scopes: [.user, .diaries]) }
        }
    }
}
