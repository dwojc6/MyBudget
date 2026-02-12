//
//  LunchMoneyService.swift
//  MyBudget
//
//  Created by David Wojcik on 1/23/26.
//

import Foundation

class LunchMoneyService {
    private struct LunchMoneyRoot: Codable {
        let transactions: [LunchMoneyRawTransaction]
    }

    private let iso8601WithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let iso8601NoFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    // 0. FETCH ACCOUNT PROFILE
    func fetchMe(apiKey: String) async throws -> LunchMoneyAccountProfile {
        let url = URL(string: "https://api.lunchmoney.dev/v2/me")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorMessage = parseLunchMoneyError(from: data) {
                throw SimpleFinError.decodingError(errorMessage)
            }
            throw SimpleFinError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        do {
            return try JSONDecoder().decode(LunchMoneyAccountProfile.self, from: data)
        } catch {
            throw SimpleFinError.decodingError(error.localizedDescription)
        }
    }

    // 1. FETCH CATEGORIES
    func fetchCategories(apiKey: String) async throws -> [LunchMoneyCategory] {
        let url = URL(string: "https://api.lunchmoney.dev/v2/categories")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        print("Fetching Categories: \(url)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SimpleFinError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        struct CategoriesRoot: Codable {
            let categories: [LunchMoneyCategory]
        }
        
        do {
            let root = try JSONDecoder().decode(CategoriesRoot.self, from: data)
            return root.categories
        } catch {
            print("Category Decoding Failed: \(error)")
            return []
        }
    }
    
    // 2. FETCH BUDGET SUMMARY (UPDATED: Returns Aligned Status)
    func fetchBudgetSummary(apiKey: String, startDate: Date, endDate: Date) async throws -> (aligned: Bool, categories: [LunchMoneySummaryCategory]) {
        var components = URLComponents(string: "https://api.lunchmoney.dev/v2/summary")!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        components.queryItems = [
            URLQueryItem(name: "start_date", value: dateFormatter.string(from: startDate)),
            URLQueryItem(name: "end_date", value: dateFormatter.string(from: endDate))
        ]
        
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        print("Fetching Summary: \(url)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SimpleFinError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        struct SummaryRoot: Codable {
            let aligned: Bool
            let categories: [LunchMoneySummaryCategory]?
        }
        
        do {
            let root = try JSONDecoder().decode(SummaryRoot.self, from: data)
            return (root.aligned, root.categories ?? [])
        } catch {
            print("Summary Decoding Failed: \(error)")
            return (false, [])
        }
    }
    
