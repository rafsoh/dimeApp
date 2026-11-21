//
//  SettingsNumberEntryView.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI

struct SettingsNumberEntryView: View {
  @AppStorage("numberEntryType", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var numberEntryType: Int = 1
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
  @Environment(\.colorScheme) var colorScheme
  @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency:
    String = Locale.current.currencyCode!
  private var currencySymbol: String {
    return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
  }

  @State private var price: Double = 0
  @State private var category: Category?
  @State var isEditingDecimal = false
  @State var decimalValuesAssigned: AssignedDecimal = .none
  @State private var priceString: String = "0"

  private var disabled: Bool {
    price == 0.0
  }

  let options = ["Type 1", "Type 2"]

  @Namespace var animation

  var body: some View {
    VStack(spacing: 10) {
      GlassSegmentedPicker(
        selection: $numberEntryType,
        options: options.indices.map { (value: $0 + 1, title: LocalizedStringKey(options[$0])) }
      )
      .padding(25)

      VStack(spacing: 10) {
        if numberEntryType == 1 {
          Text("\"Pre-dotted\"")
            .font(.system(.title2, design: .rounded).weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundColor(Color.PrimaryText)

          Text("If you're too lazy to add a decimal point, I gotchu covered.")
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .multilineTextAlignment(.center)
            .foregroundColor(Color.SubtitleText)
        } else {
          Text("\"Cent-less\"")
            .font(.system(.title2, design: .rounded).weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundColor(Color.PrimaryText)

          Text("If your transactions usually amount to whole numbers - this one is for you.")
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .multilineTextAlignment(.center)
            .foregroundColor(Color.SubtitleText)
        }
      }
      .padding(.horizontal, 25)

      Spacer()

      NumberPadTextView(
        price: $price,
        isEditingDecimal: $isEditingDecimal,
        decimalValuesAssigned: $decimalValuesAssigned
      )

      Spacer()

      NumberPad(
        price: $price,
        category: $category,
        isEditingDecimal: $isEditingDecimal,
        decimalValuesAssigned: $decimalValuesAssigned
      ) {
        submit()
      }
    }
    .modifier(SettingsSubviewModifier(title: "Number Entry Method", scrollable: false))
  }

  func submit() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    price = 0
  }
}
