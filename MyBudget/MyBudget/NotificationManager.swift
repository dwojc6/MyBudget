//
//  NotificationManager.swift
//  MyBudget
//
//  Created by David Wojcik on 2/10/26.
//

import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    private let dailyBalanceId = "daily-balance"
    private let weeklySummaryId = "weekly-summary"

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func scheduleDailyBalanceNotification(balance: Decimal) async {
        await cancelDailyBalanceNotification()

        let content = UNMutableNotificationContent()
        content.title = "Daily Balance"
        content.body = "Ending balance: \(formatCurrency(balance))"
        content.sound = .default

        var components = DateComponents()
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: dailyBalanceId, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func scheduleWeeklySummaryNotification(income: Decimal, expenses: Decimal) async {
        await cancelWeeklySummaryNotification()

        let content = UNMutableNotificationContent()
        content.title = "Weekly Summary"
        content.body = "Income: \(formatCurrency(income)) • Expenses: \(formatCurrency(expenses))"
        content.sound = .default

        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour = 21
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: weeklySummaryId, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func sendBudgetAlert(category: String, percent: Decimal, spent: Decimal, budget: Decimal) async {
        let content = UNMutableNotificationContent()
        content.title = "Budget Alert"
        let pctString = String(format: "%.0f", NSDecimalNumber(decimal: percent).doubleValue)
        content.body = "\(category) is at \(pctString)% (\(formatCurrency(spent)) of \(formatCurrency(budget)))."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancelDailyBalanceNotification() async {
        await center.removePendingNotificationRequests(withIdentifiers: [dailyBalanceId])
    }

    func cancelWeeklySummaryNotification() async {
        await center.removePendingNotificationRequests(withIdentifiers: [weeklySummaryId])
    }
}
