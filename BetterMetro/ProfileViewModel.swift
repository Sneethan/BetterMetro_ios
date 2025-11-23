import Foundation
import Combine
import SwiftData

@MainActor
final class ProfileViewModel: ObservableObject {
    // Published state consumed by ProfileView
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var accountData: AccountData?
    @Published var historyItems: [HistoryItem] = []
    @Published var isRefreshing: Bool = false
    
    // Hold onto the current credentials
    private var credentials: GreencardCredentials?
    private let service = GreencardService.shared
    
    init() {}
    
    // Computed properties for easy access in views
    var accountName: String {
        accountData?.account.fullName ?? "Unknown"
    }
    
    var balance: String {
        accountData?.card.balanceInDollars ?? "$0.00"
    }
    
    var pendingBalance: String {
        accountData?.card.pendingBalanceInDollars ?? "$0.00"
    }
    
    var cardNumber: String {
        accountData?.card.printedCardNumber ?? "Unknown"
    }
    
    // Called when credentials are updated
    func updateCredentials(_ creds: GreencardCredentials) {
        credentials = creds
        Task {
            await loadData()
        }
    }
    
    // Load all account data
    func loadData() async {
        guard let creds = credentials else {
            errorMessage = "No credentials available"
            return
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let (account, history) = try await fetchAccountAndHistoryDetached(creds)
            self.accountData = account
            self.historyItems = history

        } catch {
            if isCancellation(error) { return }
            // Only surface the error if we have no usable data; otherwise keep showing the last-good snapshot.
            if accountData == nil {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // Refresh data (for pull-to-refresh)
    func refresh() async {
        guard let creds = credentials else { return }
        
        isRefreshing = true
        errorMessage = nil
        defer {
            isRefreshing = false
            isLoading = false
        }
        
        do {
            let (account, history) = try await fetchAccountAndHistoryDetached(creds)
            self.accountData = account
            self.historyItems = history
            
        } catch {
            if isCancellation(error) { return }
            // Preserve existing data if refresh fails
            if accountData == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Retry once on URLSession-level cancellation (-999) while still respecting cooperative task cancellation.
    private func fetchWithRetry<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch is CancellationError {
            // If the parent task was actually cancelled, propagate.
            if Task.isCancelled { throw CancellationError() }
            // Otherwise treat session cancel (-999) as transient and retry once.
            return try await operation()
        }
    }

    /// Run account + history fetch in detached child tasks so SwiftUI refresh cancellation doesn't nuke the requests.
    private func fetchAccountAndHistoryDetached(_ creds: GreencardCredentials) async throws -> (AccountData, [HistoryItem]) {
        let accountTask = Task.detached(priority: .userInitiated) {
            try await self.fetchWithRetry { try await self.service.fetchAccountData(credentials: creds) }
        }
        let historyTask = Task.detached(priority: .userInitiated) {
            try await self.fetchWithRetry { try await self.service.fetchHistory(credentials: creds) }
        }

        let account = try await accountTask.value
        let history = try await historyTask.value
        return (account, history)
    }
    
    // Legacy method for compatibility
    func reload() {
        Task {
            await loadData()
        }
    }

    // Treat URLSession cancelled errors the same way as Task cancellation
    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
        return false
    }
}
