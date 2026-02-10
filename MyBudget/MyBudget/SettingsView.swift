//
//  SettingsView.swift
//  MyBudget
//
//  Created by David Wojcik on 2/10/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("Notifications.BudgetAlertsEnabled") private var budgetAlertsEnabled = false
    @AppStorage("Notifications.DailyBalanceEnabled") private var dailyBalanceEnabled = false
    @AppStorage("Notifications.WeeklySummaryEnabled") private var weeklySummaryEnabled = false

    @ObservedObject var store: BudgetStore

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Appearance")) {
                    AdaptivePillSelector(
                        items: AppearanceMode.allCases,
                        title: { $0.title },
                        isSelected: { $0.rawValue == appearanceMode },
                        onSelect: { appearanceMode = $0.rawValue }
                    )
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section(header: Text("Notifications")) {
                    notificationRow(
                        title: "Budget Alerts",
                        description: "Get notified when a budgeted amount reaches 80%.",
                        isOn: $budgetAlertsEnabled
                    ) {
                        Task {
                            let granted = await NotificationManager.shared.requestAuthorizationIfNeeded()
                            if granted {
                                store.evaluateBudgetAlerts()
                            }
                        }
                    }

                    notificationRow(
                        title: "Daily Balance",
                        description: "Receive a daily notification at 9:00 AM with the current period ending balance.",
                        isOn: $dailyBalanceEnabled
                    ) {
                        Task {
                            let granted = await NotificationManager.shared.requestAuthorizationIfNeeded()
                            if granted {
                                await NotificationManager.shared.scheduleDailyBalanceNotification(balance: store.endingBalance(for: Date()))
                            }
                        }
                    } offAction: {
                        Task { await NotificationManager.shared.cancelDailyBalanceNotification() }
                    }

                    notificationRow(
                        title: "Weekly Summary",
                        description: "Receive a weekly notification on Sunday at 9:00 PM with total income and expenses for the current week.",
                        isOn: $weeklySummaryEnabled
                    ) {
                        Task {
                            let granted = await NotificationManager.shared.requestAuthorizationIfNeeded()
                            if granted {
                                let interval = store.currentWeekInterval()
                                let totals = store.totals(in: interval)
                                await NotificationManager.shared.scheduleWeeklySummaryNotification(
                                    income: totals.income,
                                    expenses: totals.expenses
                                )
                            }
                        }
                    } offAction: {
                        Task { await NotificationManager.shared.cancelWeeklySummaryNotification() }
                    }
                }
            }
            .listStyle(.plain)
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Settings")
            .onAppear {
                Task {
                    if dailyBalanceEnabled {
                        await NotificationManager.shared.scheduleDailyBalanceNotification(balance: store.endingBalance(for: Date()))
                    }
                    if weeklySummaryEnabled {
                        let interval = store.currentWeekInterval()
                        let totals = store.totals(in: interval)
                        await NotificationManager.shared.scheduleWeeklySummaryNotification(
                            income: totals.income,
                            expenses: totals.expenses
                        )
                    }
                }
            }
        }
    }
}

private func notificationRow(
    title: String,
    description: String,
    isOn: Binding<Bool>,
    onAction: @escaping () -> Void,
    offAction: (() -> Void)? = nil
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Toggle(title, isOn: isOn)
            .onChange(of: isOn.wrappedValue) { newValue in
                if newValue {
                    onAction()
                } else {
                    offAction?()
                }
            }
        Text(description)
            .font(.caption)
            .foregroundColor(.gray)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(UIColor.secondarySystemGroupedBackground))
    .cornerRadius(12)
    .listRowSeparator(.hidden)
    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    .listRowBackground(Color.clear)
}
