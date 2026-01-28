//
//  LunchMoneyService.swift
//  MyBudget
//
//  Created by David Wojcik on 1/23/26.
//

import Foundation

class LunchMoneyService {
    
    // TRIGGER PLAID SYNC
    func triggerPlaidSync(apiKey: String) async throws {
        // Endpoint to trigger Plaid fetch
        let url = URL(string: "https://api.lunchmoney.dev/v2/plaid_accounts/fetch")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        print("Triggering Plaid Sync: \(url)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // UPDATED: Accept both 200 (OK) and 202 (Accepted/Queued) as success
        guard let httpResponse = response as? HTTPURLResponse,
              (httpResponse.statusCode == 200 || httpResponse.statusCode == 202) else {
             
             // Try to decode error message if available
             if let errorResponse = try? JSONDecoder().decode(LunchMoneyErrorResponse.self, from: data) {
                 print("Plaid Sync Error: \(errorResponse.error ?? "Unknown")")
                 // We still throw if it's not 200 or 202
                 throw SimpleFinError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
             }
             throw SimpleFinError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        print("Plaid Sync Triggered Successfully (Status: \(httpResponse.statusCode))")
    }
    
    // FETCH DATA FROM LUNCHMONEY V2 API
    func fetchTransactions(apiKey: String, startDate: Date, endDate: Date = Date()) async throws -> ([SimpleFinTransaction], [String]) {
        var components = URLComponents(string: "https://api.lunchmoney.dev/v2/transactions")!
        
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
        
        print("Fetching from: \(url)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(LunchMoneyErrorResponse.self, from: data) {
                return ([], [errorResponse.error ?? "Unknown API Error: \(String(data: data, encoding: .utf8) ?? "")"])
            }
            throw SimpleFinError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        struct LunchMoneyRoot: Codable {
            let transactions: [LunchMoneyRawTransaction]
        }
        
        do {
            let root = try JSONDecoder().decode(LunchMoneyRoot.self, from: data)
            
            // Map Raw transactions to App Model, INVERTING the amount
            let cleanTransactions = root.transactions.map { raw -> SimpleFinTransaction in
                let originalAmount = Decimal(string: raw.amount) ?? 0.0
                let invertedAmount = originalAmount * -1
                
                return SimpleFinTransaction(
                    id: String(raw.id),
                    posted: 0,
                    amount: "\(invertedAmount)",
                    description: raw.notes ?? "",
                    payee: raw.payee ?? "",
                    memo: raw.notes ?? "",
                    transacted_at: 0
                ).updatingDate(raw.date)
            }
            
            return (cleanTransactions, [])
        } catch {
            print("Decoding Failed: \(error)")
            throw SimpleFinError.decodingError(error.localizedDescription)
        }
    }
    
    // Internal Helper Structs
    private struct LunchMoneyErrorResponse: Codable {
        let error: String?
    }
}

// Internal Struct to match LunchMoney JSON exactly
private struct LunchMoneyRawTransaction: Codable {
    let id: Int
    let date: String
    let amount: String
    let payee: String?
    let notes: String?
}

// Extension to help set the date string on the model during mapping
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
            transacted_at: dateObj.timeIntervalSince1970
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
