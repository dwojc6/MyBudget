//
//  String+Display.swift
//  MyBudget
//
//  Created by David Wojcik on 2/10/26.
//

import Foundation

private extension Character {
    var isEmojiLike: Bool {
        return unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }
}

extension String {
    var displayWithoutEmoji: String {
        let filtered = self.filter { !$0.isEmojiLike }
        let parts = filtered.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return parts.joined(separator: " ")
    }
}

