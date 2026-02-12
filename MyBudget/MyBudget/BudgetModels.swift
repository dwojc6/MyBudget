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

struct LunchMoneyAccountProfile: Codable {
    let name: String?
    let email: String?
    let budgetName: String?

    init(name: String?, email: String?, budgetName: String?) {
        self.name = name
        self.email = email
        self.budgetName = budgetName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        name = container.decodeFirstString(for: ["name", "user_name"])
        email = container.decodeFirstString(for: ["email", "user_email"])

        let directBudgetName = container.decodeFirstString(for: [
            "budget_name",
            "budgetName",
            "account_name",
            "budget_account_name",
            "primary_budget_name"
        ])

        if let directBudgetName {
            budgetName = directBudgetName
        } else if let budgetObj = try? container.decode([String: String].self, forKey: DynamicCodingKey("budget")) {
            budgetName = budgetObj["name"] ?? budgetObj["budget_name"] ?? budgetObj["title"]
        } else {
            budgetName = nil
        }
    }

    struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(_ string: String) {
            self.stringValue = string
            self.intValue = nil
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }
}

private extension KeyedDecodingContainer where Key == LunchMoneyAccountProfile.DynamicCodingKey {
    func decodeFirstString(for keys: [String]) -> String? {
        for key in keys {
            let codingKey = LunchMoneyAccountProfile.DynamicCodingKey(key)
            if let value = try? decode(String.self, forKey: codingKey) {
                return value
            }
        }
        return nil
    }
}

struct SimpleFinTransaction: Codable, Identifiable {
    let id: String
    let dateString: String
    let amount: String?
    let payee: String?
    let memo: String?
    let categoryId: Int?
    let createdAtString: String?
    let isPending: Bool?
    let externalId: String?
    let pendingTransactionExternalId: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case dateString = "date"
        case amount
        case payee
        case memo = "notes"
        case categoryId = "category_id"
        case createdAtString = "created_at"
        case isPending = "is_pending"
        case externalId = "external_id"
        case pendingTransactionExternalId = "pending_transaction_external_id"
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
        self.createdAtString = try? container.decode(String.self, forKey: .createdAtString)
        self.isPending = try? container.decode(Bool.self, forKey: .isPending)
        self.externalId = try? container.decode(String.self, forKey: .externalId)
        self.pendingTransactionExternalId = try? container.decode(String.self, forKey: .pendingTransactionExternalId)
    }

    init(
        id: String,
        dateString: String,
        amount: String?,
        payee: String?,
        memo: String?,
        categoryId: Int?,
        createdAtString: String? = nil,
        isPending: Bool? = nil,
        externalId: String? = nil,
        pendingTransactionExternalId: String? = nil
    ) {
        self.id = id
        self.dateString = dateString
        self.amount = amount
        self.payee = payee
        self.memo = memo
        self.categoryId = categoryId
        self.createdAtString = createdAtString
        self.isPending = isPending
        self.externalId = externalId
        self.pendingTransactionExternalId = pendingTransactionExternalId
    }
    
    init(id: String, posted: TimeInterval, amount: String, description: String, payee: String, memo: String, transacted_at: TimeInterval, categoryId: Int? = nil) {
        self.id = id
        self.amount = amount
        self.payee = payee
        self.memo = memo
        self.categoryId = categoryId
        self.createdAtString = SimpleFinTransaction.iso8601Formatter.string(from: Date(timeIntervalSince1970: transacted_at))
        self.isPending = false
        self.externalId = nil
        self.pendingTransactionExternalId = nil
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

    var createdAtDate: Date {
        if let createdAtString {
            if let parsed = SimpleFinTransaction.iso8601Formatter.date(from: createdAtString) {
                return parsed
            }
            if let parsed = SimpleFinTransaction.iso8601NoFractionFormatter.date(from: createdAtString) {
                return parsed
            }
        }
        return date
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

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601NoFractionFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

extension SimpleFinTransaction {
    func withPayee(_ newPayee: String) -> SimpleFinTransaction {
        return SimpleFinTransaction(
            id: id,
            dateString: dateString,
            amount: amount,
            payee: newPayee,
            memo: memo,
            categoryId: categoryId,
            createdAtString: createdAtString,
            isPending: isPending,
            externalId: externalId,
            pendingTransactionExternalId: pendingTransactionExternalId
        )
    }
}
