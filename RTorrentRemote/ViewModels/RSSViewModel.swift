import Foundation

@MainActor
final class RSSViewModel: ObservableObject {
    @Published var feeds: [RSSFeed] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var newFeedURL: String = ""

    private weak var appState: AppState?

    func attach(to appState: AppState) {
        self.appState = appState
    }

    func refresh() async {
        guard let client = appState?.client else { return }
        isLoading = true
        do {
            feeds = try await client.fetchRSSFeeds()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func addFeed() {
        guard let client = appState?.client, !newFeedURL.isEmpty else { return }
        let url = newFeedURL
        Task {
            do {
                try await client.addRSSFeed(url: url)
                newFeedURL = ""
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func removeFeed(_ feed: RSSFeed) {
        guard let client = appState?.client else { return }
        Task {
            do {
                try await client.removeRSSFeed(url: feed.url)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
