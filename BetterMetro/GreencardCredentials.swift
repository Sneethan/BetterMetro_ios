import Foundation
import SwiftData

@Model
public class GreencardCredentials {
    public var id: UUID
    public var cardNumber: String
    public var password: String
    public var createdAt: Date
    public var base64Token: String?

    public init(id: UUID = UUID(), cardNumber: String, password: String, createdAt: Date = Date()) {
        self.id = id
        self.cardNumber = cardNumber
        self.password = password
        self.createdAt = createdAt

        // Precompute and store Base64 token for `username:password`
        let credential = "\(cardNumber):\(password)"
        self.base64Token = credential.data(using: .utf8)?.base64EncodedString()
    }

    public var isValid: Bool {
        let trimmedCardNumber = cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedCardNumber.isEmpty && !trimmedPassword.isEmpty
    }
    
    /// Validates that credentials can create a proper auth header
    public var canCreateAuthHeader: Bool {
        return authorizationHeaderValue != nil
    }

    public var authorizationHeaderValue: String? {
        // Validate credentials first
        guard !cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ Cannot create auth header: empty credentials")
            return nil
        }
        
        let trimmedCardNumber = cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = "\(trimmedCardNumber):\(trimmedPassword)"
        
        print("🔐 Creating auth header for: \(trimmedCardNumber):[REDACTED]")
        
        guard let credentialData = credential.data(using: .utf8) else {
            print("❌ Failed to convert credential to UTF8 data")
            return nil
        }
        
        let encoded = credentialData.base64EncodedString()
        let authHeader = "Basic \(encoded)"
        print("🔐 Auth header created successfully")
        
        // Verify we can decode it back (for debugging)
        if let decodedData = Data(base64Encoded: encoded),
           let decodedString = String(data: decodedData, encoding: .utf8) {
            print("🔐 Auth validation: \(decodedString == credential ? "✅ Valid" : "❌ Invalid")")
        }
        
        return authHeader
    }

    public func refreshToken() {
        let credential = "\(cardNumber):\(password)"
        base64Token = credential.data(using: .utf8)?.base64EncodedString()
    }
}
