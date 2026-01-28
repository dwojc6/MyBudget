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
        if name == "🤑 Savings" { return "saved" }
        if isIncome { return "deposited" }
        return "spent"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name).font(.system(size: 16, weight: .medium))
                Spacer()
                
                if isIncome {
                    if spent > budget {
                        Text("\(formatCurrency(spent - budget)) Extra")
                            .font(.system(size: 14)).foregroundColor(.green)
                    } else {
                        Text("\(formatCurrency(budget - spent)) left")
                            .font(.system(size: 14)).foregroundColor(.gray)
                    }
                } else {
                    if spent > budget {
                        Text("\(formatCurrency(spent - budget)) Overspent")
                            .font(.system(size: 14)).foregroundColor(.red)
                    } else {
                        Text("\(formatCurrency(budget - spent)) left")
                            .font(.system(size: 14)).foregroundColor(.gray)
                    }
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5).frame(height: 8).foregroundColor(Color.gray.opacity(0.2))
                    
                    let barWidth = min(CGFloat(progress) * geometry.size.width, geometry.size.width)
                    
                    RoundedRectangle(cornerRadius: 5)
                        .frame(width: barWidth, height: 8)
                        .foregroundColor(barColor)
                }
            }.frame(height: 8)
            
            HStack {
                // UPDATED: Check for emoji strings
                HStack(spacing: 4) {
                    Text("\(formatCurrency(spent))")
                    Text(statusLabel)
                    
                    // Only show % for actual expenses (not income/savings)
                    if !isIncome && totalSpent > 0 && name != "🤑 Savings" {
                        let pct = (spent / totalSpent) * 100
                        Text("(\(String(format: "%.0f", NSDecimalNumber(decimal: pct).doubleValue))%)")
                    }
                }
                .font(.caption).foregroundColor(.gray)
                
                Spacer()
                Text("of \(formatCurrency(budget))").font(.caption).foregroundColor(.gray)
            }
        }.padding().background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(12)
    }
}

struct TransactionRow: View {
    let transaction: SimpleFinTransaction; let category: String
    private var dateString: String { let formatter = DateFormatter(); formatter.dateFormat = "MMM d, yyyy"; return formatter.string(from: transaction.date) }
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateString).font(.caption2).bold().foregroundColor(.gray)
                Text(transaction.uiName).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(transaction.cleanedDescription).font(.caption2).foregroundColor(.gray).lineLimit(1)
                Text(category).font(.caption).foregroundColor(.blue)
            }
            Spacer()
            Text(formatCurrency(transaction.decimalAmount)).font(.system(size: 14, weight: .bold)).foregroundColor(transaction.decimalAmount < 0 ? .red : .green)
        }.padding().background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(10)
    }
}
