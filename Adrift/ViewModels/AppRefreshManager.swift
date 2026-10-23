import Foundation
import Combine

enum AppRefreshScope: Hashable {
    case user
    case diaries
    case friends
    case explore
}

@MainActor
final class AppRefreshManager: ObservableObject {
    @Published private(set) var isRefreshing = false

    private var handlers: [AppRefreshScope: (_ isInitialLoad: Bool) async -> Void] = [:]
    private var lastRefreshDates: [AppRefreshScope: Date] = [:]
    private var pendingScopes: Set<AppRefreshScope> = []

    func configure(
        authViewModel: AuthViewModel,
        mapViewModel: MapDiaryViewModel,
        friendsViewModel: FriendsViewModel
    ) {
        handlers[.user] = { [weak authViewModel] _ in
            await authViewModel?.refreshCurrentUser(silently: true)
        }
        handlers[.diaries] = { [weak mapViewModel] isInitialLoad in
            await mapViewModel?.loadDiaries(silently: !isInitialLoad)
        }
        handlers[.friends] = { [weak friendsViewModel] isInitialLoad in
            await friendsViewModel?.load(silently: !isInitialLoad)
        }
        handlers[.explore] = { [weak mapViewModel] _ in
            await mapViewModel?.loadExplore()
        }

        if authViewModel.currentUser != nil, lastRefreshDates[.user] == nil {
            lastRefreshDates[.user] = Date()
        }
    }

    func refreshIfNeeded(
        scopes: Set<AppRefreshScope> = [.user, .diaries, .friends, .explore],
        force: Bool = false,
        minimumInterval: TimeInterval = 30
    ) async {
        guard !isRefreshing else {
            if force { pendingScopes.formUnion(scopes) }
            return
        }

        let now = Date()
        let eligibleScopes = scopes.filter { scope in
            guard !force, let lastRefreshDate = lastRefreshDates[scope] else {
                return true
            }
            return now.timeIntervalSince(lastRefreshDate) >= minimumInterval
        }

        guard !eligibleScopes.isEmpty else { return }
        isRefreshing = true

        for scope in orderedScopes.filter(eligibleScopes.contains) {
            guard !Task.isCancelled else { break }
            guard let handler = handlers[scope] else { continue }
            await handler(lastRefreshDates[scope] == nil)
            lastRefreshDates[scope] = Date()
        }
        isRefreshing = false
        if !pendingScopes.isEmpty {
            let pending = pendingScopes
            pendingScopes.removeAll()
            await refreshIfNeeded(scopes: pending, force: true)
        }
    }

    private let orderedScopes: [AppRefreshScope] = [.user, .friends, .diaries, .explore]
}
