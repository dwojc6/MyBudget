//
//  ContentView.swift
//  MyBudget
//
//  Created by David Wojcik on 1/23/26.
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct ContentView: View {
    @StateObject var store = BudgetStore()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    private var currentAppearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }
    
    var body: some View {
        Group {
            if store.accessUrl == nil {
                LunchMoneySetupView(store: store)
            } else {
                TabView {
                    DashboardView(store: store)
                        .tabItem {
                            Image(systemName: "list.bullet.rectangle")
                            Text("Transactions")
                        }
                    
                    ReportsView(store: store)
                        .tabItem {
                            Image(systemName: "chart.bar")
                            Text("Reports")
                        }
                    
                    SettingsView(store: store)
                        .tabItem {
                            Image(systemName: "gearshape")
                            Text("Settings")
                        }
                }
            }
        }
        .preferredColorScheme(currentAppearance.colorScheme)
    }
}

extension String: Identifiable { public var id: String { return self } }
func formatCurrency(_ amount: Decimal) -> String { let formatter = NumberFormatter(); formatter.numberStyle = .currency; return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00" }
