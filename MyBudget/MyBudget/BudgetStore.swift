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
    
// 1. Define the options
    enum SortOption: String, CaseIterable, Identifiable {
        case totalSpending = "Total Spending"
        case percentSpending = "% of Total Spending"
        case alphabetical = "Alphabetical"
        
        var id: String { self.rawValue }
    }
    
    // 2. Add the state variable
    @Published var currentSortOption: SortOption = .totalSpending

    // 3. Update the categoryNames logic
    var categoryNames: [String] {
        let allCategories = categoryOrder
        
        switch currentSortOption {
        case .alphabetical:
            return allCategories.sorted { name1, name2 in
                // Strict Cleaning: Keep ONLY letters and numbers.
                let clean1 = name1.filter { $0.isLetter || $0.isNumber }
                let clean2 = name2.filter { $0.isLetter || $0.isNumber }
                
                // Compare the cleaned "text-only" versions
                return clean1.localizedCaseInsensitiveCompare(clean2) == .orderedAscending
            }
            
        case .totalSpending, .percentSpending:
            return allCategories.sorted { name1, name2 in
                let spent1 = getSpent(for: name1)
                let spent2 = getSpent(for: name2)
                if spent1 == spent2 { return name1 < name2 }
                return spent1 > spent2
            }
        }
    }
    
    @Published var transactions: [SimpleFinTransaction] = [] {
        didSet {
            updatePaycheckDates()
            updateCurrentPeriodCache()
            checkBudgetAlertsIfNeeded()
            if let encoded = try? JSONEncoder().encode(transactions) {
                UserDefaults.standard.set(encoded, forKey: "SavedTransactions")
            }
        }
    }
    
    @Published var currentPeriodTransactions: [SimpleFinTransaction] = []
    
    @Published var categoriesMap: [Int: LunchMoneyCategory] = [:] {
        didSet {
            if let encoded = try? JSONEncoder().encode(categoriesMap) {
                UserDefaults.standard.set(encoded, forKey: "SavedCategories")
            }
            refreshCategoryList()
        }
    }
    
    @Published var transactionCategoryOverrides: [String: String] = [:] {
        didSet { UserDefaults.standard.set(transactionCategoryOverrides, forKey: "TxnOverrides") }
    }
    
    @Published var defaultCategoryBudgets: [String: Decimal] = [:] {
        didSet {
            saveBudgets()
        }
    }
    
    // Helper to safely save budgets and print errors if it fails
    private func saveBudgets() {
        do {
            // Convert [String: Decimal] -> [String: String] for safe storage
            let safeStorage = defaultCategoryBudgets.mapValues { "\($0)" }
            
            let encoded = try JSONEncoder().encode(safeStorage)
            UserDefaults.standard.set(encoded, forKey: "DefaultCategoryBudgets")
        } catch {
            print("❌ FAILED TO SAVE BUDGETS: \(error.localizedDescription)")
        }
    }
    
    @Published var categoryOrder: [String] = [] {
        didSet { UserDefaults.standard.set(categoryOrder, forKey: "CategoryOrder") }
    }
    
    @Published var budgetStartDay: Int = 1 {
        didSet { UserDefaults.standard.set(budgetStartDay, forKey: "BudgetStartDay") }
    }
    
    private var paycheckDates: [Date] = []
    
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private let budgetAlertThreshold: Decimal = 0.8
    private let budgetAlertKeysStorage = "BudgetAlertedKeys"
    private let budgetAlertsEnabledKey = "Notifications.BudgetAlertsEnabled"

    private let paycheckMinimumAmount: Decimal = 1000

    private func absDecimal(_ value: Decimal) -> Decimal {
        return value < 0 ? -value : value
    }

    private func normalizedAmountKey(_ amount: Decimal) -> String {
        var source = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .bankers)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    private func transactionMatchKey(_ transaction: SimpleFinTransaction) -> String {
        let dateKey = dayFormatter.string(from: transaction.date)
        let amountKey = normalizedAmountKey(transaction.decimalAmount)
        return "\(dateKey)|\(amountKey)"
    }

    private func isAmountMatch(_ lhs: SimpleFinTransaction, _ rhs: SimpleFinTransaction) -> Bool {
        return normalizedAmountKey(lhs.decimalAmount) == normalizedAmountKey(rhs.decimalAmount)
    }

    private func isWithinDays(_ lhs: Date, _ rhs: Date, days: Int) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: lhs)
        let end = calendar.startOfDay(for: rhs)
        let diff = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return abs(diff) <= days
    }
    
    @Published var selectedDate: Date = Date() {
        didSet { updateCurrentPeriodCache() }
    }
    
    @Published var startingBalance: Decimal = 0.0
    @Published var selectedCategoryFilter: String? = nil
    @Published var hiddenTransactionIDs: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(hiddenTransactionIDs), forKey: "HiddenTxns")
            updateCurrentPeriodCache()
        }
    }
    @Published var periodBudgets: [String: [String: Decimal]] = [:] {
        didSet {
            if let encoded = try? JSONEncoder().encode(periodBudgets) {
                UserDefaults.standard.set(encoded, forKey: "PeriodBudgets")
            }
        }
    }
    @Published var payeeRules: [String: String] = [:] {
        didSet { UserDefaults.standard.set(payeeRules, forKey: "PayeeRules") }
    }
    
    @Published var minDate: Date? {
        didSet {
            if let date = minDate { UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "MinDate") }
        }
    }
    
    @Published var accessUrl: String? {
        didSet { UserDefaults.standard.set(accessUrl, forKey: "LunchMoneyToken") }
    }
    
    @Published var isSyncing = false
    @Published var errorMessage: String?
    @Published var showErrorAlert = false
    
    private let service = LunchMoneyService()
    
    init() {
        // 1. Load simple settings first
        self.accessUrl = UserDefaults.standard.string(forKey: "LunchMoneyToken")
        self.startingBalance = Decimal(UserDefaults.standard.double(forKey: "StartingBalance"))
        
        let savedDay = UserDefaults.standard.integer(forKey: "BudgetStartDay")
        self.budgetStartDay = savedDay > 0 ? savedDay : 1
        
        if let min = UserDefaults.standard.object(forKey: "MinDate") as? Double {
            self.minDate = Date(timeIntervalSince1970: min)
        }

        // 2. CRITICAL FIX: Load Budgets BEFORE Categories
        // This ensures that when categories load and trigger a refresh, the budgets are already there.
        if let savedDefaults = UserDefaults.standard.data(forKey: "DefaultCategoryBudgets") {
            // Try Safe String Format first
            if let safeDecoded = try? JSONDecoder().decode([String: String].self, from: savedDefaults) {
                self.defaultCategoryBudgets = safeDecoded.compactMapValues { Decimal(string: $0) }
                print("✅ Successfully loaded budgets from Safe Storage.")
            }
            // Fallback to Old Decimal Format
            else if let oldDecoded = try? JSONDecoder().decode([String: Decimal].self, from: savedDefaults) {
                self.defaultCategoryBudgets = oldDecoded
                print("⚠️ Loaded budgets from old format. Saving to new format now...")
                self.saveBudgets()
            }
        }
        
        // 3. Load Order and Overrides
        if let savedOrder = UserDefaults.standard.array(forKey: "CategoryOrder") as? [String] {
            self.categoryOrder = savedOrder
        }
        
        if let savedOverrides = UserDefaults.standard.object(forKey: "TxnOverrides") as? [String: String] {
            self.transactionCategoryOverrides = savedOverrides
        }
        
        // 4. NOW Load Categories (Triggers refreshCategoryList)
        // Since budgets are already loaded (Step 2), this will now MATCH them instead of overwriting them with 0.0
        if let savedCats = UserDefaults.standard.data(forKey: "SavedCategories"),
           let decoded = try? JSONDecoder().decode([Int: LunchMoneyCategory].self, from: savedCats) {
            self.categoriesMap = decoded
        } else {
            // Only run refresh manually if we didn't load categories (which would have auto-triggered it)
            self.refreshCategoryList()
        }
        
        // 5. Load Transactions
        if let savedData = UserDefaults.standard.data(forKey: "SavedTransactions"),
           let decoded = try? JSONDecoder().decode([SimpleFinTransaction].self, from: savedData) {
            self.transactions = decoded
            self.updatePaycheckDates()
        }
        
        // 6. Load Other Settings
        if let savedHidden = UserDefaults.standard.array(forKey: "HiddenTxns") as? [String] {
            self.hiddenTransactionIDs = Set(savedHidden)
        }
        
        if let savedBudgets = UserDefaults.standard.data(forKey: "PeriodBudgets"),
           let decoded = try? JSONDecoder().decode([String: [String: Decimal]].self, from: savedBudgets) {
            self.periodBudgets = decoded
        }
        
        self.updateCurrentPeriodCache()
    }

    private func updateCurrentPeriodCache() {
        let periodStart = getStartOfPeriod(for: selectedDate)
        
        let periodEnd: Date
        if let nextPaycheck = paycheckDates.sorted().first(where: { $0 > periodStart }) {
            periodEnd = nextPaycheck
        } else {
            periodEnd = Calendar.current.date(byAdding: .month, value: 1, to: periodStart)!
        }
        
        self.currentPeriodTransactions = transactions.filter { txn in
            if hiddenTransactionIDs.contains(txn.id) { return false }
            return txn.date >= periodStart && txn.date < periodEnd
        }
    }

    private func refreshCategoryList() {
        var newBudgets = self.defaultCategoryBudgets
        var newOrder = self.categoryOrder
        
        for category in categoriesMap.values {
            if newBudgets[category.name] == nil {
                print("⚠️ Missing budget for \(category.name), initializing to 0.0")
                newBudgets[category.name] = 0.0
            }
            
            if !newOrder.contains(category.name) {
                newOrder.append(category.name)
            }
        }
        
        if newBudgets["Uncategorized"] == nil { newBudgets["Uncategorized"] = 0.0 }
        if !newOrder.contains("Uncategorized") { newOrder.append("Uncategorized") }
        
        // Only update if changes were actually made to avoid unnecessary saves
        if newBudgets != self.defaultCategoryBudgets {
            self.defaultCategoryBudgets = newBudgets
        }
        if newOrder != self.categoryOrder {
            self.categoryOrder = newOrder
        }
    }
    
    func syncTransactions(startDate: Date? = nil, specificPeriodStart: Date? = nil, specificPeriodEnd: Date? = nil) async -> (String, Bool) {
        guard let token = accessUrl else { return ("No token", true) }
        isSyncing = true
        
        do {
            let categories = try await service.fetchCategories(apiKey: token)
            var newMap: [Int: LunchMoneyCategory] = [:]
            for cat in categories {
                newMap[cat.id] = cat
                if let kids = cat.children {
                    for kid in kids {
                        newMap[kid.id] = kid
                    }
                }
            }
            await MainActor.run { self.categoriesMap = newMap }
            
            let summaryStart: Date
            let summaryEnd: Date
            
            if let start = specificPeriodStart, let end = specificPeriodEnd {
                summaryStart = start
                summaryEnd = end
            } else {
                summaryStart = getStartOfPeriod(for: selectedDate)
                let nextPeriodStart = Calendar.current.date(byAdding: .month, value: 1, to: summaryStart)!
                summaryEnd = nextPeriodStart.addingTimeInterval(-86400)
            }
            
            let (aligned, summaryCategories) = try await service.fetchBudgetSummary(apiKey: token, startDate: summaryStart, endDate: summaryEnd)
            
            if aligned {
                var updatedDefaults = self.defaultCategoryBudgets
                for item in summaryCategories {
                    if let catName = newMap[item.category_id]?.name, let amount = item.totals.budgeted {
                        let cleanAmountString = String(format: "%.2f", amount)
                        if let cleanDecimal = Decimal(string: cleanAmountString) {
                            updatedDefaults[catName] = cleanDecimal
                        }
                    }
                }
                await MainActor.run { self.defaultCategoryBudgets = updatedDefaults }
            } else {
                print("Skipping budget update: Period not aligned with LunchMoney configuration.")
            }
            
            do {
                try await service.triggerPlaidSync(apiKey: token)
            } catch {
                print("⚠️ Plaid Sync Skipped: \(error.localizedDescription)")
            }
            
            try await Task.sleep(nanoseconds: 1 * 1_000_000_000)
            
            let fetchDate = startDate ?? Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            let (newTransactions, apiErrors) = try await service.fetchTransactions(apiKey: token, startDate: fetchDate)
            
            if !apiErrors.isEmpty {
                isSyncing = false
                return ("Error: " + apiErrors.joined(separator: ", "), true)
            }
            
            let initialCount = self.transactions.count

            let manualIDsToRemove: Set<String> = Set(self.transactions.compactMap { txn in
                guard txn.id.hasPrefix("MANUAL-") else { return nil }
                let shouldRemove = newTransactions.contains { incoming in
                    isAmountMatch(txn, incoming) && isWithinDays(txn.date, incoming.date, days: 2)
                }
                return shouldRemove ? txn.id : nil
            })

            if !manualIDsToRemove.isEmpty {
                self.hiddenTransactionIDs.subtract(manualIDsToRemove)
            }

            let filteredExisting = self.transactions.filter { !manualIDsToRemove.contains($0.id) }
            var txnMap: [String: SimpleFinTransaction] = Dictionary(
                uniqueKeysWithValues: filteredExisting.map { ($0.id, $0) }
            )
            for txn in newTransactions { txnMap[txn.id] = txn }
            self.transactions = txnMap.values.sorted { $0.date > $1.date }
            
            isSyncing = false
            let newCount = max(0, self.transactions.count - initialCount)
            return ("Synced. \(newCount) imported", false)
            
        } catch {
            isSyncing = false
            return ("Failed: \(error.localizedDescription)", true)
        }
    }
    
    func connectLunchMoney(token: String, initialBalance: Decimal, importStartDate: Date, periodStart: Date, periodEnd: Date) async {
        isSyncing = true
        errorMessage = nil
        showErrorAlert = false
        
        do {
            let (aligned, _) = try await service.fetchBudgetSummary(apiKey: token, startDate: periodStart, endDate: periodEnd)
            
            if !aligned {
                self.errorMessage = "The dates selected do not match a valid LunchMoney budgeting period. Please adjust the Start/End dates."
                self.showErrorAlert = true
                self.isSyncing = false
                return
            }
            
            self.accessUrl = token
            let startDay = Calendar.current.component(.day, from: periodStart)
            self.budgetStartDay = startDay
            
            _ = await syncTransactions(
                startDate: importStartDate,
                specificPeriodStart: periodStart,
                specificPeriodEnd: periodEnd
            )
            
            self.setStartingBalance(initialBalance)
            self.minDate = importStartDate
            
            if let lastTxn = transactions.max(by: { $0.date < $1.date }) {
                self.selectedDate = lastTxn.date
            } else {
                self.selectedDate = importStartDate
            }
            
        } catch {
            self.errorMessage = "Connection Failed: \(error.localizedDescription)"
            self.showErrorAlert = true
        }
        
        isSyncing = false
    }
    
    // UPDATED: Fix for Future Periods
    func getStartOfPeriod(for date: Date) -> Date {
        // 1. Try to find a paycheck on or before this date
        if let periodStart = paycheckDates.sorted().last(where: { $0 <= date || Calendar.current.isDate($0, inSameDayAs: date) }) {
            
            // CHECK: Is this paycheck "current"?
            // We changed 35 to 28. This ensures that once you are a full month (28+ days)
            // past the last paycheck, the app allows the new period to start
            // instead of forcing it back to the previous one.
            let daysDiff = Calendar.current.dateComponents([.day], from: periodStart, to: date).day ?? 0
            if daysDiff < 28 {
                return periodStart
            }
        }
        
        // 2. Fallback / Future Logic
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        var comps = calendar.dateComponents([.year, .month], from: date)
        comps.day = self.budgetStartDay
        
        if day >= self.budgetStartDay {
            return calendar.date(from: comps)!
        } else {
            return calendar.date(byAdding: .month, value: -1, to: calendar.date(from: comps)!)!
        }
    }
    
    func getCategory(for transaction: SimpleFinTransaction) -> String {
        if let override = transactionCategoryOverrides[transaction.id] { return override }
        if let id = transaction.categoryId, let cat = categoriesMap[id] { return cat.name }
        return "Uncategorized"
    }
    
    func isIncomeCategory(_ categoryName: String) -> Bool {
        if let cat = categoriesMap.values.first(where: { $0.name == categoryName }) { return cat.is_income }
        return false
    }
    
    private func updatePaycheckDates() {
        let calendar = Calendar.current
        
        let rawDates = transactions
            .filter {
                getCategory(for: $0).lowercased().contains("paycheck") &&
                absDecimal($0.decimalAmount) >= paycheckMinimumAmount
            }
            .map { $0.date }
            .sorted()
        
        var clusteredDates: [Date] = []
        
        for date in rawDates {
            let startOfDay = calendar.startOfDay(for: date)
            
            if let lastGroupDate = clusteredDates.last {
                if let daysDiff = calendar.dateComponents([.day], from: lastGroupDate, to: startOfDay).day, daysDiff < 5 {
                    continue
                }
            }
            clusteredDates.append(startOfDay)
        }
        
        self.paycheckDates = clusteredDates
        
        // NEW: Sync future projections to the most recent paycheck date.
        // This ensures that if your paycheck lands on the 23rd,
        // the future months (Feb, Mar, etc.) will also default to starting on the 23rd.
        if let lastPaycheck = clusteredDates.max() {
            let day = calendar.component(.day, from: lastPaycheck)
            if self.budgetStartDay != day {
                self.budgetStartDay = day
            }
        }
    }
    
    func isTransactionOnPayday(_ transaction: SimpleFinTransaction) -> Bool {
        let calendar = Calendar.current
        return paycheckDates.contains { calendar.isDate($0, inSameDayAs: transaction.date) }
    }
    
    var currentPeriodIncome: Decimal {
        if isSelectedPeriodFuture {
            return categoryNames.filter { isIncomeCategory($0) }
                .reduce(0) { $0 + getBudget(for: $1, on: selectedDate) }
        } else {
            return abs(currentPeriodTransactions.filter { $0.decimalAmount > 0 }.reduce(0) { $0 + $1.decimalAmount })
        }
    }
    
    var currentPeriodSpent: Decimal {
        if isSelectedPeriodFuture {
            return categoryNames.filter {
                !isIncomeCategory($0) && !$0.localizedCaseInsensitiveContains("savings")
            }
                .reduce(0) { $0 + getBudget(for: $1, on: selectedDate) }
        } else {
            let filtered = currentPeriodTransactions.filter {
                $0.decimalAmount < 0 &&
                !isIncomeCategory(getCategory(for: $0)) &&
                !getCategory(for: $0).localizedCaseInsensitiveContains("savings")
            }
            return abs(filtered.reduce(0) { $0 + $1.decimalAmount })
        }
    }
    
    var totalLifetimeSavings: Decimal {
        let startOfPeriod = getStartOfPeriod(for: selectedDate)
        let now = Date()
        let currentPeriodStart = getStartOfPeriod(for: now)
        
        let allSavingsTxns = transactions.filter {
            !hiddenTransactionIDs.contains($0.id) &&
            getCategory(for: $0).localizedCaseInsensitiveContains("savings")
        }
        let actualSavings = abs(allSavingsTxns.reduce(0) { $0 + $1.decimalAmount })
        
        if startOfPeriod > currentPeriodStart {
            var accumulated = actualSavings
            var pointer = currentPeriodStart
            while pointer <= startOfPeriod {
                if pointer > currentPeriodStart {
                    let savingsCats = categoryNames.filter { $0.localizedCaseInsensitiveContains("savings") }
                    for cat in savingsCats {
                        accumulated += getBudget(for: cat, on: pointer)
                    }
                }
                pointer = Calendar.current.date(byAdding: .month, value: 1, to: pointer)!
            }
            return accumulated
        }
        return actualSavings
    }
    
    func getNetBudget(for date: Date) -> Decimal {
        let income = categoryNames.filter { isIncomeCategory($0) }
            .reduce(0) { $0 + getBudget(for: $1, on: date) }
        let expenses = categoryNames.filter { !isIncomeCategory($0) }
            .reduce(0) { $0 + getBudget(for: $1, on: date) }
        return income - expenses
    }
    
    func getProjectedEnd(for date: Date) -> Decimal {
        let periodStart = getStartOfPeriod(for: date)
        
        let periodEnd: Date
        if let nextPaycheck = paycheckDates.sorted().first(where: { $0 > periodStart }) {
            periodEnd = nextPaycheck
        } else {
            periodEnd = Calendar.current.date(byAdding: .month, value: 1, to: periodStart)!
        }
        
        let referenceDate = min(Date(), periodEnd)
        
        let activeTxns = transactions.filter { !hiddenTransactionIDs.contains($0.id) }
        let currentActual = startingBalance + activeTxns.filter { $0.date <= referenceDate }.reduce(0) { $0 + $1.decimalAmount }
        
        var projectedAdjustment: Decimal = 0.0
        
        let periodTxns = activeTxns.filter {
            $0.date >= periodStart && $0.date < periodEnd
        }
        
        for category in categoryNames {
            let budget = getBudget(for: category, on: date)
            let catTxns = periodTxns.filter { getCategory(for: $0) == category }
            let spent = abs(catTxns.reduce(0) { $0 + $1.decimalAmount })
            
            if isIncomeCategory(category) {
                if budget > spent { projectedAdjustment += (budget - spent) }
            } else {
                if budget > spent { projectedAdjustment -= (budget - spent) }
            }
        }
        return currentActual + projectedAdjustment
    }
    
    func deleteCategory(at offsets: IndexSet) {
        let categoriesToDelete = offsets.map { categoryOrder[$0] }
        categoryOrder.remove(atOffsets: offsets)
        for category in categoriesToDelete { defaultCategoryBudgets.removeValue(forKey: category) }
    }
    func moveCategories(from source: IndexSet, to destination: Int) { categoryOrder.move(fromOffsets: source, toOffset: destination) }
    
    func addManualTransaction(payee: String, amount: Decimal, category: String, date: Date, memo: String) {
        let id = "MANUAL-\(UUID().uuidString)"
        let posted = date.timeIntervalSince1970
        let catID = categoriesMap.first(where: { $0.value.name == category })?.key
        
        let newTxn = SimpleFinTransaction(id: id, posted: posted, amount: "\(amount)", description: memo, payee: payee, memo: memo, transacted_at: posted, categoryId: catID)
        transactions.append(newTxn)
        transactions.sort { $0.date > $1.date }
    }
    
    func changeMonth(by value: Int) {
        guard !paycheckDates.isEmpty else {
            guard let newDate = Calendar.current.date(byAdding: .month, value: value, to: selectedDate) else { return }
            selectedDate = newDate
            return
        }
        
        let sorted = paycheckDates.sorted()
        let currentStart = getStartOfPeriod(for: selectedDate)
        
        if let index = sorted.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: currentStart) }) {
            let newIndex = index + value
            if newIndex >= 0 && newIndex < sorted.count {
                selectedDate = sorted[newIndex]
            } else if newIndex >= sorted.count {
                if let newDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) {
                    selectedDate = newDate
                }
            } else if newIndex < 0 {
                // Limit to oldest
                return
            }
        } else {
            // Fallback for when current selectedDate is in "Future" (not in paycheck list)
            if let newDate = Calendar.current.date(byAdding: .month, value: value, to: selectedDate) {
                selectedDate = newDate
            }
        }
    }
    
    func deleteTransaction(_ transaction: SimpleFinTransaction) { hiddenTransactionIDs.insert(transaction.id); objectWillChange.send() }
    
    var periodHeaderTitle: String {
        let start = getStartOfPeriod(for: selectedDate)
        let current = getStartOfPeriod(for: Date())
        if start > current { return "Future Period" }
        if start < current { return "Past Period" }
        return "Current Period"
    }
    
    var monthlyNetBudget: Decimal { return getNetBudget(for: selectedDate) }
    
    func updateBudget(for category: String, amount: Decimal) {
        // 1. Update the global default.
        // This ensures any future period (that doesn't have a specific override yet) uses this new amount.
        defaultCategoryBudgets[category] = amount
        
        // 2. Update the specific current period.
        // This ensures the change appears immediately in the view you are currently looking at.
        let periodFormatter = DateFormatter()
        periodFormatter.dateFormat = "yyyy-MM-dd"
        let key = periodFormatter.string(from: getStartOfPeriod(for: selectedDate))
        
        if periodBudgets[key] == nil { periodBudgets[key] = [:] }
        periodBudgets[key]?[category] = amount
        
        objectWillChange.send()
        checkBudgetAlertsIfNeeded()
    }
    
    var currentPeriodKey: String {
        let periodFormatter = DateFormatter()
        periodFormatter.dateFormat = "yyyy-MM-dd"
        return periodFormatter.string(from: getStartOfPeriod(for: selectedDate))
    }
    
    var periodLabel: String {
        let start = getStartOfPeriod(for: selectedDate)
        let currentStart = getStartOfPeriod(for: Date())
        let formatter = DateFormatter()
        
        // 1. FUTURE: Show Month & Year only (No specific day numbers)
        if start > currentStart {
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: start)
        }
        
        // 2. CURRENT: Show "Starting [Date]" only
        if start == currentStart {
            formatter.dateFormat = "MMM d"
            return "Starting \(formatter.string(from: start))"
        }
        
        // 3. PAST: Show full Date Range (e.g., "Jan 23 - Feb 22")
        // Calculate the end date based on the NEXT paycheck or standard month
        let end: Date
        if let nextPaycheck = paycheckDates.sorted().first(where: { $0 > start }) {
            end = Calendar.current.date(byAdding: .day, value: -1, to: nextPaycheck)!
        } else {
            end = Calendar.current.date(byAdding: .month, value: 1, to: start)!.addingTimeInterval(-86400)
        }
        
        let startYear = Calendar.current.component(.year, from: start)
        let endYear = Calendar.current.component(.year, from: end)
        
        if startYear == endYear {
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        } else {
            formatter.dateFormat = "MMM d ''yy"
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }
    }
    
    func setStartingBalance(_ amount: Decimal) { startingBalance = amount; UserDefaults.standard.set(NSDecimalNumber(decimal: amount).doubleValue, forKey: "StartingBalance") }
    func addCategory(name: String, amount: Decimal) { defaultCategoryBudgets[name] = amount; if !categoryOrder.contains(name) { categoryOrder.append(name) } }
    
    var beginningBalance: Decimal {
        let targetStart = getStartOfPeriod(for: selectedDate)
        let now = Date()
        let currentStart = getStartOfPeriod(for: now)
        
        if targetStart > currentStart {
            // 1. Start with the projected ending balance of the ACTUAL current period.
            // This accounts for the "Current Actual + Remaining Budget" logic you mentioned.
            var accumulated = getProjectedEnd(for: now)
            
            // 2. Iterate through every month BETWEEN the current period and the selected future period.
            // We start checking "Next Month".
            var pointer = Calendar.current.date(byAdding: .month, value: 1, to: currentStart)!
            
            // While our pointer is still BEFORE the target month...
            while getStartOfPeriod(for: pointer) < targetStart {
                // ...add the Net Budget (Income - Expenses) for that intermediate month.
                accumulated += getNetBudget(for: pointer)
                
                // Move pointer to the next month
                pointer = Calendar.current.date(byAdding: .month, value: 1, to: pointer)!
            }
            
            return accumulated
        } else {
            // Past Logic (Unchanged)
            let past = transactions.filter {
                !hiddenTransactionIDs.contains($0.id) && $0.date < targetStart
            }
            return startingBalance + past.reduce(0) { $0 + $1.decimalAmount }
        }
    }
    
    var endingBalance: Decimal {
        if getStartOfPeriod(for: selectedDate) > getStartOfPeriod(for: Date()) { return beginningBalance + monthlyNetBudget }
        return beginningBalance + currentPeriodTransactions.reduce(0) { $0 + $1.decimalAmount }
    }
    
    func getSpent(for category: String) -> Decimal {
        let filtered = currentPeriodTransactions.filter { getCategory(for: $0) == category }
        return abs(filtered.reduce(0) { $0 + $1.decimalAmount })
    }
    
    func getBudget(for category: String, on date: Date? = nil) -> Decimal {
        let d = date ?? selectedDate
        let periodFormatter = DateFormatter()
        periodFormatter.dateFormat = "yyyy-MM-dd"
        let key = periodFormatter.string(from: getStartOfPeriod(for: d))
        
        if let val = periodBudgets[key]?[category] { return val }
        return defaultCategoryBudgets[category] ?? 0.0
    }
    
    func getFilteredTransactions() -> [SimpleFinTransaction] {
        guard let f = selectedCategoryFilter, f != "All" else { return currentPeriodTransactions }
        return currentPeriodTransactions.filter { getCategory(for: $0) == f }
    }
    
    func getTransactionsForSelectedPeriod() -> [SimpleFinTransaction] {
        return currentPeriodTransactions
    }
    
    private var isSelectedPeriodFuture: Bool { getStartOfPeriod(for: selectedDate) > getStartOfPeriod(for: Date()) }

    func endingBalance(for date: Date) -> Decimal {
        let targetStart = getStartOfPeriod(for: date)
        let periodEnd = getPeriodEnd(for: targetStart)
        let active = activeTransactions()

        let past = active.filter { $0.date < targetStart }
        let beginning = startingBalance + past.reduce(0) { $0 + $1.decimalAmount }

        let periodTxns = active.filter { $0.date >= targetStart && $0.date < periodEnd }
        return beginning + periodTxns.reduce(0) { $0 + $1.decimalAmount }
    }

    func totals(in interval: DateInterval) -> (income: Decimal, expenses: Decimal) {
        let active = activeTransactions().filter { $0.date >= interval.start && $0.date < interval.end }
        let income = active.filter { $0.decimalAmount > 0 }.reduce(0) { $0 + $1.decimalAmount }
        let expensesSum = active.filter { $0.decimalAmount < 0 }.reduce(0) { $0 + $1.decimalAmount }
        return (income, abs(expensesSum))
    }

    func currentWeekInterval() -> DateInterval {
        let calendar = Calendar.current
        return calendar.dateInterval(of: .weekOfYear, for: Date()) ?? DateInterval(start: Date(), duration: 0)
    }

    private func activeTransactions() -> [SimpleFinTransaction] {
        return transactions.filter { !hiddenTransactionIDs.contains($0.id) }
    }

    private func getPeriodEnd(for periodStart: Date) -> Date {
        if let nextPaycheck = paycheckDates.sorted().first(where: { $0 > periodStart }) {
            return nextPaycheck
        }
        return Calendar.current.date(byAdding: .month, value: 1, to: periodStart)!
    }

    private func budgetAlertKey(for periodStart: Date, category: String) -> String {
        let periodKey = dayFormatter.string(from: periodStart)
        return "\(periodKey)|\(category)"
    }

    private func loadBudgetAlertedKeys() -> Set<String> {
        if let saved = UserDefaults.standard.array(forKey: budgetAlertKeysStorage) as? [String] {
            return Set(saved)
        }
        return []
    }

    private func saveBudgetAlertedKeys(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys), forKey: budgetAlertKeysStorage)
    }

    private func checkBudgetAlertsIfNeeded() {
        guard UserDefaults.standard.bool(forKey: budgetAlertsEnabledKey) else { return }

        let now = Date()
        let periodStart = getStartOfPeriod(for: now)
        let periodEnd = getPeriodEnd(for: periodStart)
        let active = activeTransactions()
        let periodTxns = active.filter { $0.date >= periodStart && $0.date < periodEnd }

        var spentByCategory: [String: Decimal] = [:]
        for txn in periodTxns where txn.decimalAmount < 0 {
            let category = getCategory(for: txn)
            if isIncomeCategory(category) || category.localizedCaseInsensitiveContains("savings") { continue }
            spentByCategory[category, default: 0] += abs(txn.decimalAmount)
        }

        var alerted = loadBudgetAlertedKeys()
        for (category, spent) in spentByCategory {
            let budget = getBudget(for: category, on: now)
            if budget <= 0 { continue }
            let pct = spent / budget
            if pct >= budgetAlertThreshold {
                let key = budgetAlertKey(for: periodStart, category: category)
                if !alerted.contains(key) {
                    alerted.insert(key)
                    Task { await NotificationManager.shared.sendBudgetAlert(category: category, percent: pct * 100, spent: spent, budget: budget) }
                }
            }
        }
        saveBudgetAlertedKeys(alerted)
    }
    
    func updateCategory(for transactionID: String, to newCategory: String) {
        transactionCategoryOverrides[transactionID] = newCategory
        objectWillChange.send()
        updateCurrentPeriodCache()
    }

    func evaluateBudgetAlerts() {
        checkBudgetAlertsIfNeeded()
    }

    private func replaceTransaction(_ updated: SimpleFinTransaction) {
        var updatedTransactions = transactions
        if let index = updatedTransactions.firstIndex(where: { $0.id == updated.id }) {
            updatedTransactions[index] = updated
            updatedTransactions.sort { $0.date > $1.date }
            transactions = updatedTransactions
        }
    }

    func updateTransactionPayee(for transactionID: String, to newPayee: String) async -> (Bool, String?) {
        let trimmed = newPayee.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let existing = transactions.first(where: { $0.id == transactionID }) else {
            return (false, "Transaction not found.")
        }

        if existing.payee == trimmed {
            return (true, nil)
        }

        if transactionID.hasPrefix("MANUAL-") {
            let updated = existing.withPayee(trimmed)
            replaceTransaction(updated)
            return (true, nil)
        }

        guard let token = accessUrl else {
            return (false, "Missing Lunch Money token.")
        }

        do {
            try await service.updateTransactionPayee(apiKey: token, transactionId: transactionID, payee: trimmed)
            let updated = existing.withPayee(trimmed)
            replaceTransaction(updated)
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
