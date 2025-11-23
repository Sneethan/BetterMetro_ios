//
//  FirstLaunchView.swift
//  BetterMetro
//
//  Created by Assistant on 17/11/2025.
//

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
    
    private let service = GreencardService.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: Design.Spacing.l) {
                // Header
                VStack(spacing: Design.Spacing.m) {
                    Image(systemName: "tram.card.fill")
                        .font(.system(size: 64))
                        .foregroundColor(Design.primary)
                    
                    Text("Welcome to BetterMetro")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Enter your Greencard credentials to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Design.Spacing.l)
                
                Spacer()
                
                // Form
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
                }
                .padding(.horizontal, Design.Spacing.l)
                
                Spacer()

                // Data privacy scaffold
                VStack(alignment: .leading, spacing: Design.Spacing.s) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(Color(red: 0.56, green: 0.45, blue: 1.0))
                            .font(.title2)
                            .frame(width: 40, height: 40)
                            .background(Color(red: 0.9, green: 0.88, blue: 1.0).opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text("Your credentials are encrypted and used only to talk to MetroTas. We don’t store your password in the cloud.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    if let privacyURL = URL(string: "https://www.metrotas.com.au/privacy-policy") {
                        Link("See how your data is managed…", destination: privacyURL)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(Color(red: 0.56, green: 0.45, blue: 1.0))
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, Design.Spacing.l)
                
                // Action Button
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
                .padding(.horizontal, Design.Spacing.l)
                .padding(.bottom, Design.Spacing.l)
            }
            .background(Design.background)
            .navigationBarHidden(true)
        }
        .alert("Authentication Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Unknown error occurred")
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
}

#Preview {
    FirstLaunchView(isPresented: .constant(true))
        .modelContainer(for: GreencardCredentials.self, inMemory: true)
}
