//
//  SettingsView.swift
//  MyBudget
//
//  Created by David Wojcik on 2/10/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @ObservedObject var store: BudgetStore

    private var appVersionDisplay: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "x.x.x"
    }
    
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

                Section(header: Text("Account")) {
                    if store.isLoadingAccountProfile && store.accountProfile == nil {
                        HStack {
                            ProgressView()
                            Text("Loading account details...")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                    } else if let profile = store.accountProfile {
                        accountDetailsCard(
                            name: profile.name ?? "Unavailable",
                            email: profile.email ?? "Unavailable",
                            budgetName: profile.budgetName ?? "Unavailable"
                        )
                    } else if let error = store.accountProfileError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Unable to load account details.")
                                .font(.subheadline)
                                .foregroundColor(.red)
                            Text(error)
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
                    } else {
                        accountDetailsCard(
                            name: "Unavailable",
                            email: "Unavailable",
                            budgetName: "Unavailable"
                        )
                    }
                }
                
            }
            .listStyle(.plain)
            .background(Color(UIColor.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 2) {
                    Text("Made by David Wojcik")
                        .font(.footnote)
                        .foregroundColor(.gray)
                    Text("Version \(appVersionDisplay)")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle("Settings")
            .task {
                await store.refreshAccountProfile()
            }
        }
    }
}

private func accountDetailsCard(name: String, email: String, budgetName: String) -> some View {
    VStack(spacing: 10) {
        accountLine(title: "Name", value: name)
        accountLine(title: "Email", value: email)
        accountLine(title: "Budget", value: budgetName)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(UIColor.secondarySystemGroupedBackground))
    .cornerRadius(12)
    .listRowSeparator(.hidden)
    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    .listRowBackground(Color.clear)
}

private func accountLine(title: String, value: String) -> some View {
    HStack(alignment: .top) {
        Text(title)
            .font(.subheadline)
            .foregroundColor(.gray)
        Spacer()
        Text(value)
            .font(.subheadline)
            .multilineTextAlignment(.trailing)
    }
}
