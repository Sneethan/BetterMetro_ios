//
//  ContentView.swift
//  BetterMetro
//
//  Created by Ethan Hopkins on 17/11/2025.
//

import SwiftUI
import SwiftData
import SafariServices

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storedCredentials: [GreencardCredentials]
    
    @StateObject private var profileViewModel = ProfileViewModel()
    @State private var showFirstLaunch = false
    
    private var hasCredentials: Bool {
        !storedCredentials.isEmpty
    }
    
    private var currentCredentials: GreencardCredentials? {
        storedCredentials.first
    }
    
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            GreencardView()
                .environmentObject(profileViewModel)
                .tabItem {
                    Label("Greencard", systemImage: "tram.card.fill")
                }
            
            HistoryView()
                .environmentObject(profileViewModel)
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
        }
        .tint(Design.primary)
        .onAppear {
            setupApp()
        }
        .onChange(of: storedCredentials.count) { oldValue, newValue in
            if newValue == 0 {
                // Credentials removed (logout); reset view data and show onboarding
                profileViewModel.accountData = nil
                profileViewModel.historyItems = []
                showFirstLaunch = true
            } else if let credentials = currentCredentials {
                // Credentials added or changed; refresh data
                profileViewModel.updateCredentials(credentials)
            }
        }
        .fullScreenCover(isPresented: $showFirstLaunch) {
            FirstLaunchView(isPresented: $showFirstLaunch)
        }
    }
    
    private func setupApp() {
        if hasCredentials, let credentials = currentCredentials {
            // User has credentials, update the view model
            profileViewModel.updateCredentials(credentials)
        } else {
            // Show first launch experience
            showFirstLaunch = true
        }
    }
}

// MARK: - Dashboard View
struct DashboardView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: Design.Spacing.l) {
                Text("Welcome to BetterMetro")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(alignment: .leading)
                
                Text("Your enhanced Greencard experience")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(alignment: .leading)
                
                Spacer()
            }
            .padding()
            .background(Design.background)
            .navigationTitle("Dashboard")
        }
    }
}

// MARK: - Greencard View (Main Profile View)
struct GreencardView: View {
    @EnvironmentObject private var viewModel: ProfileViewModel
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    VStack {
                        ProgressView("Loading your account...")
                        Text("Fetching the latest information")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    ErrorView(
                        message: errorMessage,
                        retryAction: {
                            Task { await viewModel.loadData() }
                        }
                    )
                } else if let accountData = viewModel.accountData {
                    AccountInfoView(accountData: accountData)
                } else {
                    ContentUnavailableView(
                        "No Account Data",
                        systemImage: "tram.card.fill",
                        description: Text("Pull down to refresh your account information")
                    )
                }
            }
            .refreshable {
                await viewModel.refresh()
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            .navigationTitle("Greencard")
        }
    }
}

// MARK: - Account Info View
struct AccountInfoView: View {
    @EnvironmentObject private var viewModel: ProfileViewModel
    @Environment(\.modelContext) private var modelContext
    @Query private var storedCredentials: [GreencardCredentials]
    @State private var showTopUpSheet = false
    let accountData: AccountData
    
    var body: some View {
        ScrollView {
            // Header image hugs the first card (no gap beneath)
            LazyVStack(alignment: .leading, spacing: 0) {
                Image("profileHeader")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(.top, Design.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .center)

                CardView {
                    VStack(alignment: .leading, spacing: Design.Spacing.m) {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundColor(Design.primary)

                            VStack(alignment: .leading) {
                                Text(accountData.account.fullName)
                                    .font(.headline)
                                Text(accountData.account.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: Design.Spacing.s) {
                            Text("Card Number")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(accountData.card.printedCardNumber)
                                .font(.headline)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = accountData.card.printedCardNumber
                                    } label: {
                                        Label("Copy Card Number", systemImage: "doc.on.doc")
                                    }
                                }
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Design.radius)
                        .fill(Color.white.opacity(0.01)) // invisible layer used only to render the shadow
                        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: -4)
                        .mask(
                            LinearGradient(
                                colors: [.white, .white, .clear], // keep shadow at top, fade it out downwards
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .allowsHitTesting(false)
                }


                // Combined Balance Card
                CardView {
                    VStack(alignment: .leading, spacing: Design.Spacing.m) {
                        Text("Balance")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(accountData.card.balanceInDollars)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(Design.primary)

                        Text("Pending: \(accountData.card.pendingBalanceInDollars)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Design.Spacing.l)

                Button {
                    showTopUpSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Design.primary)
                        Text("Top Up Card")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Design.radius))
                }
                .padding(.top, Design.Spacing.l)
                .sheet(isPresented: $showTopUpSheet) {
                    let creds = storedCredentials.first
                    AuthenticatedWebView(
                        url: URL(string: "https://greencard.metrotas.com.au/api/v1/pages/top-up/")!,
                        credentials: creds?.cardNumber ?? accountData.account.username,
                        password: creds?.password ?? ""
                    )
                    .onDisappear {
                        Task { await viewModel.refresh() }
                    }
                }
                
                // Additional Account Details
                CardView {
                    VStack(alignment: .leading, spacing: Design.Spacing.m) {
                        
                        VStack(alignment: .leading, spacing: Design.Spacing.s) {
                            Text("Phone")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(accountData.account.phone)
                                .font(.headline)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: Design.Spacing.s) {
                            Text("Default Trip")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(accountData.account.defaultTrip)
                                .font(.headline)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: Design.Spacing.s) {
                            Text("Residential Address")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(accountData.account.residentialAddress.street), \(accountData.account.residentialAddress.suburb) \(accountData.account.residentialAddress.postcode)")
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, Design.Spacing.l)

                Button(role: .destructive, action: logout) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                        Text("Log Out")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.regularMaterial)
                    .foregroundColor(.red)
                    .clipShape(RoundedRectangle(cornerRadius: Design.radius))
                }
                .padding(.top, Design.Spacing.l)
                .padding(.bottom, Design.Spacing.l)
            }
            .padding(.horizontal)
        }
    }

    private func logout() {
        // Remove saved credentials and clear in-memory data
        for credential in storedCredentials {
            modelContext.delete(credential)
        }
        try? modelContext.save()
        viewModel.accountData = nil
        viewModel.historyItems = []
    }
}

// MARK: - Balance Card View
struct BalanceCardView: View {
    let title: String
    let amount: String
    let color: Color
    
    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(amount)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
        }
    }
}

