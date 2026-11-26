//
//  SettingsExchangeRatesView.swift
//  dime
//

import Foundation
import SwiftUI
import WidgetKit

struct SettingsExchangeRatesView: View {
    @State private var cache = ExchangeRateStore.shared.snapshot
    @State private var isRefreshing = false
    @State private var lastResult: ExchangeRateStore.RefreshResult?

    var source: String {
        cache.latestDay.flatMap { cache.days[$0]?.source.name } ?? String(localized: "None yet")
    }

    var lastUpdated: String {
        cache.latestFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Never")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                row("Source", value: source)

                Divider()

                row("Last Updated", value: lastUpdated)

                Divider()

                row("Days Saved", value: "\(cache.days.count)")
            }
            .settingsSectionRows()

            SettingsSectionFooter("Rates come from fawazahmed0/exchange-api, and from Frankfurter (European Central Bank) for dates before March 2024. Each transaction is converted at the rate on its own date. Rates are kept on this device only and are never added to your data or iCloud.")
                .padding(.bottom, .settingsHeaderSpacing)

            Button {
                refresh()
            } label: {
                Text("Refresh Rates")
                    .font(.app(.body))
                    .foregroundColor(Color.PrimaryText)
                    .frame(maxWidth: .infinity, minHeight: .settingsRowHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .overlay(alignment: .trailing) {
                if isRefreshing {
                    ProgressView()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: isRefreshing)
            .settingsSectionRows()

            if let lastResult, lastResult.failedRequests > 0 {
                SettingsSectionFooter("Some rates couldn't be downloaded. Dime will try again later, and amounts without a rate are left out of totals until then.")
            }
        }
        .modifier(SettingsSubviewModifier(title: "Exchange Rates"))
        .onReceive(NotificationCenter.default.publisher(for: ExchangeRateStore.didChangeNotification)) { _ in
            cache = ExchangeRateStore.shared.snapshot
        }
    }

    func row(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
                .font(.app(.body))
                .foregroundColor(Color.PrimaryText)

            Spacer()

            Text(value)
                .font(.app(.body))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minHeight: .settingsRowHeight)
    }

    func refresh() {
        isRefreshing = true
        let dataController = DataController.shared
        let dates = dataController.foreignCurrencyDates()

        Task {
            // A refresh can finish almost instantly, which would only flash the spinner.
            async let minimumSpin: Void? = try? Task.sleep(nanoseconds: 2_000_000_000)
            let result = await ExchangeRateStore.shared.refresh(dates: dates, force: true)
            _ = await minimumSpin

            await MainActor.run {
                lastResult = result
                isRefreshing = false
                cache = ExchangeRateStore.shared.snapshot
                dataController.objectWillChange.send()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
