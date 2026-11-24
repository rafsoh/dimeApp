//
//  SettingsCurrencyView.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI

struct SettingsCurrencyView: View {
  @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var currencyCode: String = Locale.current.currencyCode!
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
  @Environment(\.dynamicTypeSize) var dynamicTypeSize

  @ObservedObject private var changeManager = MainCurrencyChangeManager.shared
  @State private var proposedCurrency: Currency?
  @State private var errorMessage: String?

  let currencies = Currency.allCurrencies

  @Namespace var animation

  var body: some View {
    ScrollViewReader { value in
      VStack(spacing: 0) {
        ForEach(currencies, id: \.self) { currency in
          HStack(spacing: 10) {
            Text(currency.code)
              .font(.system(.body, design: .rounded).weight(.semibold))
              .foregroundColor(Color.SubtitleText)
              .lineLimit(1)
              //                                    .layoutPriority(1)
              .frame(width: dynamicTypeSize > .xLarge ? 55 : 45, alignment: .leading)
            Text(currency.name)
              .font(.system(.body, design: .rounded))
              .foregroundColor(Color.PrimaryText)
              .lineLimit(1)

            Spacer()

            if currency.code == currencyCode {
              Image(systemName: "checkmark")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.DarkIcon.opacity(0.6))
                .matchedGeometryEffect(id: "tick", in: animation)
            }
          }
          .frame(maxWidth: .infinity, minHeight: .settingsRowHeight)
          .contentShape(Rectangle())
          .onTapGesture {
            guard currency.code != currencyCode, !changeManager.isWorking else {
              return
            }

            proposedCurrency = currency
          }
          .overlay(alignment: .bottom) {
            if currency != currencies.last {
              Divider()
            }
          }
          .padding(.horizontal, .settingsRowInset)
          .id(currency.code)
        }
      }
      .settingsSectionBackground()
      .onAppear {
        value.scrollTo(currencyCode, anchor: .center)
      }
    }
    .modifier(SettingsSubviewModifier(title: "Primary Currency"))
    .overlay {
      if changeManager.isWorking {
        ProgressView()
      }
    }
    .confirmationDialog(
      Text("Change your primary currency?"),
      isPresented: Binding(get: { proposedCurrency != nil }, set: { if !$0 { proposedCurrency = nil } }),
      titleVisibility: .visible,
      presenting: proposedCurrency
    ) { currency in
      Button("My transactions were actually in \(currency.code)") {
        change(to: currency, kind: .relabel)
      }

      Button("Convert to \(currency.code)") {
        change(to: currency, kind: .convert)
      }

      Button("Cancel", role: .cancel) {}
    } message: { currency in
      Text("Relabelling keeps every amount as it is and treats your \(currencyCode) transactions as \(currency.code). Converting keeps them in \(currencyCode) and shows them in \(currency.code) at each day's rate. Budgets and templates keep their amounts. Dime backs up your data first.")
    }
    .alert(
      Text("Currency not changed"),
      isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
  }

  func change(to currency: Currency, kind: MainCurrencyChangePlan.Kind) {
    changeManager.change(to: currency.code, kind: kind) { result in
      switch result {
      case .success:
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
          self.presentationMode.wrappedValue.dismiss()
        }
      case let .failure(error):
        errorMessage = message(for: error)
      }
    }
  }

  func message(for error: MainCurrencyChangeManager.ChangeError) -> String {
    switch error {
    case .busy:
      return String(localized: "Dime is still finishing your last currency change. Try again in a moment.")
    case .waitingForICloud:
      return String(localized: "Dime is still catching up with iCloud. Try again once it's up to date.")
    case .backupFailed:
      return String(localized: "Dime couldn't back up your data first, so nothing was changed. Please try again.")
    case .failed:
      return String(localized: "Dime couldn't finish changing your currency. Nothing was lost, and it will finish the next time you open Dime.")
    }
  }
}
