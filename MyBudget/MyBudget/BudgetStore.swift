//
//  BudgetStore.swift
//  MyBudget
//
//  Created by David Wojcik on 1/23/26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class BudgetStore: ObservableObject {
    @Published var transactions: [SimpleFinTransaction] = [] {
        didSet {
            updatePaycheckDates()
            if let encoded = try? JSONEncoder().encode(transactions) {
                UserDefaults.standard.set(encoded, forKey: "SavedTransactions")
            }
        }
    }
    
    private var paycheckDates: Set<String> = []
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    @Published var selectedDate: Date = Date()
    @Published var startingBalance: Decimal = 0.0
    @Published var selectedCategoryFilter: String? = nil
    
    @Published var hiddenTransactionIDs: Set<String> = [] {
        didSet {
            let array = Array(hiddenTransactionIDs)
            UserDefaults.standard.set(array, forKey: "HiddenTxns")
        }
    }
    
    @Published var payeeRules: [String: String] = [:] {
        didSet { UserDefaults.standard.set(payeeRules, forKey: "PayeeRules") }
    }
    
    @Published var transactionCategoryOverrides: [String: String] = [:] {
        didSet { UserDefaults.standard.set(transactionCategoryOverrides, forKey: "TxnOverrides") }
    }
    
    @Published var periodBudgets: [String: [String: Decimal]] = [:] {
        didSet {
            if let encoded = try? JSONEncoder().encode(periodBudgets) {
                UserDefaults.standard.set(encoded, forKey: "PeriodBudgets")
            }
        }
    }
    
    @Published var categoryOrder: [String] = [] {
        didSet { UserDefaults.standard.set(categoryOrder, forKey: "CategoryOrder") }
    }
    
    @Published var minDate: Date? {
        didSet {
            if let date = minDate {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "MinDate")
            }
        }
    }
    
    @Published var accessUrl: String? {
        didSet { UserDefaults.standard.set(accessUrl, forKey: "LunchMoneyToken") }
    }
    @Published var isSyncing = false
    @Published var errorMessage: String?
    
    // UPDATED: Zeroed out amounts for public release
    @Published var defaultCategoryBudgets: [String: Decimal] = [
        "💰 Paycheck": 0.00,
        "💵 Income": 0.00,
        "🛒 Groceries": 0.00,
        "🍽️ Restaurants": 0.00,
        "⛽️ Gas": 0.00,
        "🛍️ Shopping/Entertainment": 0.00,
        "🏠 Household": 0.00,
        "🍼 Daycare": 0.00,
        "🚗 Car Loan": 0.00,
        "🔄 Subscriptions": 0.00,
        "🤑 Savings": 0.00,
        "💸 CC Payment": 0.00,
        "❌ Uncategorized": 0.00
    ] {
        didSet {
            if let encoded = try? JSONEncoder().encode(defaultCategoryBudgets) {
                UserDefaults.standard.set(encoded, forKey: "DefaultCategoryBudgets")
            }
        }
    }
    
    private let service = LunchMoneyService()
    var categoryNames: [String] { return categoryOrder }
    
    init() {
        self.accessUrl = UserDefaults.standard.string(forKey: "LunchMoneyToken")
        let savedBalance = UserDefaults.standard.double(forKey: "StartingBalance")
        if savedBalance != 0.0 { self.startingBalance = Decimal(savedBalance) }
        
        let savedMin = UserDefaults.standard.double(forKey: "MinDate")
        if savedMin > 0 { self.minDate = Date(timeIntervalSince1970: savedMin) }
        
        if let savedRules = UserDefaults.standard.object(forKey: "PayeeRules") as? [String: String] {
            self.payeeRules = savedRules
        }
        
        if let savedOverrides = UserDefaults.standard.object(forKey: "TxnOverrides") as? [String: String] {
            self.transactionCategoryOverrides = savedOverrides
        }
        
        if let savedHidden = UserDefaults.standard.array(forKey: "HiddenTxns") as? [String] {
            self.hiddenTransactionIDs = Set(savedHidden)
        }
        
        if let savedData = UserDefaults.standard.data(forKey: "PeriodBudgets"),
           let decoded = try? JSONDecoder().decode([String: [String: Decimal]].self, from: savedData) {
            self.periodBudgets = decoded
        }
        
        if let savedDefaultsData = UserDefaults.standard.data(forKey: "DefaultCategoryBudgets"),
           let decodedDefaults = try? JSONDecoder().decode([String: Decimal].self, from: savedDefaultsData) {
            self.defaultCategoryBudgets = decodedDefaults
        }
        
        if let savedOrder = UserDefaults.standard.array(forKey: "CategoryOrder") as? [String] {
            self.categoryOrder = savedOrder
            // Ensure new emoji keys exist if migrating from old order
            for key in defaultCategoryBudgets.keys {
                if !self.categoryOrder.contains(key) {
                    self.categoryOrder.append(key)
                }
            }
        } else {
            self.categoryOrder = defaultCategoryBudgets.keys.sorted()
        }
        
        if let savedData = UserDefaults.standard.data(forKey: "SavedTransactions"),
           let decoded = try? JSONDecoder().decode([SimpleFinTransaction].self, from: savedData) {
            self.transactions = decoded
            self.updatePaycheckDates()
        }
        
        if let min = self.minDate {
             let currentStart = getStartOfPeriod(for: selectedDate)
             let minStart = getStartOfPeriod(for: min)
             if currentStart < minStart {
                 self.selectedDate = min
             }
        }
    }
    
    private func updatePaycheckDates() {
        let dates = transactions
            .filter { BudgetLogic.isPaycheck($0) }
            .map { dayFormatter.string(from: $0.date) }
        self.paycheckDates = Set(dates)
    }
    
    func isTransactionOnPayday(_ transaction: SimpleFinTransaction) -> Bool {
        let key = dayFormatter.string(from: transaction.date)
        return paycheckDates.contains(key)
    }
    
    func deleteCategory(at offsets: IndexSet) {
        let categoriesToDelete = offsets.map { categoryOrder[$0] }
        categoryOrder.remove(atOffsets: offsets)
        for category in categoriesToDelete {
            defaultCategoryBudgets.removeValue(forKey: category)
        }
    }
    
    func moveCategories(from source: IndexSet, to destination: Int) {
        categoryOrder.move(fromOffsets: source, toOffset: destination)
    }
    
    // CONNECT (SETUP)
    func connectLunchMoney(token: String, startDate: Date, initialBalance: Decimal) async {
        isSyncing = true
        errorMessage = nil
        do {
            // Initial sync: Pull from user selected Start Date -> Today
            let (fetchedTransactions, _) = try await service.fetchTransactions(apiKey: token, startDate: startDate, endDate: Date())
            
            self.setStartingBalance(initialBalance)
            self.minDate = startDate
            self.transactions = fetchedTransactions
            self.accessUrl = token // Store API Key
            
            if let lastTxn = fetchedTransactions.max(by: { $0.date < $1.date }) {
                self.selectedDate = lastTxn.date
            } else {
                 self.selectedDate = startDate
            }
            
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        isSyncing = false
    }
    
    // SYNC (DASHBOARD)
    func syncTransactions(startDate: Date? = nil) async -> (String, Bool) {
        guard let token = accessUrl else { return ("No access token", true) }
        isSyncing = true
        
        let fetchStartDate: Date
        if let inputDate = startDate {
            fetchStartDate = inputDate
        } else {
            let calendar = Calendar.current
            fetchStartDate = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        }
        
        var resultMessage = ""
        var isError = false
        
        do {
            // 1. Trigger Plaid Sync
            try await service.triggerPlaidSync(apiKey: token)
            
            // Optional: wait briefly
            try await Task.sleep(nanoseconds: 1 * 1_000_000_000)
            
            // 2. Fetch Transactions
            let (newTransactions, apiErrors) = try await service.fetchTransactions(apiKey: token, startDate: fetchStartDate, endDate: Date())
            
            if !apiErrors.isEmpty {
                resultMessage = "Error: " + apiErrors.joined(separator: ", ")
                isError = true
            } else {
                let initialCount = self.transactions.count
                
                var txnMap = Dictionary(uniqueKeysWithValues: self.transactions.map { ($0.id, $0) })
                for txn in newTransactions {
                    txnMap[txn.id] = txn
                }
                self.transactions = txnMap.values.sorted { $0.date > $1.date }
                
                let newCount = max(0, self.transactions.count - initialCount)
                
                resultMessage = "Synced successfully. \(newCount) imported"
                isError = false
            }
            
        } catch {
            errorMessage = "Sync Failed: \(error.localizedDescription)"
            resultMessage = "Failed: \(error.localizedDescription)"
            isError = true
        }
        isSyncing = false
        return (resultMessage, isError)
    }
    
    func addManualTransaction(payee: String, amount: Decimal, category: String, date: Date, memo: String) {
        let id = "MANUAL-\(UUID().uuidString)"
        let amountString = "\(amount)"
        let posted = date.timeIntervalSince1970
        
        let newTxn = SimpleFinTransaction(
            id: id,
            posted: posted,
            amount: amountString,
            description: memo,
            payee: payee,
            memo: memo,
            transacted_at: posted
        )
        
        self.transactions.append(newTxn)
        self.transactions.sort { $0.date > $1.date }
        self.transactionCategoryOverrides[id] = category
    }
    
    func changeMonth(by value: Int) {
        guard let newDate = Calendar.current.date(byAdding: .month, value: value, to: selectedDate) else { return }
        
        if value < 0, let min = minDate {
            let minPeriodStart = getStartOfPeriod(for: min)
            let targetPeriodStart = getStartOfPeriod(for: newDate)
            if targetPeriodStart < minPeriodStart { return }
        }
        
        selectedDate = newDate
    }
    
    func deleteTransaction(_ transaction: SimpleFinTransaction) {
        hiddenTransactionIDs.insert(transaction.id)
        objectWillChange.send()
    }
    
    // MARK: - Calculations
    
    private var isSelectedPeriodFuture: Bool {
        let startOfPeriod = getStartOfPeriod(for: selectedDate)
        let currentPeriodStart = getStartOfPeriod(for: Date())
        return startOfPeriod > currentPeriodStart
    }
    
    var periodHeaderTitle: String {
        let selectedStart = getStartOfPeriod(for: selectedDate)
        let currentStart = getStartOfPeriod(for: Date())
        
        if selectedStart > currentStart {
            return "Future Period"
        } else if selectedStart < currentStart {
            return "Past Period"
        } else {
            return "Current Period"
        }
    }
    
    // UPDATED: Use emojis for logic checks
    var currentPeriodIncome: Decimal {
        if isSelectedPeriodFuture {
            return (getBudget(for: "💵 Income", on: selectedDate) ) + (getBudget(for: "💰 Paycheck", on: selectedDate))
        } else {
            let periodTxns = getTransactionsForSelectedPeriod()
            let positiveTxns = periodTxns.filter { $0.decimalAmount > 0 }
            return abs(positiveTxns.reduce(0) { $0 + $1.decimalAmount })
        }
    }
    
    // UPDATED: Use emojis for logic checks
    var currentPeriodSpent: Decimal {
        if isSelectedPeriodFuture {
            return categoryNames.filter {
                $0 != "💵 Income" && $0 != "💰 Paycheck" && $0 != "🤑 Savings"
            }.reduce(0) { $0 + getBudget(for: $1, on: selectedDate) }
        } else {
            let periodTxns = getTransactionsForSelectedPeriod()
            let negativeTxns = periodTxns.filter {
                $0.decimalAmount < 0 &&
                getCategory(for: $0) != "🤑 Savings" &&
                getCategory(for: $0) != "💵 Income" &&
                getCategory(for: $0) != "💰 Paycheck"
            }
            return abs(negativeTxns.reduce(0) { $0 + $1.decimalAmount })
        }
    }
    
    // UPDATED: Use emojis for logic checks
    var totalLifetimeSavings: Decimal {
        let startOfPeriod = getStartOfPeriod(for: selectedDate)
        let now = Date()
        let currentPeriodStart = getStartOfPeriod(for: now)
        
        let allSavingsTxns = transactions.filter {
            !hiddenTransactionIDs.contains($0.id) && getCategory(for: $0) == "🤑 Savings"
        }
        let actualSavings = abs(allSavingsTxns.reduce(0) { $0 + $1.decimalAmount })
        
        if startOfPeriod > currentPeriodStart {
            var accumulatedSavings = actualSavings
            var pointerDate = currentPeriodStart
            
            while pointerDate <= startOfPeriod {
                if pointerDate > currentPeriodStart {
                    accumulatedSavings += getBudget(for: "🤑 Savings", on: pointerDate)
                }
                pointerDate = Calendar.current.date(byAdding: .month, value: 1, to: pointerDate)!
            }
            return accumulatedSavings
        } else {
            return actualSavings
        }
    }
    
    var monthlyNetBudget: Decimal {
        return getNetBudget(for: selectedDate)
    }
    
    // UPDATED: Use emojis for logic checks
    func getNetBudget(for date: Date) -> Decimal {
        let income = (getBudget(for: "💵 Income", on: date) ) + (getBudget(for: "💰 Paycheck", on: date))
        let expenses = categoryNames.filter {
            $0 != "💵 Income" && $0 != "💰 Paycheck"
        }.reduce(0) { $0 + getBudget(for: $1, on: date) }
        return income - expenses
    }
    
    func getCategory(for transaction: SimpleFinTransaction) -> String {
        if let specificCategory = transactionCategoryOverrides[transaction.id] {
            return specificCategory
        }
        
        if let highPriority = BudgetLogic.getHighPriorityCategory(transaction) {
            return highPriority
        }
        
        if let userRule = payeeRules[transaction.uiName] { return userRule }
        return BudgetLogic.categorize(transaction)
    }
    
    func updateCategory(for transactionID: String, to newCategory: String) {
        transactionCategoryOverrides[transactionID] = newCategory
        objectWillChange.send()
    }
    
    func getStartOfPeriod(for date: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = 24
        
        if day >= 24 {
            return calendar.date(from: components)!
        } else {
            return calendar.date(byAdding: .month, value: -1, to: calendar.date(from: components)!)!
        }
    }
    
    var periodLabel: String {
        let start = getStartOfPeriod(for: selectedDate)
        let nextPeriodStart = Calendar.current.date(byAdding: .month, value: 1, to: start)!
        let displayEnd = Calendar.current.date(byAdding: .day, value: -1, to: nextPeriodStart)!
        
        let startYear = Calendar.current.component(.year, from: start)
        let endYear = Calendar.current.component(.year, from: displayEnd)
        
        let formatter = DateFormatter()
        
        if startYear == endYear {
            formatter.dateFormat = "MMM d"
            let startString = formatter.string(from: start)
            
            formatter.dateFormat = "MMM d ''yy"
            let endString = formatter.string(from: displayEnd)
            
            return "\(startString) - \(endString)"
        } else {
            formatter.dateFormat = "MMM d ''yy"
            return "\(formatter.string(from: start)) - \(formatter.string(from: displayEnd))"
        }
    }
    
    func setStartingBalance(_ amount: Decimal) {
        startingBalance = amount
        UserDefaults.standard.set(NSDecimalNumber(decimal: amount).doubleValue, forKey: "StartingBalance")
    }
    
    func addCategory(name: String, amount: Decimal) {
        defaultCategoryBudgets[name] = amount
        if !categoryOrder.contains(name) {
            categoryOrder.append(name)
        }
    }
    
    func updateBudget(for category: String, amount: Decimal) {
        let period = currentPeriodKey
        if periodBudgets[period] == nil {
            periodBudgets[period] = [:]
        }
        periodBudgets[period]?[category] = amount
        objectWillChange.send()
    }
    
    var currentPeriodKey: String { return BudgetLogic.getPeriodLabel(for: selectedDate) }
    
    // UPDATED: Use emojis for logic checks
    func getProjectedEnd(for date: Date) -> Decimal {
        let targetLabel = BudgetLogic.getPeriodLabel(for: date, bumpToNextPeriod: false)
        let periodEnd = Calendar.current.date(byAdding: .month, value: 1, to: getStartOfPeriod(for: date))!
        let referenceDate = min(Date(), periodEnd)
        
        let activeTxns = transactions.filter { !hiddenTransactionIDs.contains($0.id) }
        let currentActual = startingBalance + activeTxns.filter { $0.date <= referenceDate }.reduce(0) { $0 + $1.decimalAmount }
        
        var projectedAdjustment: Decimal = 0.0
        
        let periodTxns = activeTxns.filter {
            BudgetLogic.getPeriodLabel(for: $0.date, bumpToNextPeriod: isTransactionOnPayday($0)) == targetLabel
        }
        
        for category in categoryNames {
            let budgetAmount = getBudget(for: category, on: date)
            let catTxns = periodTxns.filter { getCategory(for: $0) == category }
            let spentAmount = abs(catTxns.reduce(0) { $0 + $1.decimalAmount })
            
            let isIncome = (category == "💵 Income" || category == "💰 Paycheck")
            
            if isIncome {
                if budgetAmount > spentAmount {
                    projectedAdjustment += (budgetAmount - spentAmount)
                }
            } else {
                if budgetAmount > spentAmount {
                    projectedAdjustment -= (budgetAmount - spentAmount)
                }
            }
        }
        
        return currentActual + projectedAdjustment
    }
    
    var beginningBalance: Decimal {
        let targetLabel = currentPeriodKey
        
        if isSelectedPeriodFuture {
            let now = Date()
            let currentPeriodStart = getStartOfPeriod(for: now)
            let startOfPeriod = getStartOfPeriod(for: selectedDate)
            
            var accumulatedBalance = getProjectedEnd(for: now)
            var pointerDate = Calendar.current.date(byAdding: .month, value: 1, to: currentPeriodStart)!
            
            while pointerDate < startOfPeriod {
                let netForMonth = getNetBudget(for: pointerDate)
                accumulatedBalance += netForMonth
                pointerDate = Calendar.current.date(byAdding: .month, value: 1, to: pointerDate)!
            }
            
            return accumulatedBalance
        } else {
            let pastTransactions = transactions.filter { txn in
                let txnLabel = BudgetLogic.getPeriodLabel(for: txn.date, bumpToNextPeriod: isTransactionOnPayday(txn))
                return txnLabel < targetLabel && !hiddenTransactionIDs.contains(txn.id)
            }
            let pastSum = pastTransactions.reduce(0) { $0 + $1.decimalAmount }
            return startingBalance + pastSum
        }
    }
    
    var endingBalance: Decimal {
        let startOfPeriod = getStartOfPeriod(for: selectedDate)
        let now = Date()
        let currentPeriodStart = getStartOfPeriod(for: now)

        if startOfPeriod > currentPeriodStart {
            return beginningBalance + monthlyNetBudget
        } else {
            let currentTxns = getTransactionsForSelectedPeriod()
            let currentSum = currentTxns.reduce(0) { $0 + $1.decimalAmount }
            return beginningBalance + currentSum
        }
    }
    
    func getCurrentActualBalance() -> Decimal {
        let activeTxns = transactions.filter { !hiddenTransactionIDs.contains($0.id) }
        return startingBalance + activeTxns.filter { $0.date <= Date() }.reduce(0) { $0 + $1.decimalAmount }
    }
    
    func getSpent(for category: String) -> Decimal {
        let targetPeriod = currentPeriodKey
        let filtered = transactions.filter { txn in
            return !hiddenTransactionIDs.contains(txn.id) &&
                   BudgetLogic.getPeriodLabel(for: txn.date, bumpToNextPeriod: isTransactionOnPayday(txn)) == targetPeriod &&
                   self.getCategory(for: txn) == category
        }
        return abs(filtered.reduce(0) { $0 + $1.decimalAmount })
    }
    
    func getBudget(for category: String, on date: Date? = nil) -> Decimal {
        let dateToUse = date ?? selectedDate
        let periodKey = BudgetLogic.getPeriodLabel(for: dateToUse)
        
        if let specific = periodBudgets[periodKey]?[category] {
            return specific
        }
        return defaultCategoryBudgets[category] ?? 0.0
    }
    
    func getFilteredTransactions() -> [SimpleFinTransaction] {
        let allInPeriod = getTransactionsForSelectedPeriod()
        guard let filter = selectedCategoryFilter, filter != "All" else { return allInPeriod }
        return allInPeriod.filter { getCategory(for: $0) == filter }
    }
    
    func getTransactionsForSelectedPeriod() -> [SimpleFinTransaction] {
        let targetPeriod = currentPeriodKey
        return transactions.filter {
            !hiddenTransactionIDs.contains($0.id) &&
            BudgetLogic.getPeriodLabel(for: $0.date, bumpToNextPeriod: isTransactionOnPayday($0)) == targetPeriod
        }
    }
}
