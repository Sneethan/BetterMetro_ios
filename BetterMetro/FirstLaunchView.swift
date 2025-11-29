
import SwiftUI
import SwiftData

struct FirstLaunchView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    
    @State private var cardNumber: String = ""
    @State private var password: String = ""
    @State private var isAuthenticating: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var step: OnboardingStep = .welcome
    
    private let service = GreencardService.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: Design.Spacing.l) {
                Spacer()
                
                ZStack {
                    if step == .welcome {
                        welcomePage
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                    
                    if step == .security {
                        securityPage
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .identity // no exit animation when heading to sign-in
                            ))
                    }
                    
                    if step == .login {
                        loginForm
                            .transition(.opacity) // whisper-subtle fade in
                    }
                }
                .padding(.horizontal, Design.Spacing.l)
                .animation(step == .login ? .easeInOut(duration: 0.14) : .easeInOut(duration: 0.32),
                           value: step)
                
                Spacer()
                
                VStack(spacing: Design.Spacing.m) {
                    if step != .login {
                        stepIndicator
                        Button(action: advanceStep) {
                            HStack {
                                Text(step == .security ? "Continue to Sign In" : "Continue")
                                    .fontWeight(.semibold)
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Design.primary)
                            .foregroundColor(Design.btntext)
                            .clipShape(RoundedRectangle(cornerRadius: Design.radius))
                        }
                    } else {
                        Button(action: authenticateUser) {
                            HStack {
                                if isAuthenticating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Design.btntext))
                                        .scaleEffect(0.8)
                                }
                                Text(isAuthenticating ? "Authenticating..." : "Sign In")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Design.primary)
                            .foregroundColor(Design.btntext)
                            .clipShape(RoundedRectangle(cornerRadius: Design.radius))
                        }
                        .disabled(cardNumber.isEmpty || password.isEmpty || isAuthenticating)
                    }
                }
                .padding(.horizontal, Design.Spacing.l)
                .padding(.bottom, Design.Spacing.l)
            }
            .navigationBarHidden(true)
            // Radial glow that feels like light spilling down from above.
            .background(alignment: .top) {
                if step != .login {
                    RadialGradient(
                        colors: [
                            Design.primary.opacity(0.7),
                            Design.primary.opacity(0.18),
                            .clear
                        ],
                        center: UnitPoint(x: 0.5, y: -0.4), // originate above the visible bounds
                        startRadius: 24,
                        endRadius: 520
                    )
                    .frame(height: 420)
                    .offset(y: -140) // pull it further offscreen so it pours downward
                    .blur(radius: 28)
                    .opacity(0.9)
                    .allowsHitTesting(false)
                    .padding(.horizontal, -Design.Spacing.xl)
                }
            }
        }
        .alert("Authentication Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Unknown error occurred")
        }
    }
    
    private var welcomePage: some View {
        VStack(spacing: Design.Spacing.m) {
            Image(systemName: "tram.card.fill")
                .font(.system(size: 64))
                .foregroundColor(Design.primary)
            
            Text("Welcome to BetterMetro")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.bottom, Design.Spacing.xl)
            
            VStack(alignment: .leading, spacing: Design.Spacing.m) {
                benefitRow(icon: "bolt.fill", title: "Lightning Fast", detail: "A fluid, snappy design ensures everything is exactly where you need it.")
                benefitRow(icon: "arrow.clockwise.circle.fill", title: "Always Accurate", detail: "We proactively fetch the freshest data so you can rely that it's up to date.")
                benefitRow(icon: "plus.app", title: "Feature Packed", detail: "See your balance on the go, with widgets and complications (coming soon)")
            }
        }
    }
    
    private var securityPage: some View {
        VStack(spacing: Design.Spacing.m) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 64))
                .foregroundColor(Design.primary)
            
            Text("Your data is yours.")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.bottom, Design.Spacing.xl)
            
            VStack(alignment: .leading, spacing: Design.Spacing.m) {
                benefitRow(icon: "lock.fill", title: "Stored Securely", detail: "Credentials are encrypted and kept on your device only.")
                benefitRow(icon: "key.fill", title: "Used For You", detail: "We only use your login to pull your Greencard data. We never share or sell your information, or send it to anywhere that isn't Metro Tasmania.")
                benefitRow(icon: "heart.circle.fill", title: "Fully Independent", detail: "BetterMetro is a fully independent project made by a transit enthusiast, for transit users. It is not endorsed or affiliated with Metro Tasmania.")
            }
        }
    }
    
    private var loginForm: some View {
        VStack(spacing: Design.Spacing.l) {
            VStack(spacing: Design.Spacing.m) {
                Image(systemName: "tram.card.fill")
                    .font(.system(size: 64))
                    .foregroundColor(Design.primary)
                
                Text("Sign in to continue")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Enter your Greencard credentials to get started")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: Design.Spacing.m) {
                VStack(alignment: .leading, spacing: Design.Spacing.s) {
                    Text("Card Number (including suffix)")
                        .font(.caption)
                        .fontWeight(.medium)
                    TextField("e.g. 1807022585-1", text: $cardNumber)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(Color(uiColor: .systemGray5))
                        .cornerRadius(14)
                        .contentShape(Rectangle())
                }
                
                VStack(alignment: .leading, spacing: Design.Spacing.s) {
                    Text("Password")
                        .font(.caption)
                        .fontWeight(.medium)
                    SecureField("Enter your password", text: $password)
                        .textContentType(.password)
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(Color(uiColor: .systemGray5))
                        .cornerRadius(14)
                        .contentShape(Rectangle())
                }
             .padding(.bottom, Design.Spacing.xl)
            }
            
            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                Image(systemName: "person.2.fill")
                    .foregroundColor(Design.primary)
                    .font(.title2)
                    .padding(.bottom, Design.Spacing.s)
                Text("We respect your privacy. Your credentials are securely stored on your device and never shared. We only use them to fetch your Greencard data, and are not affiliated with Metro Tasmania.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("See how your data is managed…") {
                    // Placeholder action for future privacy link
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(Design.primary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading) // stretch to match text fields/buttons
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.m) {
            Image(systemName: icon)
                .foregroundColor(Design.primary)
                .font(.title) // slightly larger, left-aligned
                .frame(width: 32, alignment: .topLeading)
            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var stepIndicator: some View {
        HStack(spacing: Design.Spacing.s) {
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == step ? Design.primary : Color(uiColor: .systemGray5))
                    .frame(width: item == step ? 28 : 12, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }
    
    private func advanceStep() {
        if let next = step.next() {
            step = next
        }
    }
    
    private func authenticateUser() {
        Task {
            await performAuthentication()
        }
    }
    
    @MainActor
    private func performAuthentication() async {
        print("🔐 Starting authentication process from UI...")
        isAuthenticating = true
        errorMessage = nil
        
        // Check connectivity first
        let isConnected = await service.checkConnectivity()
        if !isConnected {
            errorMessage = "Unable to connect to server. Please check your internet connection."
            showError = true
            isAuthenticating = false
            return
        }
        
        // Create credentials object for testing
        let credentials = GreencardCredentials(
            cardNumber: cardNumber,
            password: password
        )
        
        print("🔐 Created credentials for card number: \(cardNumber)")
        
        do {
            // Test authentication
            print("🔐 Attempting authentication...")
            let isValid = try await service.authenticate(credentials: credentials)
            
            if isValid {
                print("✅ Authentication successful, saving credentials...")
                // Save credentials to persistent storage
                modelContext.insert(credentials)
                try modelContext.save()
                
                print("✅ Credentials saved, dismissing view...")
                // Dismiss the sheet
                isPresented = false
            }
        } catch {
            print("❌ Authentication error: \(error)")
            errorMessage = error.localizedDescription
            showError = true
        }
        
        print("🔐 Authentication process completed")
        isAuthenticating = false
    }
    
    private enum OnboardingStep: CaseIterable {
        case welcome
        case security
        case login
        
        func next() -> OnboardingStep? {
            switch self {
            case .welcome: return .security
            case .security: return .login
            case .login: return nil
            }
        }
    }
}