    // 3. TRIGGER PLAID SYNC
    func triggerPlaidSync(apiKey: String) async throws {
        let url = URL(string: "https://api.lunchmoney.dev/v2/plaid_accounts/fetch")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (httpResponse.statusCode == 200 || httpResponse.statusCode == 202) else {
             if let errorResponse = try? JSONDecoder().decode(LunchMoneyErrorResponse.self, from: data) {
                 print("Plaid Sync Error: \(errorResponse.error ?? "Unknown")")
                 throw SimpleFinError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
             }
             throw SimpleFinError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
    
    // 4. FETCH TRANSACTIONS
    func fetchTransactions(apiKey: String, startDate: Date, endDate: Date = Date()) async throws -> ([SimpleFinTransaction], [String]) {
        do {
            async let pendingRaw = fetchTransactionsRaw(apiKey: apiKey, startDate: startDate, endDate: endDate, isPending: true)
            async let postedRaw = fetchTransactionsRaw(apiKey: apiKey, startDate: startDate, endDate: endDate, isPending: false)

            let (pendingTransactions, postedTransactions) = try await (pendingRaw, postedRaw)

            // Non-pending should win when the same Lunch Money transaction id appears in both sets.
            var mergedById: [Int: LunchMoneyRawTransaction] = [:]
            for raw in pendingTransactions { mergedById[raw.id] = raw }
            for raw in postedTransactions { mergedById[raw.id] = raw }

            var merged = Array(mergedById.values)

            // If a posted transaction references a pending transaction id from Plaid metadata,
            // remove the pending version so the cleared transaction replaces it.
            let replacedPendingIds = Set(postedTransactions.compactMap { $0.plaid_metadata?.pending_transaction_id })
            merged.removeAll { raw in
                guard raw.is_pending == true else { return false }
                if replacedPendingIds.contains(String(raw.id)) { return true }
                if let externalId = raw.external_id, replacedPendingIds.contains(externalId) { return true }
                return false
            }

            // If both pending + posted share the same external id, keep posted.
            var byExternalId: [String: LunchMoneyRawTransaction] = [:]
            var noExternalId: [LunchMoneyRawTransaction] = []
            for raw in merged {
                guard let externalId = raw.external_id, !externalId.isEmpty else {
                    noExternalId.append(raw)
                    continue
                }
                if let existing = byExternalId[externalId] {
                    byExternalId[externalId] = preferredTransaction(existing: existing, candidate: raw)
                } else {
                    byExternalId[externalId] = raw
                }
            }

            let dedupedRaw = noExternalId + Array(byExternalId.values)

            let cleanTransactions = dedupedRaw.map { raw -> SimpleFinTransaction in
                let originalAmount = Decimal(string: raw.amount) ?? 0.0
                let invertedAmount = originalAmount * -1
                let merchantName = raw.plaid_metadata?.merchant_name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let payee = (merchantName?.isEmpty == false) ? merchantName : raw.payee

                return SimpleFinTransaction(
                    id: String(raw.id),
                    dateString: raw.date,
                    amount: "\(invertedAmount)",
                    payee: payee,
                    memo: raw.notes ?? "",
                    categoryId: raw.category_id,
                    createdAtString: raw.created_at,
                    isPending: raw.is_pending,
                    externalId: raw.external_id,
                    pendingTransactionExternalId: raw.plaid_metadata?.pending_transaction_id
                )
            }

            return (cleanTransactions, [])
        } catch {
            print("Transaction Decoding Failed: \(error)")
            throw SimpleFinError.decodingError(error.localizedDescription)
        }
    }

    private func fetchTransactionsRaw(
        apiKey: String,
        startDate: Date,
        endDate: Date,
        isPending: Bool
    ) async throws -> [LunchMoneyRawTransaction] {
        var components = URLComponents(string: "https://api.lunchmoney.dev/v2/transactions")!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        components.queryItems = [
            URLQueryItem(name: "start_date", value: dateFormatter.string(from: startDate)),
            URLQueryItem(name: "end_date", value: dateFormatter.string(from: endDate)),
            URLQueryItem(name: "is_pending", value: isPending ? "true" : "false"),
            URLQueryItem(name: "include_metadata", value: "true")
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        print("Fetching Transactions: \(url)")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(LunchMoneyErrorResponse.self, from: data) {
                throw SimpleFinError.decodingError(errorResponse.error ?? "Unknown API Error")
            }
            throw SimpleFinError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let root = try JSONDecoder().decode(LunchMoneyRoot.self, from: data)
        return root.transactions
    }

    private func preferredTransaction(existing: LunchMoneyRawTransaction, candidate: LunchMoneyRawTransaction) -> LunchMoneyRawTransaction {
        let existingPending = existing.is_pending ?? false
        let candidatePending = candidate.is_pending ?? false

        if existingPending && !candidatePending { return candidate }
        if !existingPending && candidatePending { return existing }

        let existingCreatedAt = parseCreatedAt(existing.created_at)
        let candidateCreatedAt = parseCreatedAt(candidate.created_at)
        if candidateCreatedAt != existingCreatedAt {
            return candidateCreatedAt > existingCreatedAt ? candidate : existing
        }

        return candidate.id > existing.id ? candidate : existing
    }

    private func parseCreatedAt(_ value: String?) -> Date {
        guard let value else { return .distantPast }
        if let date = iso8601WithFractions.date(from: value) { return date }
        if let date = iso8601NoFractions.date(from: value) { return date }
        return .distantPast
    }

    // 5. UPDATE TRANSACTION PAYEE
    func updateTransactionPayee(apiKey: String, transactionId: String, payee: String) async throws {
        let url = URL(string: "https://api.lunchmoney.dev/v2/transactions/\(transactionId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "payee": payee
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let errorMessage = parseLunchMoneyError(from: data) {
                throw SimpleFinError.decodingError(errorMessage)
            }
            throw SimpleFinError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
    
    private struct LunchMoneyErrorResponse: Codable {
        let error: String?
    }

    private func parseLunchMoneyError(from data: Data) -> String? {
        if let errorResponse = try? JSONDecoder().decode(LunchMoneyErrorResponse.self, from: data),
           let error = errorResponse.error {
            return error
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? String { return error }
            if let errors = json["error"] as? [String] { return errors.joined(separator: ", ") }
        }
        return nil
    }
}

// Internal Structs
struct LunchMoneySummaryCategory: Codable {
    let category_id: Int
    let totals: LunchMoneySummaryTotals
}

struct LunchMoneySummaryTotals: Codable {
    let budgeted: Double?
}

private struct LunchMoneyRawTransaction: Codable {
    let id: Int
    let date: String
    let amount: String
    let payee: String?
    let notes: String?
    let category_id: Int?
    let created_at: String?
    let is_pending: Bool?
    let external_id: String?
    let plaid_metadata: LunchMoneyPlaidMetadata?
}

private struct LunchMoneyPlaidMetadata: Codable {
    let merchant_name: String?
    let pending_transaction_id: String?
}

private extension SimpleFinTransaction {
    func updatingDate(_ dateString: String) -> SimpleFinTransaction {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateObj = formatter.date(from: dateString) ?? Date()
        
        return SimpleFinTransaction(
            id: self.id,
            posted: dateObj.timeIntervalSince1970,
            amount: self.amount ?? "0",
            description: self.memo ?? "",
            payee: self.payee ?? "",
            memo: self.memo ?? "",
            transacted_at: dateObj.timeIntervalSince1970,
            categoryId: self.categoryId
        )
    }
}

enum SimpleFinError: Error, LocalizedError {
    case invalidToken, claimFailed, invalidResponse, invalidAccessUrl, apiError(Int), decodingError(String)
    var errorDescription: String? {
        switch self {
        case .invalidToken: return "Invalid setup token."
        case .claimFailed: return "Token claim failed."
        case .invalidResponse: return "Invalid server response."
        case .invalidAccessUrl: return "Invalid access URL."
        case .apiError(let code): return "API Error: \(code)"
        case .decodingError(let msg): return "Data Error: \(msg)"
        }
    }
}
