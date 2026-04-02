//
//  QuickLogIntent.swift
//  dime
//
//  Created by Claude on 12/2/26.
//

import AppIntents
import Foundation
import SwiftUI
import UserNotifications

@available(iOS 16.4, *)
struct QuickLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Log Transaction"

    static var description =
        IntentDescription("Quickly log a transaction amount. Categorize it later.")

    @Parameter(title: "Type", description: "Income or expense", requestValueDialog: IntentDialog("Is this an income or expense?"))
    var income: TransactionType

    @Parameter(title: "Amount", description: "Transaction amount", controlStyle: .field, inclusiveRange: (lowerBound: 0.01, upperBound: 100_000_000), requestValueDialog: IntentDialog("How much was the transaction?"))
    var amount: Double

    @Parameter(title: "Note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        if amount == 0 {
            throw $amount.needsValueError()
        }

        let dataController = DataController.shared
        let isIncome = (income == .income)

        let transaction = dataController.newTransaction(
            note: note ?? "",
            category: nil,
            income: isIncome,
            amount: amount,
            date: Date.now,
            repeatType: 0,
            repeatCoefficient: 1,
            delay: false
        )

        // Send local notification to categorize later
        sendCategorizeNotification(for: transaction)

        let amountStr = formatAmount(amount)
        return .result(dialog: "\(amountStr) logged! Tap the notification to categorize.") {
            QuickLogConfirmationView(amount: amount, isIncome: isIncome, note: note)
        }
    }

    private func sendCategorizeNotification(for transaction: Transaction) {
        let content = UNMutableNotificationContent()

        let amountStr = formatAmount(transaction.amount)

        content.title = "\(amountStr) recorded"
        content.subtitle = "Tap to categorize this transaction"
        content.sound = .default
        content.categoryIdentifier = "CATEGORIZE_TRANSACTION"

        if let id = transaction.id {
            content.userInfo = ["transactionID": id.uuidString]
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "categorize-\(transaction.id?.uuidString ?? UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = UserDefaults(suiteName: "group.com.vanxun.dime")?.string(forKey: "currency")
            ?? Locale.current.currencyCode ?? "USD"

        let showCents = UserDefaults(suiteName: "group.com.vanxun.dime")?.bool(forKey: "showCents") ?? true
        if showCents {
            formatter.maximumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 0
        }

        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Quick log \(\.$income) of \(\.$amount)") {
            \.$note
        }
    }
}

@available(iOS 16.4, *)
struct QuickLogConfirmationView: View {
    let amount: Double
    let isIncome: Bool
    let note: String?

    @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.vanxun.dime")) var showCents: Bool = true
    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.vanxun.dime")) var currency: String = Locale.current.currencyCode!

    var amountString: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currency

        if showCents {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        return numberFormatter.string(from: NSNumber(value: amount)) ?? "$0"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(.orange)
                .frame(width: 35, height: 35, alignment: .center)

            VStack(alignment: .leading) {
                Text(note?.isEmpty == false ? note! : "Uncategorized")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)

                Text("Tap notification to categorize")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .lineLimit(1)
            }
            Spacer()
            if isIncome {
                Text("+\(amountString)")
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundColor(Color.IncomeGreen)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .layoutPriority(1)
            } else {
                Text("-\(amountString)")
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
    }
}
