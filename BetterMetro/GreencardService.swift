import Foundation
import Combine
import SwiftUI

public enum GreencardAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case decodingError(Error)
    case authenticationFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .invalidResponse:
            return "Invalid response from server."
        case .serverError(let message):
            return "Server error: \(message)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .authenticationFailed:
            return "Authentication failed. Please check your credentials."
        }
    }
}

@MainActor
public class GreencardService: ObservableObject {
    private let baseURLString = "https://greencard.metrotas.com.au/api/v1"
    private let userAgent = "MetroTasMobile/0.0.0 android"
    
    // Singleton instance
    public static let shared = GreencardService()
    
    private let redirectDelegate = GreencardSessionDelegate()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
    }()
    
    private init() {
        print("🔧 GreencardService initialized with base URL: \(baseURLString)")
    }
    
    private func makeRequest(slug: String, method: String = "GET", credentials: GreencardCredentials, body: Data? = nil) throws -> URLRequest {
        // Validate credentials first
        guard credentials.isValid else {
            print("❌ Invalid credentials provided to makeRequest")
            throw GreencardAPIError.authenticationFailed
        }
        
        guard let url = URL(string: "\(baseURLString)/\(slug)") else {
            print("❌ Failed to create URL for slug: \(slug)")
            throw GreencardAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Build Basic Auth header: "username:password" -> base64 -> "Basic <encoded>"
        let credentialString = "\(credentials.cardNumber):\(credentials.password)"
        
        guard let credentialData = credentialString.data(using: .utf8) else {
            print("❌ Failed to encode credentials string")
            throw GreencardAPIError.authenticationFailed
        }
        
        let base64Credentials = credentialData.base64EncodedString()
        let authHeader = "Basic \(base64Credentials)"
        
        print("🔐 Authorization header: \(authHeader)")
        
        // Set headers
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        // For POST requests, set content type and body only if body is provided
        if method == "POST", let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            print("🔧 Set request body: \(String(data: body, encoding: .utf8) ?? "Unable to decode")")
        }
        
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        
        print("🔧 Created request for: \(method) \(url)")
        print("🔧 Request headers: \(request.allHTTPHeaderFields ?? [:])")
        
        return request
    }
    
    private func performRequest<T: Codable>(_ request: URLRequest, expecting: T.Type) async throws -> T {
        // Log the request being sent
        print("🚀 Sending request to: \(request.url?.absoluteString ?? "unknown URL")")
        print("🚀 Method: \(request.httpMethod ?? "GET")")
        print("🚀 Headers: \(request.allHTTPHeaderFields ?? [:])")
        if let body = request.httpBody {
            print("🚀 Body: \(String(data: body, encoding: .utf8) ?? "Unable to decode body")")
        }
        
        do {
            print("🔄 Making network request...")
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                throw GreencardAPIError.invalidResponse
            }
            
            print("📥 Response status code: \(httpResponse.statusCode)")
            print("📥 Response headers: \(httpResponse.allHeaderFields)")
            print("📥 Response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode response")")
            
            // Check for HTTP errors
            if httpResponse.statusCode == 401 {
                print("❌ Authentication failed (401)")
                throw GreencardAPIError.authenticationFailed
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                print("❌ HTTP error: \(httpResponse.statusCode)")
                throw GreencardAPIError.serverError("HTTP \(httpResponse.statusCode)")
            }
        
            do {
                let decoder = JSONDecoder()
                
                // For authentication endpoint, we get a different response structure
                if T.self == AuthenticationResponse.self {
                    // Parse the raw response to check success
                    if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = jsonObject["success"] as? Bool,
                       success {
                        print("✅ Authentication successful")
                        // Create a dummy AuthenticationResponse since data is null
                        return AuthenticationResponse() as! T
                    } else {
                        print("❌ Authentication failed - success field is false or missing")
                        throw GreencardAPIError.authenticationFailed
                    }
                }
                
                let apiResponse = try decoder.decode(GreencardAPIResponse<T>.self, from: data)
                
                if !apiResponse.success, let errors = apiResponse.errors, let firstError = errors.first {
                    print("❌ API error: \(firstError.message)")
                    throw GreencardAPIError.serverError(firstError.message)
                }
                
                guard let responseData = apiResponse.data else {
                    print("❌ No data in response")
                    throw GreencardAPIError.invalidResponse
                }
                
                print("✅ Request successful, returning data")
                return responseData
            } catch {
                print("❌ Error processing response: \(error)")
                if error is GreencardAPIError {
                    throw error
                } else {
                    throw GreencardAPIError.decodingError(error)
                }
            }
        } catch {
            print("❌ Network error: \(error)")
            if error is GreencardAPIError {
                throw error
            } else {
                // This catches URLSession errors like no internet connection, timeout, etc.
                throw GreencardAPIError.serverError("Network error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - API Methods
    
    /// Checks if the device can reach the server
    public func checkConnectivity() async -> Bool {
        guard let url = URL(string: "\(baseURLString)/ping") else { return false }
        
        do {
            print("🔍 Checking connectivity to server...")
            let (data, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                let isConnected = httpResponse.statusCode < 500
                print("🔍 Connectivity check: \(isConnected ? "✅ Connected" : "❌ Server error")")
                return isConnected
            }
        } catch {
            print("🔍 Connectivity check failed: \(error.localizedDescription)")
        }
        
        return false
    }
    
    /// Validates credentials with the auth endpoint
    public func authenticate(credentials: GreencardCredentials) async throws -> Bool {
        print("🔐 Starting authentication process...")

        // Auth requires ONLY headers, no request body
        let request = try makeRequest(
            slug: "auth",
            method: "POST",
            credentials: credentials,
            body: nil
        )

        let _: AuthenticationResponse = try await performRequest(request, expecting: AuthenticationResponse.self)

        print("✅ Authentication completed successfully")
        return true
    }
    
    /// Fetches account and card information
    public func fetchAccountData(credentials: GreencardCredentials) async throws -> AccountData {
        let request = try makeRequest(slug: "account", credentials: credentials)
        return try await performRequest(request, expecting: AccountData.self)
    }
    
    /// Fetches transaction history
    public func fetchHistory(credentials: GreencardCredentials) async throws -> [HistoryItem] {
        let request = try makeRequest(slug: "history", credentials: credentials)
        return try await performRequest(request, expecting: [HistoryItem].self)
    }
    
    /// Returns the top-up URL
    public func topUpURL(credentials: GreencardCredentials) -> URL? {
        URL(string: "\(baseURLString)/pages/top-up")
    }
}
