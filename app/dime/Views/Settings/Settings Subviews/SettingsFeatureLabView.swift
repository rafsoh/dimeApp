//
//  SettingsFeatureLabView.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI

struct SettingsGoofyView: View {
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

  @AppStorage("confetti", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var confetti:
    Bool = false

  //    @AppStorage("chromatic", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var chromatic: Bool = false

  @AppStorage("logViewLineGraph", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var lineGraph: Bool = false

  @AppStorage("budgetViewStyle", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var budgetRows: Bool = false

  @AppStorage("swapTimeLabel", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var swapTimeLabel: Bool = false

  @AppStorage(
    "showTransactionRecommendations", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var showRecommendations: Bool = false

  @Namespace var animation

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        ToggleRow(text: "Celebrate Expenses", bool: $confetti)

        Divider()

        ToggleRow(text: "Show Line Graph", bool: $lineGraph)

        Divider()

        ToggleRow(text: "Budget Rows", bool: $budgetRows)
      }
      .settingsSectionRows()

      SettingsSectionFooter("Experimental features - proceed with caution.")
        .padding(.bottom, .settingsHeaderSpacing)

      ToggleRow(text: "Replace Time Label", bool: $swapTimeLabel)
        .settingsSectionRows()

      SettingsSectionFooter("Swaps the time label of each transaction with its category name. However, if you do not manually input a note for each transaction - in which case the note is the category name by default - duplicate text will appear.")
        .padding(.bottom, .settingsHeaderSpacing)

      ToggleRow(text: "Show Note Suggestions", bool: $showRecommendations)
        .settingsSectionRows()

      SettingsSectionFooter("Displays transaction suggestions whilst you type in the 'Note' field of the new transaction page.")

      //            ToggleRow(text: "Miles-Morales Effect", bool: $chromatic, id: 5)
      //            .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
      //
      //            Text("Enables a chromatic abberation effect on the 'New Transaction' page when a future date is set.")
      //                .font(.system(size: 12, weight: .medium, design: .rounded))
      //                .foregroundColor(Color.SubtitleText)
      //                .padding(.horizontal, 15)
      //                .frame(maxWidth: .infinity, alignment: .leading)
      //                .padding(.bottom, 30)
    }
    .modifier(SettingsSubviewModifier(title: "Feature Lab"))
  }

  func ToggleRow(text: String, bool: Binding<Bool>) -> some View {
    Toggle(isOn: bool.animation()) {
      Text(LocalizedStringKey(text))
        .font(.system(.body, design: .rounded))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .foregroundColor(Color.PrimaryText)
    }
    .tint(.green)
    .frame(minHeight: .settingsRowHeight)
  }
}
