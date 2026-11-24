//
//  ConversionNote.swift
//  dime
//

import SwiftUI

extension ConversionReport {
    /// "2 excluded" when a total leaves out amounts without a rate, otherwise nil.
    var note: String? {
        excludedCount > 0 ? String(localized: "\(excludedCount) excluded") : nil
    }

    var approximatePrefix: String {
        isApproximate || !isComplete ? "≈ " : ""
    }

    /// A formatted total marked as approximate, followed by how many amounts it leaves out.
    func marking(_ total: String) -> String {
        guard excludedCount > 0 else {
            return approximatePrefix + total
        }

        return approximatePrefix + total + " · " + String(localized: "\(excludedCount) excluded")
    }
}

extension Transaction {
    /// "≈ $12.30" in the main currency under a transaction in another currency, or nil for one in the main currency.
    func convertedAmountText(showCents: Bool = true) -> String? {
        let converter = CurrencyConverter.current()

        guard let code = currencyCode, !converter.isMainCurrency(code) else {
            return nil
        }

        guard let converted = converter.convert(amount, from: code, on: wrappedDate) else {
            return String(localized: "No exchange rate yet")
        }

        return "≈ " + MoneyFormatter.string(converted, currencyCode: converter.mainCurrency, showCents: showCents)
    }
}

struct ConversionNote: View {
    let report: ConversionReport

    var body: some View {
        if let note = report.note {
            Text(note)
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(Text("\(report.excludedCount) transactions have no exchange rate yet and are left out"))
        }
    }
}
