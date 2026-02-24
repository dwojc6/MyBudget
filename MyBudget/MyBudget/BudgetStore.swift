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
    private var lastConfirmedPaycheckDate: Date? {
        didSet {
            if let date = lastConfirmedPaycheckDate {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "LastConfirmedPaycheckDate")
            } else {
                UserDefaults.standard.removeObject(forKey: "LastConfirmedPaycheckDate")
            }
        }
    }
    
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

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

    private func sortTransactionsByCreatedAtNewestFirst(_ transactions: [SimpleFinTransaction]) -> [SimpleFinTransaction] {
        return transactions.sorted { lhs, rhs in
            if lhs.createdAtDate != rhs.createdAtDate {
                return lhs.createdAtDate > rhs.createdAtDate
            }
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            return lhs.id > rhs.id
        }
    }

    private func calendarMonthRange(containing date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let end = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? start
        return (start, end)
    }

    private func periodBounds(for date: Date) -> (start: Date, endExclusive: Date) {
        let calendar = Calendar.current
        let start = getStartOfPeriod(for: date)

        if let nextPaycheck = paycheckDates.sorted().first(where: { $0 > start }) {
            return (start, nextPaycheck)
        }

        let currentStart = getStartOfPeriod(for: Date())
        if calendar.isDate(start, inSameDayAs: currentStart) {
            // Keep current period open-ended until a new paycheck posts.
            return (start, Date.distantFuture)
        }

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, nextMonth)
    }

    private func isProjectedFuturePeriodStart(_ start: Date) -> Bool {
        let calendar = Calendar.current
        let currentStart = getStartOfPeriod(for: Date())
        guard start > currentStart else { return false }
        let hasPostedBoundary = paycheckDates.contains { calendar.isDate($0, inSameDayAs: start) }
        return !hasPostedBoundary
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

    @Published var accountProfile: LunchMoneyAccountProfile?
    @Published var isLoadingAccountProfile = false
    @Published var accountProfileError: String?
    
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
        if let savedAnchor = UserDefaults.standard.object(forKey: "LastConfirmedPaycheckDate") as? Double {
            self.lastConfirmedPaycheckDate = Date(timeIntervalSince1970: savedAnchor)
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
            self.transactions = sortTransactionsByCreatedAtNewestFirst(decoded)
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
        let (periodStart, periodEnd) = periodBounds(for: selectedDate)
        let isProjectedFuturePeriod = isProjectedFuturePeriodStart(periodStart)
        let now = Date()
        
        self.currentPeriodTransactions = transactions.filter { txn in
            if hiddenTransactionIDs.contains(txn.id) { return false }
            guard txn.date >= periodStart && txn.date < periodEnd else { return false }
            // Keep already-posted transactions in the active current period
            // until an actual paycheck creates the next boundary.
            if isProjectedFuturePeriod && txn.date <= now {
                return false
            }
            return true
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
    
    func syncTransactions(startDate: Date? = nil, summaryAnchorDate: Date? = nil) async -> (String, Bool) {
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
            
            // Lunch Money summary is fetched on calendar-month boundaries even though app periods are paycheck-based.
            let summaryDate = summaryAnchorDate ?? selectedDate
            let (summaryStart, summaryEnd) = calendarMonthRange(containing: summaryDate)
            
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
                print("Skipping budget update: Lunch Money summary month not aligned with account configuration.")
            }
            
            do {
                try await service.triggerPlaidSync(apiKey: token)
            } catch {
                print("⚠️ Plaid Sync Skipped: \(error.localizedDescription)")
            }
            
            try await Task.sleep(nanoseconds: 1 * 1_000_000_000)
            
            // Pull a wider rolling window so paycheck detection has enough history
            // to keep period boundaries anchored to actual posted paychecks.
            let defaultWindowStart = Calendar.current.date(byAdding: .day, value: -45, to: Date())!
            var fetchDate = startDate ?? defaultWindowStart
            if fetchDate > defaultWindowStart {
                fetchDate = defaultWindowStart
            }
            if let anchor = lastConfirmedPaycheckDate,
               let anchorWindowStart = Calendar.current.date(byAdding: .day, value: -35, to: anchor),
               anchorWindowStart < fetchDate {
                fetchDate = anchorWindowStart
            }
            if let minDate = self.minDate {
                let minStart = Calendar.current.startOfDay(for: minDate)
                if fetchDate < minStart {
                    fetchDate = minStart
                }
            }
            print("Transaction fetch start date: \(dayFormatter.string(from: fetchDate))")
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

            let incomingIds = Set(newTransactions.map(\.id))
            let replacedPendingReferences = Set(newTransactions.compactMap(\.pendingTransactionExternalId))
            let clearedExternalIds = Set(newTransactions.filter { $0.isPending != true }.compactMap(\.externalId))

            if !manualIDsToRemove.isEmpty {
                self.hiddenTransactionIDs.subtract(manualIDsToRemove)
            }

            let filteredExisting = self.transactions.filter { txn in
                if manualIDsToRemove.contains(txn.id) { return false }

                if txn.isPending == true {
                    if replacedPendingReferences.contains(txn.id) { return false }
                    if let externalId = txn.externalId {
                        if replacedPendingReferences.contains(externalId) { return false }
                        if clearedExternalIds.contains(externalId), !incomingIds.contains(txn.id) {
                            return false
                        }
                    }
                }

                return true
            }
            var txnMap: [String: SimpleFinTransaction] = Dictionary(
                uniqueKeysWithValues: filteredExisting.map { ($0.id, $0) }
            )
            for txn in newTransactions { txnMap[txn.id] = txn }
            self.transactions = sortTransactionsByCreatedAtNewestFirst(Array(txnMap.values))
            
            isSyncing = false
            let newCount = max(0, self.transactions.count - initialCount)
            return ("Synced. \(newCount) imported", false)
            
        } catch {
            isSyncing = false
            return ("Failed: \(error.localizedDescription)", true)
        }
    }

    func refreshAccountProfile() async {
        guard let token = accessUrl else {
            self.accountProfile = nil
            self.accountProfileError = "Missing Lunch Money token."
            return
        }

        self.isLoadingAccountProfile = true
        self.accountProfileError = nil

        do {
            let profile = try await service.fetchMe(apiKey: token)
            self.accountProfile = profile
        } catch {
            self.accountProfile = nil
            self.accountProfileError = error.localizedDescription
        }

        self.isLoadingAccountProfile = false
    }
    
    func connectLunchMoney(token: String, initialBalance: Decimal, importStartDate: Date, periodStart: Date, periodEnd: Date) async {
        isSyncing = true
        errorMessage = nil
        showErrorAlert = false
        
        do {
            let calendar = Calendar.current
            let startMonth = calendar.dateComponents([.year, .month], from: periodStart)
            let endMonth = calendar.dateComponents([.year, .month], from: periodEnd)
            if startMonth != endMonth {
                self.errorMessage = "Lunch Money validation uses a single calendar month. Please select start and end dates within the same month."
                self.showErrorAlert = true
                self.isSyncing = false
                return
            }

            let (summaryStart, summaryEnd) = calendarMonthRange(containing: periodStart)
            let (aligned, _) = try await service.fetchBudgetSummary(apiKey: token, startDate: summaryStart, endDate: summaryEnd)
            
            if !aligned {
                self.errorMessage = "Lunch Money summary is not aligned for this calendar month. In Lunch Money, set Budget Period to Calendar Month."
                self.showErrorAlert = true
                self.isSyncing = false
                return
            }
            
            self.accessUrl = token
            let startDay = Calendar.current.component(.day, from: periodStart)
            self.budgetStartDay = startDay
            self.lastConfirmedPaycheckDate = Calendar.current.startOfDay(for: periodStart)
            self.minDate = importStartDate
            
            _ = await syncTransactions(
                startDate: importStartDate,
                summaryAnchorDate: periodStart
            )
            await refreshAccountProfile()
            
            self.setStartingBalance(initialBalance)
            
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
    
    func getStartOfPeriod(for date: Date) -> Date {
        let today = Date()
        let calendar = Calendar.current

        // 1. Try to find a paycheck on or before this date
        if let periodStart = paycheckDates.sorted().last(where: { $0 <= date || Calendar.current.isDate($0, inSameDayAs: date) }) {
            // For current/past dates, anchor strictly to the latest posted paycheck.
            // Do not roll to the next expected payday until a paycheck is actually posted.
            if date <= today {
                return periodStart
            }

            // For future dates, project forward using budgetStartDay only after a full cycle.
            let daysDiff = calendar.dateComponents([.day], from: periodStart, to: date).day ?? 0
            if daysDiff < 28 {
                return periodStart
            }
        }

        // 1b. If there are no currently-detected paycheck transactions, keep using
        // the last confirmed paycheck start until a new paycheck posts.
        if let anchor = lastConfirmedPaycheckDate {
            let anchoredDay = calendar.startOfDay(for: anchor)
            if date <= today && date >= anchoredDay {
                return anchoredDay
            }
            if date > today {
                let daysDiff = calendar.dateComponents([.day], from: anchoredDay, to: date).day ?? 0
                if daysDiff < 28 {
                    return anchoredDay
                }
            }
        }
        
        // 2. Fallback / Future Logic
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
                $0.isPending != true &&
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
        print("Detected paycheck dates: \(clusteredDates.map { dayFormatter.string(from: $0) })")

        if let lastPaycheck = clusteredDates.max() {
            self.lastConfirmedPaycheckDate = lastPaycheck
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
        let (periodStart, periodEnd) = periodBounds(for: date)
        let historyStart = minDate.map { Calendar.current.startOfDay(for: $0) } ?? Date.distantPast
        
        let referenceDate = min(Date(), periodEnd)
        
        let activeTxns = transactions.filter { !hiddenTransactionIDs.contains($0.id) }
        let currentActual = startingBalance + activeTxns.filter {
            $0.date >= historyStart && $0.date <= referenceDate
        }.reduce(0) { $0 + $1.decimalAmount }

        // If current period is open-ended (waiting on next posted paycheck),
        // "projected end" should just be today's actual balance.
        if periodEnd == Date.distantFuture {
            return currentActual
        }
        
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
        let createdAt = Date().timeIntervalSince1970
        let catID = categoriesMap.first(where: { $0.value.name == category })?.key
        
        let newTxn = SimpleFinTransaction(id: id, posted: posted, amount: "\(amount)", description: memo, payee: payee, memo: memo, transacted_at: createdAt, categoryId: catID)
        transactions.append(newTxn)
        transactions = sortTransactionsByCreatedAtNewestFirst(transactions)
    }
    
    func changeMonth(by value: Int) {
        guard !paycheckDates.isEmpty else {
            let currentStart = getStartOfPeriod(for: selectedDate)
            guard let targetStart = Calendar.current.date(byAdding: .month, value: value, to: currentStart) else { return }
            let actualCurrentStart = getStartOfPeriod(for: Date())
            if targetStart > actualCurrentStart && targetStart <= Date() {
                // Keep projected (future) periods reachable even if their nominal start date is in the past.
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? targetStart
            } else {
                selectedDate = targetStart
            }
            return
        }
        
        let sorted = paycheckDates.sorted()
        let currentStart = getStartOfPeriod(for: selectedDate)
        
        if let index = sorted.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: currentStart) }) {
            let newIndex = index + value
            if newIndex >= 0 && newIndex < sorted.count {
                selectedDate = sorted[newIndex]
            } else if newIndex >= sorted.count {
                if let targetStart = Calendar.current.date(byAdding: .month, value: value, to: currentStart) {
                    let actualCurrentStart = getStartOfPeriod(for: Date())
                    if targetStart > actualCurrentStart && targetStart <= Date() {
                        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? targetStart
                    } else {
                        selectedDate = targetStart
                    }
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
        let historyStart = minDate.map { Calendar.current.startOfDay(for: $0) } ?? Date.distantPast
        
        if targetStart > currentStart {
            // 1. Start with the projected ending balance of the ACTUAL current period.
            // This accounts for the "Current Actual + Remaining Budget" logic you mentioned.
            var accumulated = getProjectedEnd(for: now)
            
            // 2. Iterate through every month BETWEEN the current period and the selected future period.
            // We start checking "Next Month".
            var pointer = Calendar.current.date(byAdding: .month, value: 1, to: currentStart)!
            
            // While our pointer is still BEFORE the target month...
            while pointer < targetStart {
                // ...add the Net Budget (Income - Expenses) for that intermediate month.
                accumulated += getNetBudget(for: pointer)
                
                // Move pointer to the next month
                pointer = Calendar.current.date(byAdding: .month, value: 1, to: pointer)!
            }
            
            return accumulated
        } else {
            // Past Logic (Unchanged)
            let past = transactions.filter {
                !hiddenTransactionIDs.contains($0.id) &&
                $0.date >= historyStart &&
                $0.date < targetStart
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
    
    func updateCategory(for transactionID: String, to newCategory: String) {
        transactionCategoryOverrides[transactionID] = newCategory
        objectWillChange.send()
        updateCurrentPeriodCache()
    }

    private func replaceTransaction(_ updated: SimpleFinTransaction) {
        var updatedTransactions = transactions
        if let index = updatedTransactions.firstIndex(where: { $0.id == updated.id }) {
            updatedTransactions[index] = updated
            updatedTransactions = sortTransactionsByCreatedAtNewestFirst(updatedTransactions)
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
