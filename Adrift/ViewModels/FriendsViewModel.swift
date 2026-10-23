import Foundation

@MainActor
final class FriendsViewModel: ObservableObject {
    @Published var friends: [Friend] = []
    @Published var requests: [FriendRequest] = []
    @Published var sentRequests: [FriendRequest] = []
    @Published var searchResult: SearchUserResult?
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var searchMessage: String?
    @Published private(set) var isMutating = false

    private let service: FriendService
    private var isRefreshing = false
    private var revision = 0

    init(service: FriendService = FriendService()) {
        self.service = service
    }

    func load(silently: Bool = false, force: Bool = false) async {
        if force {
            while isRefreshing {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        let startingRevision = revision
        let showsInitialLoading = friends.isEmpty && requests.isEmpty && sentRequests.isEmpty && !silently
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
            async let nextFriends = service.fetchFriends()
            async let nextRequests = service.fetchRequests()
            async let nextSentRequests = service.fetchSentRequests()
            let result = try await (nextFriends, nextRequests, nextSentRequests)
            guard startingRevision == revision else { return }
            friends = result.0
            requests = result.1
            sentRequests = result.2
            if let searchResult, !isSearching {
                self.searchResult = try await service.searchUser(userCode: searchResult.userCode)
            }
            errorMessage = nil
        } catch {
            if !silently || (friends.isEmpty && requests.isEmpty && sentRequests.isEmpty) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func search(userCode: String) async {
        let trimmed = userCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSearching = true
        searchResult = nil
        searchMessage = nil
        do {
            searchResult = try await service.searchUser(userCode: trimmed)
        } catch {
            searchMessage = error.localizedDescription
        }
        isSearching = false
    }

    func sendRequest() async {
        guard let searchResult else { return }
        await mutate {
            try await service.sendFriendRequest(targetUserId: searchResult.id)
            searchMessage = "好友邀請已送出"
        }
    }

    func accept(_ request: FriendRequest) async {
        await mutate {
            try await service.acceptRequest(id: request.id)
            revision += 1
            requests.removeAll { $0.id == request.id }
            if let friend = request.from, !friends.contains(where: { $0.id == friend.id }) {
                friends.append(friend)
            }
        }
    }

    func reject(_ request: FriendRequest) async {
        await mutate {
            try await service.rejectRequest(id: request.id)
            revision += 1
            requests.removeAll { $0.id == request.id }
        }
    }

    func remove(_ friend: Friend) async {
        await mutate {
            try await service.removeFriend(id: friend.id)
            revision += 1
            friends.removeAll { $0.id == friend.id }
        }
    }

    func cancel(_ request: FriendRequest) async {
        await mutate {
            try await service.cancelRequest(id: request.id)
            revision += 1
            sentRequests.removeAll { $0.id == request.id }
        }
    }

    private func mutate(_ action: () async throws -> Void) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await action()
            await load(silently: true, force: true)
        } catch { errorMessage = error.localizedDescription }
    }
}
