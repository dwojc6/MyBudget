//
//  AdaptivePillSelector.swift
//  MyBudget
//
//  Created by David Wojcik on 2/10/26.
//

import SwiftUI

struct AdaptivePillSelector<Item: Identifiable>: View {
    let items: [Item]
    let title: (Item) -> String
    let isSelected: (Item) -> Bool
    let onSelect: (Item) -> Void

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let spacing: CGFloat = 8
            let count = max(items.count, 1)
            let pillWidth = (totalWidth - (spacing * CGFloat(count - 1))) / CGFloat(count)
            let isCompact = totalWidth < 360
            let textSize: CGFloat = isCompact ? 13 : 15
            let verticalPadding: CGFloat = isCompact ? 7 : 9
            let horizontalPadding: CGFloat = isCompact ? 10 : 14

            HStack(spacing: spacing) {
                ForEach(items) { item in
                    Button(action: { onSelect(item) }) {
                        Text(title(item))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .font(.system(size: textSize, weight: .medium))
                            .padding(.vertical, verticalPadding)
                            .padding(.horizontal, horizontalPadding)
                            .frame(width: pillWidth)
                            .foregroundColor(isSelected(item) ? .blue : .primary)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected(item) ? Color.blue.opacity(0.15) : Color(UIColor.secondarySystemGroupedBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
    }
}
