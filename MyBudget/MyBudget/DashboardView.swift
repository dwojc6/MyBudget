//
//  DashboardView.swift
//  MyBudget
//
//  Created by David Wojcik on 1/25/26.
//

import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: BudgetStore
    
    @State private var selectedTransaction: SimpleFinTransaction?
    @State private var selectedCategoryForEdit: String?
    @State private var showEditBudgetAlert = false
    @State private var editBudgetAmount = ""
    @State private var showAddCategory = false
    @State private var showEditBalance = false
    @State private var showAddTransaction = false
    @State private var editMode: EditMode = .inactive
    
    @State private var syncStatusMessage: String?
    @State private var syncStatusColor: Color = .green
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { store.changeMonth(by: -1) }) { Image(systemName: "chevron.left").padding() }
                    Spacer()
                    VStack {
                        Text(store.periodHeaderTitle).font(.caption).foregroundColor(.gray)
                        Text(store.periodLabel).font(.headline).bold()
                    }
                    Spacer()
                    Button(action: { store.changeMonth(by: 1) }) { Image(systemName: "chevron.right").padding() }
                }
                .background(Color(UIColor.systemBackground)).shadow(radius: 1).zIndex(1)
                
                // MAIN LIST
                ZStack(alignment: .bottomTrailing) {
                    List {
                    // 1. DASHBOARD SUMMARY & CATEGORIES
                    Group {
                        // 2x2 Grid
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                let isFirstPeriod: Bool = {
                                    guard let min = store.minDate else { return true }
                                    return store.getStartOfPeriod(for: store.selectedDate) <= store.getStartOfPeriod(for: min)
                                }()
                                
                                if isFirstPeriod {
                                    Button(action: { showEditBalance = true }) {
                                        SummaryView(title: "Balance", amount: store.beginningBalance, color: .blue, showEditIcon: true)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                } else {
                                    SummaryView(title: "Balance", amount: store.beginningBalance, color: .blue, showEditIcon: false)
                                }
                                
                                SummaryView(title: "Income", amount: store.currentPeriodIncome, color: .green)
                            }
                            
                            HStack(spacing: 12) {
                                SummaryView(title: "Spent", amount: store.currentPeriodSpent, color: .red)
                                SummaryView(title: "Savings", amount: store.totalLifetimeSavings, color: .purple)
                            }
                        }
                        .padding(.vertical, 6)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        
                        // Categories Header
                        HStack {
                            Text("Budget Categories").font(.title3).bold()
                            
                            Spacer()
                            
                            // NEW: Sort By Menu (Icon Only)
                            Menu {
                                Picker("Sort By", selection: $store.currentSortOption) {
                                    ForEach(BudgetStore.SortOption.allCases) { option in
                                        Text(option.rawValue).tag(option)
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                    .padding(6)
                                    .background(Color(UIColor.systemGray5))
                                    .cornerRadius(8)
                            }
                            .padding(.trailing, 8)
                            
                            Button(action: { showAddCategory = true }) {
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 5)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        
                        // Category Rows
                        ForEach(store.categoryNames, id: \.self) { category in
                            let spent = store.getSpent(for: category)
                            
                            // UPDATED: Check against "Uncategorized"
                            if !(category == "Uncategorized" && spent == 0) {
                                Button(action: {
                                    selectedCategoryForEdit = category
                                    let current = store.getBudget(for: category)
                                    let formatter = NumberFormatter()
                                    formatter.numberStyle = .decimal
                                    formatter.usesGroupingSeparator = false
                                    formatter.maximumFractionDigits = 2
                                    editBudgetAmount = formatter.string(from: current as NSDecimalNumber) ?? "\(current)"
                                    showEditBudgetAlert = true
                                }) {
                                        CategoryProgressRow(
                                            name: category,
                                            spent: spent,
                                            budget: store.getBudget(for: category),
                                            totalSpent: store.currentPeriodSpent,
                                            customColor: category.localizedCaseInsensitiveContains("savings") ? .purple : nil,
                                            // UPDATED: Check against emoji strings
                                            isIncome: (category == "💵 Income" || category == "💰 Paycheck")
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                            }
                        }
                        .onDelete(perform: store.deleteCategory)
                        .onMove(perform: store.moveCategories)
                        
                        // Ending Balance
                        HStack {
                            Text("Ending Balance").font(.headline)
                            Spacer()
                            Text(formatCurrency(store.endingBalance)).font(.headline).foregroundColor(store.endingBalance < 0 ? .red : .primary)
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(10)
                        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        
                        // Transactions Header
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Transactions").font(.title3).bold()
                                
                                Menu {
                                    Button("All Categories") { store.selectedCategoryFilter = nil }
                                    Divider()
                                    let sortedCategories = store.categoryNames.sorted {
                                        $0.displayWithoutEmoji.localizedCaseInsensitiveCompare($1.displayWithoutEmoji) == .orderedAscending
                                    }
                                    ForEach(sortedCategories, id: \.self) { cat in
                                        Button(cat.displayWithoutEmoji) { store.selectedCategoryFilter = cat }
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: store.selectedCategoryFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                        Text((store.selectedCategoryFilter ?? "All").displayWithoutEmoji)
                                            .font(.caption)
                                    }
                                    .padding(6)
                                    .background(Color(UIColor.systemGray5))
                                    .cornerRadius(8)
                                }
                                
                                Spacer()
                                
                                if store.isSyncing { ProgressView().scaleEffect(0.8) }
                                else {
                                    Button(action: {
                                        Task {
                                            let (message, isError) = await store.syncTransactions()
                                            
                                            syncStatusColor = isError ? .red : .green
                                            
                                            withAnimation {
                                                syncStatusMessage = message
                                            }
                                            if !isError {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                                    withAnimation { syncStatusMessage = nil }
                                                }
                                            } else {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                                    withAnimation { syncStatusMessage = nil }
                                                }
                                            }
                                        }
                                    }) {
                                        Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(.gray)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                
                                Button(action: { showAddTransaction = true }) {
                                    Image(systemName: "plus").font(.title3).foregroundColor(.blue)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.leading, 8)
                            }
                            
                            if let message = syncStatusMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(syncStatusColor)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.top, 10)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    
                    // 2. TRANSACTIONS SECTION
                    Section {
                        let visibleTransactions = store.getFilteredTransactions()
                        
                        if visibleTransactions.isEmpty {
                            Text("No transactions found.")
                                .font(.caption).foregroundColor(.gray)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(visibleTransactions) { transaction in
                                Button(action: { selectedTransaction = transaction }) {
                                    TransactionRow(transaction: transaction, category: store.getCategory(for: transaction))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                            }
                            .onDelete { indexSet in
                                indexSet.forEach { index in
                                    let txnToDelete = visibleTransactions[index]
                                    store.deleteTransaction(txnToDelete)
                                }
                            }
                        }
                    }
                    
                    Section {
                        Color.clear.frame(height: 50)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    }
                    .listStyle(.plain)
                    .background(Color(UIColor.systemGroupedBackground))
                    .environment(\.editMode, $editMode)
                    
                    Button(action: { showAddTransaction = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $selectedTransaction) { t in EditTransactionView(store: store, transaction: t) }
            .sheet(isPresented: $showAddCategory) { AddCategoryView(store: store) }
            .sheet(isPresented: $showEditBalance) { EditBalanceView(store: store) }
            .sheet(isPresented: $showAddTransaction) { AddTransactionView(store: store) }
            .alert("Edit Budget", isPresented: $showEditBudgetAlert) {
                TextField("Amount", text: $editBudgetAmount)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    if let category = selectedCategoryForEdit,
                       let decimal = Decimal(string: editBudgetAmount) {
                        store.updateBudget(for: category, amount: decimal)
                    }
                }
            } message: {
                Text("Enter new monthly budget for \(selectedCategoryForEdit ?? "")")
            }
        }
    }
}
