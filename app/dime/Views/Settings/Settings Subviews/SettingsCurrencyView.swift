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
            withAnimation(.easeIn(duration: 0.15)) {
              currencyCode = currency.code
            }

            NSUbiquitousKeyValueStore.default.set(currency.code, forKey: "currency")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
              self.presentationMode.wrappedValue.dismiss()
            }
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
    .modifier(SettingsSubviewModifier(title: "Currencies"))
  }
}
