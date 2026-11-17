//
//  Helper.swift
//  dime
//
//  Created by Rafael Soh on 13/8/22.
//

import Foundation

extension Transaction {
    var wrappedAmount: Double {
        amount
    }

    var wrappedIcon: String {
        category?.wrappedIcon ?? CategorySymbols.fallback
    }

    var wrappedDate: Date {
        date ?? Date.now
    }

    var wrappedNote: String {
        note ?? ""
    }

    var wrappedCategoryName: String {
        category?.wrappedName ?? ""
    }

    var wrappedColour: String {
        category?.wrappedColour ?? ""
    }

    /// Free-form tags, stored comma-separated (commas are stripped from tag names).
    var wrappedTags: [String] {
        get {
            (tags ?? "").split(separator: ",").map { String($0) }.filter { !$0.isEmpty }
        }
        set {
            let cleaned = newValue.map(Transaction.cleanTag).filter { !$0.isEmpty }
            tags = cleaned.isEmpty ? nil : cleaned.joined(separator: ",")
        }
    }

    static func cleanTag(_ tag: String) -> String {
        tag.replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ";", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))
    }

    var nextTransactionDate: Date {
        RecurrenceRule.nextDate(after: day ?? Date.now, type: Int(recurringType), coefficient: Int(recurringCoefficient))
            ?? date ?? Date.now
    }
}

extension TemplateTransaction {
    var wrappedAmount: Double {
        amount
    }

    var wrappedIcon: String {
        category?.wrappedIcon ?? CategorySymbols.fallback
    }

    var wrappedNote: String {
        note ?? ""
    }

    var wrappedEmoji: String {
        category?.wrappedEmoji ?? ""
    }

    var wrappedColour: String {
        category?.wrappedColour ?? ""
    }
}

extension Category {
    var wrappedColour: String {
        colour ?? "#FFFFFF"
    }

    var wrappedEmoji: String {
        emoji ?? "😄️"
    }

    /// SF Symbol shown for the category: the chosen one, or one matched from its emoji.
    var wrappedIcon: String {
        if let symbol, !symbol.isEmpty {
            return symbol
        }
        return CategorySymbols.symbol(forEmoji: wrappedEmoji)
    }

    var wrappedName: String {
        name ?? ""
    }

    var wrappedDate: Date {
        dateCreated ?? Date.now
    }

    var fullName: String {
        wrappedEmoji + "  " + wrappedName
    }

    var allTransactions: [Transaction] {
        let set = transactions as? Set<Transaction> ?? []
        return set.sorted {
            $0.wrappedDate < $1.wrappedDate
        }
    }

    var transactionCount: Int {
        transactions?.count ?? 0
    }
}

public extension Budget {
    var wrappedColour: String {
        category?.wrappedColour ?? "#FFFFFF"
    }

    var wrappedName: String {
        category?.wrappedName ?? ""
    }

    var wrappedEmoji: String {
        category?.wrappedEmoji ?? ""
    }

    var wrappedIcon: String {
        category?.wrappedIcon ?? CategorySymbols.fallback
    }

    var fullName: String {
        return wrappedEmoji + " " + wrappedName
    }

    var wrappedDate: Date {
        return startDate ?? Date.now
    }

    var endDate: Date {
        BudgetPeriod.end(of: startDate ?? Date.now, type: Int(type)) ?? (startDate ?? Date.now)
    }
}

public extension MainBudget {
    var wrappedDate: Date {
        return startDate ?? Date.now
    }

    var endDate: Date {
        BudgetPeriod.end(of: startDate ?? Date.now, type: Int(type)) ?? (startDate ?? Date.now)
    }
}


/// SF Symbols for categories. Older categories only have an emoji; they get the closest symbol.
/// When a symbol is picked, a matching emoji is still saved so older app versions show something sensible.
enum CategorySymbols {
    static let fallback = "tag.fill"

