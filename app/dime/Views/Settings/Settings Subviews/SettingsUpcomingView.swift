//
//  SettingsUpcomingView.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI

struct SettingsUpcomingView: View {
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
  @State private var showFuture: Bool = true

  @State private var showSoon: Bool = false
  @ObservedObject var dataController = DataController.shared

  @Namespace var animation

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        Toggle(isOn: $showFuture.animation()) {
          Text("Display on Log Page")
            .font(.app(.body))
            .foregroundColor(Color.PrimaryText)
        }
        .tint(.green)
        .frame(minHeight: .settingsRowHeight)
        .onChange(of: showFuture) { newValue in
            UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.set(
              newValue, forKey: "showUpcomingTransactions")

            if !newValue {
              showSoon = false
              UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.set(
                false, forKey: "showUpcomingTransactionsWhenUpcoming")
            }
          }

        Divider()

        Toggle(isOn: $showSoon.animation()) {
          Text("Limit to 14-Day Outlook")
            .font(.app(.body))
            .foregroundColor(Color.PrimaryText)
        }
        .tint(.green)
        .frame(minHeight: .settingsRowHeight)
        .onChange(of: showSoon) { newValue in
          UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.set(
            newValue, forKey: "showUpcomingTransactionsWhenUpcoming")
        }
      }
      .settingsSectionRows()

      SettingsSectionFooter("Don't worry, even if you do hide them there, you will aways be able to find all upcoming transactions right here.")
        .padding(.bottom, .settingsHeaderSpacing)

      FutureListView(dataController: dataController, filterMode: true, limitedMode: false)
    }
    .modifier(SettingsSubviewModifier(title: "Upcoming Logs"))
    .onAppear {
      showFuture = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.bool(
        forKey: "showUpcomingTransactions")
      showSoon = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.bool(
        forKey: "showUpcomingTransactionsWhenUpcoming")
    }
  }
}
