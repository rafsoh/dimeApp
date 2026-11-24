//
//  CurrencyPicker.swift
//  dime
//

import SwiftUI

struct CurrencyPickerSheet: View {
    @Binding var currencyCode: String
    let mainCurrency: String

    @Environment(\.dismiss) var dismiss
    @State private var search = ""

    private let currencies = Currency.allCurrencies

    private var pinnedCodes: [String] {
        let recent = CurrencyPreferences.recentCurrencies(in: UserDefaults(suiteName: CurrencyConverter.appGroup))
        let known = Set(currencies.map(\.code))
        return CurrencyPreferences.pickerOrder(codes: [], recent: recent, mainCurrency: mainCurrency).filter { known.contains($0) }
    }

    private func matches(_ currency: Currency) -> Bool {
        search.isEmpty || currency.code.localizedCaseInsensitiveContains(search) || currency.name.localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        NavigationView {
            List {
                if search.isEmpty {
                    Section(header: Text("Recent")) {
                        ForEach(pinnedCodes.compactMap { code in currencies.first { $0.code == code } }, id: \.code) { currency in
                            row(currency)
                        }
                    }
                }

                Section(header: Text("All Currencies")) {
                    ForEach(currencies.filter { matches($0) }, id: \.code) { currency in
                        row(currency)
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle(Text("Currency"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                }
            }
        }
    }

    private func row(_ currency: Currency) -> some View {
        Button {
            currencyCode = currency.code
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Text(currency.code)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.SubtitleText)
                    .frame(width: 50, alignment: .leading)

                Text(currency.name)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)

                Spacer()

                if currency.code == currencyCode {
                    Image(systemName: "checkmark")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.PrimaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
