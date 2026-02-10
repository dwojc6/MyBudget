//
//  BudgetCimponents.swift
//  MyBudget
//
//  Created by David Wojcik on 1/25/26.
//

import SwiftUI

struct SummaryView: View {
    let title: String; let amount: Decimal; let color: Color
    var showEditIcon: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundColor(.gray).lineLimit(1)
                if showEditIcon {
                    Image(systemName: "pencil").font(.caption2).foregroundColor(.gray)
                }
            }
            Text(formatCurrency(amount)).font(.headline).bold().foregroundColor(color).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct CategoryProgressRow: View {
    let name: String; let spent: Decimal; let budget: Decimal
    var totalSpent: Decimal = 0.0
    var customColor: Color? = nil
    var isIncome: Bool = false

    private var isSavingsCategory: Bool {
        return name.localizedCaseInsensitiveContains("savings")
    }
    
    private var progress: Double {
        return Double(truncating: (budget > 0 ? spent / budget : 0) as NSNumber)
    }
    
    private var barColor: Color {
        if let c = customColor { return c }
        if isIncome {
            return progress >= 1.0 ? .green : .blue
        } else {
            return progress > 1.0 ? .red : .blue
        }
    }
    
    // UPDATED: Check for emoji strings
    private var statusLabel: String {
        if isSavingsCategory { return "saved" }
        if isIncome { return "deposited" }
        return "spent"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(.system(size: 18, weight: .semibold))
                Spacer()
                
                if isIncome {
                    if spent > budget {
                        Text("\(formatCurrency(spent - budget)) Extra")
                            .font(.system(size: 15, weight: .medium)).foregroundColor(.green)
                    } else {
                        Text("\(formatCurrency(budget - spent)) left")
                            .font(.system(size: 15, weight: .medium)).foregroundColor(.gray)
                    }
                } else {
                    if spent > budget {
                        Text("\(formatCurrency(spent - budget)) Overspent")
                            .font(.system(size: 15, weight: .medium)).foregroundColor(.red)
                    } else {
                        Text("\(formatCurrency(budget - spent)) left")
                            .font(.system(size: 15, weight: .medium)).foregroundColor(.gray)
                    }
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).frame(height: 10).foregroundColor(Color.gray.opacity(0.2))
                    
                    let barWidth = min(CGFloat(progress) * geometry.size.width, geometry.size.width)
                    
                    RoundedRectangle(cornerRadius: 5)
                        .frame(width: barWidth, height: 10)
                        .foregroundColor(barColor)
                }
            }.frame(height: 10)
            
            HStack {
                // UPDATED: Check for emoji strings
                HStack(spacing: 4) {
                    Text("\(formatCurrency(spent))")
                    Text(statusLabel)
                    
                    // Only show % for actual expenses (not income/savings)
                    if !isIncome && totalSpent > 0 && !isSavingsCategory {
                        let pct = (spent / totalSpent) * 100
                        Text("(\(String(format: "%.0f", NSDecimalNumber(decimal: pct).doubleValue))%)")
                    }
                }
                .font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
                
                Spacer()
                Text("of \(formatCurrency(budget))").font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
            }
        }
        .padding(20)
        .frame(minHeight: 104)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }
}

struct TransactionRow: View {
    let transaction: SimpleFinTransaction; let category: String
    private var dateString: String { let formatter = DateFormatter(); formatter.dateFormat = "MMM d, yyyy"; return formatter.string(from: transaction.date) }
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateString).font(.caption2).bold().foregroundColor(.gray)
                Text(titleCasePreservingAcronyms(transaction.uiName.displayWithoutEmoji)).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(titleCasePreservingAcronyms(transaction.cleanedDescription.displayWithoutEmoji)).font(.caption2).foregroundColor(.gray).lineLimit(1)
                Text(titleCasePreservingAcronyms(category.displayWithoutEmoji)).font(.caption).foregroundColor(.blue)
            }
            Spacer()
            Text(formatCurrency(transaction.decimalAmount)).font(.system(size: 14, weight: .bold)).foregroundColor(transaction.decimalAmount < 0 ? .red : .green)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

private func titleCasePreservingAcronyms(_ text: String) -> String {
    let tokens = text.split(whereSeparator: { $0.isWhitespace })
    let transformed = tokens.map { token in
        return transformTokenPreservingAcronyms(String(token))
    }
    return transformed.joined(separator: " ")
}

private func transformTokenPreservingAcronyms(_ token: String) -> String {
    var result = ""
    var current = ""
    var currentIsWord = false

    func flush() {
        guard !current.isEmpty else { return }
        if currentIsWord {
            result.append(transformWordSegment(current))
        } else {
            result.append(current)
        }
        current = ""
    }

    for ch in token {
        let isWord = ch.isLetter || ch.isNumber
        if current.isEmpty {
            currentIsWord = isWord
            current.append(ch)
        } else if isWord == currentIsWord {
            current.append(ch)
        } else {
            flush()
            currentIsWord = isWord
            current.append(ch)
        }
    }
    flush()
    return result
}

private func transformWordSegment(_ segment: String) -> String {
    let letters = segment.filter { $0.isLetter }
    let isAllCaps = segment == segment.uppercased()
    let hasDigits = segment.rangeOfCharacter(from: .decimalDigits) != nil
    let knownAcronyms: Set<String> = [
        "ATM", "ACH", "LLC", "INC", "IRS", "POS", "PPD", "WEB", "ID", "CO",
        "DES", "INDN", "DBA", "SSN", "FBO", "P2P", "USA", "US"
    ]

    if !letters.isEmpty && isAllCaps {
        if hasDigits { return segment }
        if letters.count <= 3 { return segment }
        if knownAcronyms.contains(segment) { return segment }
    }

    let lower = segment.lowercased()
    guard let first = lower.first else { return lower }
    if !first.isLetter { return lower }
    return String(first).uppercased() + lower.dropFirst()
}