// MARK: - Generic Card View
struct CardView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: Design.radius))
    }
}

// MARK: - Error View
struct ErrorView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        ContentUnavailableView {
            Label("Error Loading Data", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                retryAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(Design.primary)
        }
    }
}

// MARK: - History View
struct HistoryView: View {
    @EnvironmentObject private var viewModel: ProfileViewModel
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading history...")
                } else if let errorMessage = viewModel.errorMessage {
                    ErrorView(
                        message: errorMessage,
                        retryAction: {
                            Task { await viewModel.loadData() }
                        }
                    )
                } else if viewModel.historyItems.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock",
                        description: Text("Your transaction history will appear here")
                    )
                } else {
                    List(viewModel.historyItems) { item in
                        HistoryRowView(item: item)
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            .navigationTitle("History")
            .safeAreaInset(edge: .top) {
                // Add breathing room beneath the nav title without affecting scroll behavior
                Color.clear.frame(height: Design.Spacing.m)
            }
        }
    }
}

// MARK: - History Row View
struct HistoryRowView: View {
    let item: HistoryItem
    
    var body: some View {
        HStack {
            Image(systemName: item.type == "trip" ? "bus" : "plus.circle.fill")
                .foregroundColor(item.type == "trip" ? Color(red: 106/255, green: 182/255, blue: 248/255) : Design.primary)
                .font(.title2)
            
            VStack(alignment: .leading) {
                Text(item.type.capitalized)
                    .font(.headline)
                Text(item.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(item.balanceChangeInDollars)
                .font(.headline)
                .foregroundColor(item.isPositive ? Design.primary : .red)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Change Credentials View
struct ChangeCredentialsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var storedCredentials: [GreencardCredentials]
    
    @State private var cardNumber: String = ""
    @State private var password: String = ""
    @State private var isAuthenticating: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    
    private let service = GreencardService.shared
    
    var body: some View {
        NavigationStack {
            Form {
                Section("New Credentials") {
                    TextField("Card Number", text: $cardNumber)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .keyboardType(.numberPad)
                    
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                
                Section {
                    Button("Update Credentials") {
                        Task { await updateCredentials() }
                    }
                    .disabled(cardNumber.isEmpty || password.isEmpty || isAuthenticating)
                }
            }
            .navigationTitle("Change Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Authentication Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "Unknown error occurred")
            }
        }
    }
    
    @MainActor
    private func updateCredentials() async {
        isAuthenticating = true
        errorMessage = nil
        
        let credentials = GreencardCredentials(
            cardNumber: cardNumber,
            password: password
        )
        
        do {
            // Test authentication
            let isValid = try await service.authenticate(credentials: credentials)
            
            if isValid {
                // Clear old credentials
                for oldCredential in storedCredentials {
                    modelContext.delete(oldCredential)
                }
                
                // Save new credentials
                modelContext.insert(credentials)
                try modelContext.save()
                
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isAuthenticating = false
    }
}

import WebKit

struct AuthenticatedWebView: UIViewRepresentable {
    let url: URL
    let credentials: String
    let password: String

    func makeCoordinator() -> Coordinator {
        Coordinator(credentials: credentials, password: password)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Inject BetterMetro CSS
        let css = """
        :root {
            --brand-bg-dark: #060803;
            --brand-primary-dark: #24A355;
            --brand-primary-light: #5CDB8D;
            --brand-bg-light: #FAFDF7;
            --brand-button-text-light: #0D1906;
            --brand-button-text-dark: #EDF9E6;
            --brand-card-bg: #0B1209;
        }

        /* Base layout */
        body {
            background: #1C1C1E !important; /* iOS dark system background */
            margin: 0 !important;
            padding: 16px !important;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", -apple-system, system-ui, sans-serif !important;
            color: #ffffff !important;
        }

        .container,
        #container {
            padding: 0 !important;
            margin: 0 auto !important;
            background: #1C1C1E !important;
        }

        /* Kill table backgrounds / borders (these were causing white stripes) */
        table.table,
        .table > tbody > tr,
        .table > tbody > tr > td {
            border: none !important;
            padding: 0 !important;
            background: transparent !important;
        }

        /* Card-style groups */
        .form-group {
            background: #2C2C2E !important; /* iOS secondary background */
            padding: 16px !important;
            border-radius: 16px !important;
            margin-bottom: 12px !important;
        }

        /* Labels */
        .control-label label {
            font-size: 14px !important;
            color: #9FA4A0 !important;
            font-weight: 600 !important;
        }
        .control-label {
            display: flex !important;
            align-items: center !important;
            gap: 8px !important;
        }

        /* Inputs */
        .form-control {
            height: 6vh !important;
            background: #3A3A3C !important; /* iOS tertiary background */
            color: #ffffff !important;
            border: none !important;
            border-radius: 12px !important;
            padding: 11px 12px !important;
            font-size: 16px !important;
        }

        /* Prevent dropdown text clipping */
        select.form-control {
            line-height: 1.5 !important;
            padding-right: 40px !important; /* space for the arrow */
        }
        /* Amount dropdown with custom arrow */
        select.form-control {
            appearance: none !important;
            background-image: url('data:image/svg+xml;utf8,<svg fill="white" height="18" viewBox="0 0 24 24" width="18" xmlns="http://www.w3.org/2000/svg"><path d="M7 10l5 5 5-5z"/></svg>') !important;
            background-repeat: no-repeat !important;
            background-position: right 12px center !important;
        }

        /* Section heading row */
        .subhead,
        .subhead td {
            background: transparent !important;
            padding: 0 !important;
        }

        .subhead h4 {
            margin-top: 8px !important;
            margin-bottom: 8px !important;
            font-weight: 600 !important;
            color: #ffffff !important;
            font-size: 15px !important;
            letter-spacing: 0.3px !important;
        }


        input.save_card[type="checkbox"] {
            accent-color: var(--brand-primary-dark);
        }

        /* cc_form visibility helper */
        .hidden {
            display: none !important;
        }

        /* Submit button */
        #submit-btn {
            background: var(--brand-primary-dark) !important;
            color: var(--brand-button-text-dark) !important;
            border-radius: 12px !important;
            display: flex !important;
            align-items: center !important;
            justify-content: center !important;
            width: 100% !important;
            box-sizing: border-box !important;
            padding: 12px 16px !important;
            font-weight: 600 !important;
            font-size: 17px !important;
            min-height: 44px !important;
        }

        /* Disabled submit state */
        #submit-btn[disabled],
        #submit-btn.disabled {
            background: #3A3A3C !important;
            color: #A0A0A0 !important;
        }

        /* “View stored cards” link */
        button.form-link {
            background: none !important;
            color: var(--brand-primary-light) !important;
            font-size: 17px !important;
            display: flex !important;
            align-items: center !important;
            justify-content: center !important;
            width: 100% !important;
            box-sizing: border-box !important;
            padding: 12px 16px !important;
            min-height: 44px !important;
        }

        /* No legacy Bootstrap shadows */
        .btn,
        .form-control,
        select,
        button {
            box-shadow: none !important;
        }
        """
        let js = """
        var style = document.createElement('style');
        style.innerHTML = `\(css)`;
        document.head.appendChild(style);
        """

        let userScript = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // First authenticated load
        var request = URLRequest(url: url)
        let credentialString = "\(credentials):\(password)"
        let base64 = Data(credentialString.utf8).base64EncodedString()
        request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        request.setValue("MetroTasMobile/0.0.0 android", forHTTPHeaderField: "User-Agent")

        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let credentials: String
        let password: String

        init(credentials: String, password: String) {
            self.credentials = credentials
            self.password = password
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Only intercept top-level navigations
            guard let url = navigationAction.request.url,
                  navigationAction.targetFrame?.isMainFrame == true else {
                decisionHandler(.allow)
                return
            }

            // Allow already-authenticated requests
            if navigationAction.request.value(forHTTPHeaderField: "Authorization") != nil {
                decisionHandler(.allow)
                return
            }

            let credentialString = "\(credentials):\(password)"
            let base64 = Data(credentialString.utf8).base64EncodedString()

            // Preserve original request properties
            var newRequest = navigationAction.request
            newRequest.url = url
            newRequest.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            newRequest.setValue("MetroTasMobile/0.0.0 android", forHTTPHeaderField: "User-Agent")

            webView.load(newRequest)
            decisionHandler(.cancel)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [GreencardCredentials.self, Item.self], inMemory: true)
}
