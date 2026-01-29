//
//  LunchMoneySetupView.swift
//  MyBudget
//
//  Created by David Wojcik III on 1/25/26.
//

import SwiftUI

struct LunchMoneySetupView: View {
    @ObservedObject var store: BudgetStore
    @State private var apiToken: String = ""
    @State private var balanceString: String = ""
    
    // Default to 1st of current month -> End of current month
    @State private var budgetStartDate: Date = {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        return Calendar.current.date(from: components) ?? Date()
    }()
    
    @State private var budgetEndDate: Date = {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        if let start = Calendar.current.date(from: components) {
            return Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? Date()
        }
        return Date()
    }()
    
    @State private var importStartDate: Date = Date().addingTimeInterval(-30 * 24 * 60 * 60)
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Initial Setup")) {
                    Text("This balance will be the starting point for your budget history.")
                        .font(.caption).foregroundColor(.gray)
                    TextField("Current Bank Balance", text: $balanceString).keyboardType(.decimalPad)
                }
                
                Section(header: Text("Lunch Money Connection")) {
                    Text("Enter your Lunch Money Access Token.")
                        .font(.caption).foregroundColor(.gray)
                    TextField("Access Token", text: $apiToken).disableAutocorrection(true)
                }
                
                Section(header: Text("Current Budget Period")) {
                    Text("Select the dates for your CURRENT budgeting period. This must match Lunch Money exactly.")
                        .font(.caption).foregroundColor(.gray)
                    DatePicker("Period Start", selection: $budgetStartDate, displayedComponents: .date)
                    DatePicker("Period End", selection: $budgetEndDate, displayedComponents: .date)
                }
                
                Section(header: Text("Import Transactions From")) {
                    DatePicker("Start Date", selection: $importStartDate, displayedComponents: .date)
                }
                
                Button(action: {
                    Task {
                        let initialBalance = Decimal(string: balanceString) ?? 0.0
                        await store.connectLunchMoney(
                            token: apiToken,
                            initialBalance: initialBalance,
                            importStartDate: importStartDate,
                            periodStart: budgetStartDate,
                            periodEnd: budgetEndDate
                        )
                    }
                }) {
                    if store.isSyncing { ProgressView() } else { Text("Connect & Import").bold().frame(maxWidth: .infinity, alignment: .center) }
                }.disabled(apiToken.isEmpty)
            }
            .navigationTitle("Welcome")
            // NEW: Alert Popup
            .alert("Configuration Error", isPresented: $store.showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(store.errorMessage ?? "An unknown error occurred.")
            }
        }
    }
}
