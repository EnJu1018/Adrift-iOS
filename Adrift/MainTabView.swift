import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var mapViewModel = MapDiaryViewModel()
    @StateObject private var friendsViewModel = FriendsViewModel()
    @StateObject private var refreshManager = AppRefreshManager()

    var body: some View {
        TabView {
            MapDiaryView(viewModel: mapViewModel)
                .tabItem {
                    Label("地圖", systemImage: "map")
                }

            FriendsView(viewModel: friendsViewModel)
                .tabItem {
                    Label("好友", systemImage: "person.2")
                }

            ExploreView()
                .tabItem { Label("探索", systemImage: "globe.asia.australia") }

            IntelligenceView()
                .tabItem {
                    Label("洞察", systemImage: "sparkles")
                }

            ProfileView()
                .tabItem {
                    Label("個人", systemImage: "person.crop.circle")
                }
        }
        .environmentObject(refreshManager)
        .environmentObject(mapViewModel)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.regularMaterial, for: .tabBar)
        .task {
            mapViewModel.prepareLocation()
            refreshManager.configure(
                authViewModel: authViewModel,
                mapViewModel: mapViewModel,
                friendsViewModel: friendsViewModel
            )
            await refreshManager.refreshIfNeeded(scopes: [.diaries, .friends, .explore], force: true)

            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                guard scenePhase == .active else { continue }
                await refreshManager.refreshIfNeeded(minimumInterval: 30)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                mapViewModel.prepareLocation()
                await refreshManager.refreshIfNeeded(minimumInterval: 30)
            }
        }
        .onReceive(mapViewModel.locationManager.$lastLocation) { location in
            guard location != nil else { return }
            Task { await refreshManager.refreshIfNeeded(scopes: [.explore], force: mapViewModel.exploreError != nil) }
        }
        .onChange(of: friendsViewModel.friends) { _, _ in
            mapViewModel.invalidateFriendVisibility()
            Task { await refreshManager.refreshIfNeeded(scopes: [.diaries, .explore], force: true) }
        }
        .onChange(of: authViewModel.currentUser) { _, _ in
            Task { await refreshManager.refreshIfNeeded(scopes: [.diaries, .explore], force: true) }
        }
        .onChange(of: mapViewModel.isCreating) { old, new in
            if old && !new {
                Task { await refreshManager.refreshIfNeeded(scopes: [.diaries, .explore], force: true) }
            }
        }
    }
}
