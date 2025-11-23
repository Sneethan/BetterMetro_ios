//
//  GreencardAPIModels.swift
//  BetterMetro
//
//  Created by Assistant on 17/11/2025.
//

import Foundation

// MARK: - API Response Wrapper
public struct GreencardAPIResponse<T: Codable>: Codable {
    public let success: Bool
    public let data: T?
    public let errors: [APIError]?
    
    public init(success: Bool, data: T? = nil, errors: [APIError]? = nil) {
        self.success = success
        self.data = data
        self.errors = errors
    }
}

public struct APIError: Codable {
    public let message: String
    
    public init(message: String) {
        self.message = message
    }
}

// MARK: - Authentication Response
public struct AuthenticationResponse: Codable {
    // The auth endpoint returns null data when successful
    // We just need this to match the structure, but the actual validation
    // is done by checking the success field in GreencardAPIResponse
    
    public init() {
        // Empty initializer for creating dummy instances
    }
}

// MARK: - Account Response Models
public struct AccountData: Codable {
    public let account: Account
    public let card: Card
}

public struct Account: Codable {
    public let username: String
    public let familyName: String
    public let dateOfBirth: String
    public let givenName: String
    public let postalAddress: Address
    public let phone: String
    public let defaultTrip: String
    public let residentialAddress: Address
    public let email: String
    public let allowMarketing: Bool
    
    enum CodingKeys: String, CodingKey {
        case username
        case familyName = "family_name"
        case dateOfBirth = "date_of_birth"
        case givenName = "given_name"
        case postalAddress = "postal_address"
        case phone
        case defaultTrip = "default_trip"
        case residentialAddress = "residential_address"
        case email
        case allowMarketing = "allow_marketing"
    }
    
    public var fullName: String {
        "\(givenName) \(familyName)"
    }
}

public struct Address: Codable {
    public let suburb: String
    public let street: String
    public let postcode: String
}

public struct Card: Codable {
    public let cardType: String
    public let printedCardNumber: String
    public let autoTopUp: String?
    public let balance: Int
    public let cardNumber: String
    public let pendingBalance: Int
    
    enum CodingKeys: String, CodingKey {
        case cardType = "card_type"
        case printedCardNumber = "printed_card_number"
        case autoTopUp = "auto_top_up"
        case balance
        case cardNumber = "card_number"
        case pendingBalance = "pending_balance"
    }
    
    public var balanceInDollars: String {
        String(format: "$%.2f", Double(balance) / 100)
    }
    
    public var pendingBalanceInDollars: String {
        String(format: "$%.2f", Double(pendingBalance) / 100)
    }
}

// MARK: - History Response Models
public struct HistoryItem: Codable, Identifiable {
    public let date: String
    public let type: String
    public let balanceChange: Int
    
    enum CodingKeys: String, CodingKey {
        case date
        case type
        case balanceChange = "balance_change"
    }
    
    public var id: String {
        "\(date)-\(type)-\(balanceChange)"
    }
    
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        if let parsedDate = formatter.date(from: date) {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: parsedDate)
        }
        return date
    }
    
    public var balanceChangeInDollars: String {
        let amount = Double(balanceChange) / 100
        if amount >= 0 {
            return String(format: "+$%.2f", amount)
        } else {
            return String(format: "-$%.2f", abs(amount))
        }
    }
    
    public var isPositive: Bool {
        balanceChange >= 0
    }
}