//
//  BudgetModels.swift
//  MyBudget
//
//  Created by David Wojcik III on 1/23/26.
//

import Foundation

// NEW: Model for Categories
struct LunchMoneyCategory: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let is_income: Bool
    let exclude_from_budget: Bool
    let children: [LunchMoneyCategory]? // Nested categories
}

struct SimpleFinTransaction: Codable, Identifiable {
    let id: String
    let dateString: String
    let amount: String?
    let payee: String?
    let memo: String?
    let categoryId: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case dateString = "date"
        case amount
        case payee
        case memo = "notes"
        case categoryId = "category_id"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decode(Int.self, forKey: .id) {
            self.id = String(intId)
        } else {
            self.id = try container.decode(String.self, forKey: .id)
        }
        self.dateString = try container.decode(String.self, forKey: .dateString)
        self.amount = try? container.decode(String.self, forKey: .amount)
        self.payee = try? container.decode(String.self, forKey: .payee)
        self.memo = try? container.decode(String.self, forKey: .memo)
        self.categoryId = try? container.decode(Int.self, forKey: .categoryId)
    }
    
    init(id: String, posted: TimeInterval, amount: String, description: String, payee: String, memo: String, transacted_at: TimeInterval, categoryId: Int? = nil) {
        self.id = id
        self.amount = amount
        self.payee = payee
        self.memo = memo
        self.categoryId = categoryId
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
    
    var uiName: String {
        var cleanName = payee ?? "Unknown Transaction"
        cleanName = cleanName.replacingOccurrences(of: "^(CHECKCARD|PURCHASE|MOBILE PURCHASE) \\d+ ", with: "", options: [.regularExpression, .caseInsensitive])
        if let range = cleanName.range(of: " DES") { cleanName = String(cleanName[..<range.lowerBound]) }
        cleanName = cleanName.replacingOccurrences(of: "[:;]?\\s*Conf#.*", with: "", options: [.regularExpression, .caseInsensitive])
        cleanName = cleanName.replacingOccurrences(of: "\\s?XXXXX[A-Z0-9]*", with: "", options: .regularExpression)
        return cleanName.trimmingCharacters(in: .whitespaces)
    }
    
    var cleanedDescription: String { return memo ?? "" }
}
