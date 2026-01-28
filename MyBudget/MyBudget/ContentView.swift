//
//  ContentView.swift
//  MyBudget
//
//  Created by David Wojcik on 1/23/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject var store = BudgetStore()
    
    var body: some View {
        Group {
            if store.accessUrl == nil {
                LunchMoneySetupView(store: store)
            } else {
                DashboardView(store: store)
            }
        }
    }
}

extension String: Identifiable { public var id: String { return self } }
func formatCurrency(_ amount: Decimal) -> String { let formatter = NumberFormatter(); formatter.numberStyle = .currency; return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00" }
