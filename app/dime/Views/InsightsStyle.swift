//
//  InsightsStyle.swift
//  dime
//

import Foundation
import SwiftUI

struct InsightsFormatter {
    let currencySymbol: String
    let showCents: Bool

    static var current: InsightsFormatter {
        let formatter = BudgetFormatter.current
        return InsightsFormatter(currencySymbol: formatter.currencySymbol, showCents: formatter.showCents)
    }

    func number(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let digits = showCents && amount < 10000 ? 2 : 0
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }

    func string(_ amount: Double) -> String {
        currencySymbol + number(amount)
    }

    func rounded(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return currencySymbol + (formatter.string(from: NSNumber(value: amount.rounded())) ?? "0")
    }

    /// Short enough for a chart label, e.g. "$42" or "$1.2k".
    func compact(_ amount: Double) -> String {
        if amount >= 1000 {
            let thousands = amount / 1000
            return currencySymbol + String(format: thousands >= 10 ? "%.0fk" : "%.1fk", thousands)
        }
        return currencySymbol + String(Int(amount.rounded()))
    }
}

struct InsightsCardTitle: View {
    let title: Text

    init(_ title: LocalizedStringKey) {
        self.title = Text(title)
    }

    init(verbatim title: String) {
        self.title = Text(title)
    }

    var body: some View {
        title
            .font(.app(.subheadline, weight: .semibold))
            .foregroundColor(Color.SubtitleText)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

struct InsightsAmountText: View {
    let amount: Double
    var sign: String = ""
    let formatter: InsightsFormatter
    let font: Font

    var body: some View {
        (Text(sign + formatter.currencySymbol).foregroundColor(Color.SubtitleText) + Text(formatter.number(amount)).foregroundColor(Color.PrimaryText))
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(sign + formatter.string(amount))
    }
}
