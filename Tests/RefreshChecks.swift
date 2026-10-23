import Foundation

// Minimal spies for the manager's collaborators; shipping view models are unchanged.
@MainActor final class AuthViewModel {
    var currentUser: Int? = 1
    var calls = 0
    func refreshCurrentUser(silently: Bool) async { calls += 1 }
}

@MainActor final class FriendsViewModel {
    var calls = 0
    func load(silently: Bool) async { calls += 1 }
}

@MainActor final class MapDiaryViewModel {
    var calls = 0
    var exploreCalls = 0
    var shouldSuspend = false
    var continuation: CheckedContinuation<Void, Never>?
    func loadDiaries(silently: Bool) async {
        calls += 1
        if shouldSuspend {
            await withCheckedContinuation { continuation = $0 }
        }
    }
    func loadExplore() async { exploreCalls += 1 }
}

@main struct RefreshChecks {
    @MainActor static func main() async {
        let auth = AuthViewModel()
        let map = MapDiaryViewModel()
        let friends = FriendsViewModel()
        let manager = AppRefreshManager()
        manager.configure(authViewModel: auth, mapViewModel: map, friendsViewModel: friends)
        await manager.refreshIfNeeded()
        precondition(map.calls == 1 && map.exploreCalls == 1 && friends.calls == 1)
        precondition(auth.calls == 0)
        await manager.refreshIfNeeded()
        precondition(map.calls == 1 && friends.calls == 1, "Immediate page entry must be throttled")

        map.shouldSuspend = true
        let first = Task { await manager.refreshIfNeeded(scopes: [.diaries], force: true) }
        while map.continuation == nil { await Task.yield() }
        await manager.refreshIfNeeded(scopes: [.diaries, .explore], force: true)
        await manager.refreshIfNeeded(scopes: [.diaries], force: true)
        precondition(map.calls == 2, "No duplicate in-flight request")
        map.shouldSuspend = false
        map.continuation!.resume()
        await first.value
        precondition(map.calls == 3 && map.exploreCalls == 2, "Mutation refresh must run after an older request, once")
        precondition(!manager.isRefreshing)
        await manager.refreshIfNeeded(scopes: [.user], minimumInterval: 0)
        precondition(auth.calls == 1)
        print("PASS: initial refresh, throttling, in-flight deduplication and queued mutation refresh")
    }
}