    /// Emoji → symbol, covering the suggested categories and common choices.
    static let byEmoji: [String: String] = [
        "🍔": "fork.knife", "🍕": "fork.knife", "🍜": "fork.knife", "🍽️": "fork.knife", "🍱": "takeoutbag.and.cup.and.straw.fill",
        "☕": "cup.and.saucer.fill", "☕️": "cup.and.saucer.fill", "🍺": "wineglass.fill", "🍷": "wineglass.fill", "🍸": "wineglass.fill",
        "🛒": "cart.fill", "🛍️": "bag.fill", "🛍": "bag.fill", "👔": "tshirt.fill", "👕": "tshirt.fill", "👗": "tshirt.fill", "👟": "shoe.fill",
        "🏠": "house.fill", "🏡": "house.fill", "🏢": "building.2.fill", "💡": "lightbulb.fill", "🔌": "bolt.fill", "⚡": "bolt.fill", "⚡️": "bolt.fill",
        "💧": "drop.fill", "🔥": "flame.fill", "📱": "iphone", "💻": "laptopcomputer", "📺": "tv.fill", "🎮": "gamecontroller.fill",
        "🚆": "tram.fill", "🚇": "tram.fill", "🚌": "bus.fill", "🚗": "car.fill", "🚕": "car.fill", "⛽": "fuelpump.fill", "⛽️": "fuelpump.fill",
        "✈️": "airplane", "✈": "airplane", "🚲": "bicycle", "🛵": "scooter", "🏖️": "beach.umbrella.fill", "🧳": "suitcase.fill", "🏨": "bed.double.fill",
        "🔄": "arrow.triangle.2.circlepath", "📦": "shippingbox.fill", "🎁": "gift.fill", "🎉": "party.popper.fill", "🎬": "film.fill",
        "🎵": "music.note", "🎶": "music.note", "📚": "book.fill", "📖": "book.fill", "🎓": "graduationcap.fill", "✏️": "pencil",
        "🚑": "cross.case.fill", "💊": "pills.fill", "🏥": "cross.case.fill", "🦷": "mouth.fill", "💪": "dumbbell.fill", "🏋️": "dumbbell.fill",
        "⚽": "soccerball", "⚽️": "soccerball", "💇": "scissors", "💅": "sparkles", "🧴": "sparkles", "🐕": "pawprint.fill", "🐈": "pawprint.fill",
        "🐶": "pawprint.fill", "🐱": "pawprint.fill", "👶": "figure.and.child.holdinghands", "👨‍👩‍👦": "figure.2.and.child.holdinghands",
        "👨‍👩‍👧‍👦": "figure.2.and.child.holdinghands", "❤️": "heart.fill", "💝": "heart.fill", "🙏": "hands.sparkles.fill",
        "💰": "banknote.fill", "💵": "banknote.fill", "💶": "banknote.fill", "🪙": "dollarsign.circle.fill", "🤑": "dollarsign.circle.fill",
        "💹": "chart.line.uptrend.xyaxis", "📈": "chart.line.uptrend.xyaxis", "💼": "briefcase.fill", "🧧": "envelope.fill", "🏦": "building.columns.fill",
        "💳": "creditcard.fill", "🧾": "doc.text.fill", "📄": "doc.text.fill", "🔧": "wrench.and.screwdriver.fill", "🛠️": "wrench.and.screwdriver.fill",
        "🧹": "bubbles.and.sparkles.fill", "🌱": "leaf.fill", "🌳": "tree.fill", "☂️": "umbrella.fill", "🛡️": "shield.fill", "🏷️": "tag.fill"
    ]

    /// Symbols offered when choosing a category icon, grouped loosely by theme.
    static let all: [String] = [
        "fork.knife", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill", "wineglass.fill", "cart.fill", "bag.fill",
        "basket.fill", "tshirt.fill", "shoe.fill", "house.fill", "building.2.fill", "bed.double.fill",
        "lightbulb.fill", "bolt.fill", "drop.fill", "flame.fill", "wifi", "iphone",
        "laptopcomputer", "tv.fill", "gamecontroller.fill", "headphones", "tram.fill", "bus.fill",
        "car.fill", "fuelpump.fill", "parkingsign", "bicycle", "scooter", "airplane",
        "suitcase.fill", "beach.umbrella.fill", "map.fill", "ticket.fill", "film.fill", "music.note",
        "book.fill", "graduationcap.fill", "pencil", "paintbrush.fill", "camera.fill", "party.popper.fill",
        "gift.fill", "heart.fill", "cross.case.fill", "pills.fill", "stethoscope", "dumbbell.fill",
        "figure.run", "soccerball", "scissors", "sparkles", "pawprint.fill", "leaf.fill",
        "figure.and.child.holdinghands", "figure.2.and.child.holdinghands", "person.2.fill", "hands.sparkles.fill", "arrow.triangle.2.circlepath", "shippingbox.fill",
        "wrench.and.screwdriver.fill", "hammer.fill", "bubbles.and.sparkles.fill", "umbrella.fill", "shield.fill", "doc.text.fill",
        "creditcard.fill", "banknote.fill", "dollarsign.circle.fill", "chart.line.uptrend.xyaxis", "briefcase.fill", "building.columns.fill",
        "envelope.fill", "percent", "smoke.fill", "star.fill", "globe", "tag.fill"
    ]

    static func symbol(forEmoji emoji: String) -> String {
        if let match = byEmoji[emoji] {
            return match
        }
        // tolerate variation selectors (e.g. "☕︎" vs "☕️")
        let stripped = emoji.unicodeScalars.filter { $0.value != 0xFE0F && $0.value != 0xFE0E }
        return byEmoji[String(String.UnicodeScalarView(stripped))] ?? fallback
    }

    /// A representative emoji for a symbol, saved alongside it for older app versions.
    static func emoji(forSymbol symbol: String) -> String {
        byEmoji.filter { $0.value == symbol }.map(\.key).min() ?? "🏷️"
    }
}
