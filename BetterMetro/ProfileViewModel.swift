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
        
        do {
            self.accountData = try await service.fetchAccountData(credentials: creds)
            self.historyItems = try await service.fetchHistory(credentials: creds)
            
        } catch is CancellationError {
            // Ignore silent cancels from pull-to-refresh / navigation
            errorMessage = nil
            isLoading = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // Refresh data (for pull-to-refresh)
    func refresh() async {
        guard let creds = credentials else { return }
        
        isRefreshing = true
        errorMessage = nil
        
        do {
            self.accountData = try await service.fetchAccountData(credentials: creds)
            self.historyItems = try await service.fetchHistory(credentials: creds)
            
        } catch is CancellationError {
            // Silent ignore — prevents sudden error screen
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
        isRefreshing = false
    }
    
    // Legacy method for compatibility
    func reload() {
        Task {
            await loadData()
        }
    }
}
