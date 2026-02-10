//
//  ReportsView.swift
//  MyBudget
//
//  Created by David Wojcik on 2/10/26.
//

import SwiftUI

private enum ReportRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case custom = "Custom"

    var id: String { rawValue }
}

struct ReportsView: View {
    @ObservedObject var store: BudgetStore
    @State private var selectedRange: ReportRange = .month
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()

    private var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()

        switch selectedRange {
        case .week:
            if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
                return (interval.start, interval.end)
            }
        case .month:
            if let interval = calendar.dateInterval(of: .month, for: now) {
                return (interval.start, interval.end)
            }
        case .year:
            if let interval = calendar.dateInterval(of: .year, for: now) {
                return (interval.start, interval.end)
            }
        case .custom:
            let start = calendar.startOfDay(for: min(customStartDate, customEndDate))
            let endDay = calendar.startOfDay(for: max(customStartDate, customEndDate))
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return (start, end)
        }

        return (now, now)
    }

    private var filteredTransactions: [SimpleFinTransaction] {
        let range = dateRange
        return store.transactions.filter { txn in
            guard !store.hiddenTransactionIDs.contains(txn.id) else { return false }
            return txn.date >= range.start && txn.date < range.end
        }
    }

    private var totalIncome: Decimal {
        filteredTransactions
            .filter { $0.decimalAmount > 0 }
            .reduce(0) { $0 + $1.decimalAmount }
    }

    private var totalExpenses: Decimal {
        let sum = filteredTransactions
            .filter { $0.decimalAmount < 0 }
            .reduce(0) { $0 + $1.decimalAmount }
        return abs(sum)
    }

    private var totalBalance: Decimal {
        totalIncome - totalExpenses
    }

    private var categorySpend: [(String, Decimal, Decimal)] {
        var totals: [String: Decimal] = [:]
        for txn in filteredTransactions where txn.decimalAmount < 0 {
            let category = store.getCategory(for: txn)
            if store.isIncomeCategory(category) { continue }
            totals[category, default: 0] += abs(txn.decimalAmount)
        }
        let total = max(totalExpenses, 0.01)
        return totals
            .sorted { $0.value > $1.value }
            .map { (name, amount) in
                let pct = (amount / total) * 100
                return (name, amount, pct)
            }
    }


    var body: some View {
        NavigationView {
            List {
                Section {
                    AdaptivePillSelector(
                        items: ReportRange.allCases,
                        title: { $0.rawValue },
                        isSelected: { $0 == selectedRange },
                        onSelect: { selectedRange = $0 }
                    )
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                
                if selectedRange == .custom {
                    Section {
                        HStack(spacing: 10) {
                            DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(Color.clear)
                                .clipShape(Capsule())
                            
                            DatePicker("End", selection: $customEndDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(Color.clear)
                                .clipShape(Capsule())
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                }
                
                Section(header: Text("Summary")) {
                    VStack(spacing: 20) {
                        HStack {
                            Text("Total Income")
                            Spacer()
                            Text(formatCurrency(totalIncome))
                                .foregroundColor(.green)
                        }
                        HStack {
                            Text("Total Expenses")
                            Spacer()
                            Text(formatCurrency(totalExpenses))
                                .foregroundColor(.red)
                        }
                        Divider()
                        HStack {
                            Text("Balance")
                            Spacer()
                            Text(formatCurrency(totalBalance))
                                .foregroundColor(totalBalance < 0 ? .red : .blue)
                        }
                    }
                    .font(.title3)
                    .padding(12)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                
                Section(header: Text("Category Spending")) {
                    if categorySpend.isEmpty {
                        Text("No expenses in this timeframe.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(categorySpend, id: \.0) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(item.0)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(formatCurrency(item.1))
                                        Text("\(String(format: "%.0f", NSDecimalNumber(decimal: item.2).doubleValue))%")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                GeometryReader { geometry in
                                    let progress = min(max(NSDecimalNumber(decimal: item.2).doubleValue / 100.0, 0), 1)
                                    let barWidth = CGFloat(progress) * geometry.size.width
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 5)
                                            .frame(height: 8)
                                            .foregroundColor(Color.gray.opacity(0.2))
                                        RoundedRectangle(cornerRadius: 5)
                                            .frame(width: barWidth, height: 8)
                                            .foregroundColor(.blue)
                                    }
                                }
                                .frame(height: 8)
                            }
                            .padding(12)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Reports")
        }
    }
}
