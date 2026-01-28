//
//  BudgetModels.swift
//  MyBudget
//
//  Created by David Wojcik on 1/23/26.
//

import Foundation

struct SimpleFinTransaction: Codable, Identifiable {
    let id: String
    let dateString: String // Maps to "date" in JSON
    let amount: String?
    let payee: String?
    let memo: String? // Maps to "notes"
    
    // Coding keys to map LunchMoney JSON fields to our struct
    enum CodingKeys: String, CodingKey {
        case id
        case dateString = "date"
        case amount
        case payee
        case memo = "notes"
    }
    
    // Custom decoding to handle Int ID -> String ID conversion
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle ID: LunchMoney sends Int, we want String
        if let intId = try? container.decode(Int.self, forKey: .id) {
            self.id = String(intId)
        } else {
            self.id = try container.decode(String.self, forKey: .id)
        }
        
        self.dateString = try container.decode(String.self, forKey: .dateString)
        self.amount = try? container.decode(String.self, forKey: .amount)
        self.payee = try? container.decode(String.self, forKey: .payee)
        self.memo = try? container.decode(String.self, forKey: .memo)
    }
    
    // Manual Init for "Add Manual Transaction"
    init(id: String, posted: TimeInterval, amount: String, description: String, payee: String, memo: String, transacted_at: TimeInterval) {
        self.id = id
        self.amount = amount
        self.payee = payee
        self.memo = memo
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateString = formatter.string(from: Date(timeIntervalSince1970: posted))
    }
    
    var decimalAmount: Decimal {
        guard let amt = amount else { return 0.0 }
        return Decimal(string: amt) ?? 0.0
    }
    
    var date: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString) ?? Date()
    }
    
    // UPDATED: Cleaning Logic
    var uiName: String {
        var cleanName = payee ?? "Unknown Transaction"
        
        // 1. Remove Prefixes
        cleanName = cleanName.replacingOccurrences(
            of: "^(CHECKCARD|PURCHASE|MOBILE PURCHASE) \\d+ ",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // 2. Remove " DES" and everything after
        if let range = cleanName.range(of: " DES") {
            cleanName = String(cleanName[..<range.lowerBound])
        }
        
        // 3. Remove "Conf#" and everything after
        cleanName = cleanName.replacingOccurrences(
            of: "[:;]?\\s*Conf#.*",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // 4. Remove Masking XXXXX...
        cleanName = cleanName.replacingOccurrences(
            of: "\\s?XXXXX[A-Z0-9]*",
            with: "",
            options: .regularExpression
        )
        
        return cleanName.trimmingCharacters(in: .whitespaces)
    }
    
    var cleanedDescription: String {
        return memo ?? ""
    }
}

class BudgetLogic {
    static func getPeriodLabel(for date: Date, bumpToNextPeriod: Bool = false) -> String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        
        var effectiveDate = date
        
        // PAYCHECK EXCEPTION:
        if bumpToNextPeriod && day == 23 {
            effectiveDate = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        let effectiveDay = calendar.component(.day, from: effectiveDate)
        let targetDate: Date
        
        if effectiveDay >= 24 {
            targetDate = calendar.date(byAdding: .month, value: 1, to: effectiveDate) ?? effectiveDate
        } else {
            targetDate = effectiveDate
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-25"
        return formatter.string(from: targetDate)
    }
    
    static func isPaycheck(_ transaction: SimpleFinTransaction) -> Bool {
        if let highPriority = getHighPriorityCategory(transaction), highPriority == "💰 Paycheck" {
            return true
        }
        if categorize(transaction) == "💰 Paycheck" {
            return true
        }
        return false
    }
    
    // UPDATED: Completely Generic Logic
    static func getHighPriorityCategory(_ transaction: SimpleFinTransaction) -> String? {
        let text = transaction.uiName.uppercased()
        
        // Generic Savings keyword
        if text.contains("SAVINGS") || text.contains("INVESTMENT") { return "🤑 Savings" }
        
        return nil
    }
    
    // UPDATED: Completely Generic Logic - Examples only
    static func categorize(_ transaction: SimpleFinTransaction) -> String {
        if let special = getHighPriorityCategory(transaction) { return special }
        
        let text = transaction.uiName.uppercased()
        
        // Common Groceries
        if text.contains("ALDI") || text.contains("FOOD LION") || text.contains("PUBLIX") || text.contains("KROGER") || text.contains("TRADER JOE") || text.contains("WHOLE FOODS") { return "🛒 Groceries" }
        
        // Common Shopping
        if text.contains("TARGET") || text.contains("WALMART") || text.contains("AMAZON") || text.contains("COSTCO") { return "🛍️ Shopping/Entertainment" }
        
        // Common Utilities/Household
        if text.contains("ENERGY") || text.contains("WATER") || text.contains("ELECTRIC") { return "🏠 Household" }
        
        // Common Subscriptions
        if text.contains("SPOTIFY") || text.contains("NETFLIX") || text.contains("HULU") || text.contains("APPLE") || text.contains("DISNEY") { return "🔄 Subscriptions" }
        
        // Common Dining
        if text.contains("STARBUCKS") || text.contains("MCDONALDS") || text.contains("CHICK-FIL-A") || text.contains("CHIPOTLE") || text.contains("UBER EATS") || text.contains("DOORDASH") { return "🍽️ Restaurants" }
        
        // Common Gas
        if text.contains("SHELL") || text.contains("EXXON") || text.contains("BP") || text.contains("WAWA") || text.contains("QT") || text.contains("QUIKTRIP") { return "⛽️ Gas" }
        
        // Generic Income keywords
        if text.contains("PAYROLL") || text.contains("DEPOSIT") || text.contains("SALARY") { return "💰 Paycheck" }
        
        return "❌ Uncategorized"
    }
}
