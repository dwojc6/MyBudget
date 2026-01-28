//
//  LunchMoneySetupView.swift
//  MyBudget
//
//  Created by David Wojcik on 1/25/26.
//

import SwiftUI

struct LunchMoneySetupView: View {
    @ObservedObject var store: BudgetStore
    @State private var apiToken: String = ""
    @State private var balanceString: String = ""
    @State private var startDate: Date = Date().addingTimeInterval(-30 * 24 * 60 * 60)
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Initial Setup")) {
                    Text("This balance will be the starting point for your budget history.")
                        .font(.caption).foregroundColor(.gray)
                    TextField("Current Bank Balance", text: $balanceString).keyboardType(.decimalPad)
                }
                Section(header: Text("LunchMoney Connection")) {
                    Text("Enter your LunchMoney Access Token.")
                        .font(.caption).foregroundColor(.gray)
                    TextField("Access Token", text: $apiToken).disableAutocorrection(true)
                }
                Section(header: Text("Import Settings")) {
                    DatePicker("Import Transactions From", selection: $startDate, displayedComponents: .date)
                }
                if let error = store.errorMessage {
                    Section(header: Text("Error")) { Text(error).foregroundColor(.red) }
                }
                Button(action: {
                    Task {
                        let initialBalance = Decimal(string: balanceString) ?? 0.0
                        await store.connectLunchMoney(token: apiToken, startDate: startDate, initialBalance: initialBalance)
                    }
                }) {
                    if store.isSyncing { ProgressView() } else { Text("Connect & Import").bold().frame(maxWidth: .infinity, alignment: .center) }
                }.disabled(apiToken.isEmpty)
            }
            .navigationTitle("Welcome")
        }
    }
}
