import Foundation
import Combine
import SwiftUI

public enum GreencardAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case decodingError(Error)
    case authenticationFailed
    case missingConfiguration(String)
    
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
        case .missingConfiguration(let key):
            return "Missing configuration for \(key). Set it before calling this endpoint."
        }
    }
}

@MainActor
public class GreencardService: ObservableObject {
    private let baseURLString = "https://greencard.metrotas.com.au/api/v1"
    private let userAgent = "MetroTasMobile/0.0.0 android"

    // Optional Trip Planner endpoints (injected via env vars or runtime configuration)
    private let tripPlannerRESTBase = ProcessInfo.processInfo.environment["TRIPPLANNER_REST_BASE"].flatMap { URL(string: $0) }
    private let tripPlannerGraphQLEndpoint = ProcessInfo.processInfo.environment["TRIPPLANNER_GRAPHQL_ENDPOINT"].flatMap { URL(string: $0) }
    
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
        
        // Preserve slug exactly as provided (no forced trailing slash) to avoid 405s
        let normalizedSlug = slug.hasPrefix("/") ? String(slug.dropFirst()) : slug
        guard let url = URL(string: "\(baseURLString)/\(normalizedSlug)") else {
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
            // Propagate cancellations explicitly so callers can ignore them
            if let urlError = error as? URLError, urlError.code == .cancelled {
                print("❌ Network cancelled: \(urlError)")
                throw CancellationError()
            }

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
            let (_, response) = try await session.data(from: url)
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
        URL(string: "\(baseURLString)/pages/top-up/")
    }

    /// Update account details (PUT /account/)
    public func updateAccount(credentials: GreencardCredentials, payload: AccountUpdatePayload) async throws -> AccountData {
        let body = try JSONEncoder().encode(AccountUpdateRequest(account: payload))
        let request = try makeRequest(slug: "account", method: "PUT", credentials: credentials, body: body)
        return try await performRequest(request, expecting: AccountData.self)
    }

    // MARK: - Trip Planner (optional, scaffolded)

    /// Fetch available networks from the trip-planner REST API.
    public func fetchNetworks(restBase override: URL? = nil) async throws -> NetworkListResponse {
        guard let base = override ?? tripPlannerRESTBase else {
            throw GreencardAPIError.missingConfiguration("TRIPPLANNER_REST_BASE")
        }
        var request = URLRequest(url: base.appendingPathComponent("networks"))
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await performTripPlannerREST(request, expecting: NetworkListResponse.self)
    }

    /// Fetch timetables; optionally filter by network and region.
    public func fetchTimetables(restBase override: URL? = nil, networkId: String? = nil, regionId: String? = nil) async throws -> TimetableListResponse {
        guard let base = override ?? tripPlannerRESTBase else {
            throw GreencardAPIError.missingConfiguration("TRIPPLANNER_REST_BASE")
        }

        var components = URLComponents(url: base.appendingPathComponent("timetables"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        if let networkId { queryItems.append(URLQueryItem(name: "network_id", value: networkId)) }
        if let regionId { queryItems.append(URLQueryItem(name: "region_id", value: regionId)) }
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else { throw GreencardAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await performTripPlannerREST(request, expecting: TimetableListResponse.self)
    }

    /// Generic GraphQL caller for trip-planner real-time endpoints.
    public func performTripPlannerGraphQL(
        operationName: String?,
        variables: [String: Any],
        query: String,
        endpoint override: URL? = nil
    ) async throws -> Data {
        guard let endpoint = override ?? tripPlannerGraphQLEndpoint else {
            throw GreencardAPIError.missingConfiguration("TRIPPLANNER_GRAPHQL_ENDPOINT")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let body: [String: Any?] = [
            "operationName": operationName,
            "variables": variables,
            "query": query
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 }, options: [])

        return try await performTripPlannerRaw(request)
    }

    // MARK: - Private helpers (Trip Planner)
    private func performTripPlannerREST<T: Codable>(_ request: URLRequest, expecting: T.Type) async throws -> T {
        print("🚀 Trip planner REST -> \(request.url?.absoluteString ?? "unknown")")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw GreencardAPIError.serverError("Trip planner REST returned non-2xx")
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private func performTripPlannerRaw(_ request: URLRequest) async throws -> Data {
        print("🚀 Trip planner GraphQL -> \(request.url?.absoluteString ?? "unknown")")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw GreencardAPIError.serverError("Trip planner GraphQL returned non-2xx")
        }
        return data
    }
}
