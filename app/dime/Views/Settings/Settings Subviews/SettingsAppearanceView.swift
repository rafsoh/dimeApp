//
//  SettingsAppearanceView.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI
import WidgetKit

struct SettingsAppearanceView: View {
  @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var colourScheme: Int = 0
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

  let options = ["System", "Light", "Dark"]

  @Namespace var animation

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        ForEach(options.indices, id: \.self) { option in
          HStack {
            Text(LocalizedStringKey(options[option]))
              .font(.app(.body))
              .foregroundColor(Color.PrimaryText)

            Spacer()

            if colourScheme == option {
              Image(systemName: "checkmark")
                .font(.app(.subheadline))
                .foregroundColor(.DarkIcon.opacity(0.6))
                .matchedGeometryEffect(id: "tick", in: animation)
            }
          }
          .frame(maxWidth: .infinity, minHeight: .settingsRowHeight)
          .contentShape(Rectangle())
          .onTapGesture {
            withAnimation(.easeIn(duration: 0.15)) {
              colourScheme = option
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
              self.presentationMode.wrappedValue.dismiss()
            }
          }
          .overlay(alignment: .bottom) {
            if option < (options.count - 1) {
              Divider()
            }
          }
        }
      }
      .settingsSectionRows()

      SettingsSectionFooter("Close and reload app for change to take effect.")
    }
    .modifier(SettingsSubviewModifier(title: "Appearance"))
  }
}

struct SettingsFontView: View {
  @AppStorage(AppFont.storageKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var appFont: Int = 0
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

  /// Applied when this page closes: the tabs rebuild to pick up the new font, which would pop the page mid-tap.
  @State private var selection: AppFont = .current

  @Namespace var animation

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        ForEach(AppFont.allCases, id: \.self) { option in
          HStack {
            Text(option.displayName)
              .font(.app(.body, font: option))
              .foregroundColor(Color.PrimaryText)

            Spacer()

            if selection == option {
              Image(systemName: "checkmark")
                .font(.app(.subheadline))
                .foregroundColor(.DarkIcon.opacity(0.6))
                .matchedGeometryEffect(id: "tick", in: animation)
            }
          }
          .frame(maxWidth: .infinity, minHeight: .settingsRowHeight)
          .contentShape(Rectangle())
          .onTapGesture {
            withAnimation(.easeIn(duration: 0.15)) {
              selection = option
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
              self.presentationMode.wrappedValue.dismiss()
            }
          }
          .overlay(alignment: .bottom) {
            if option != AppFont.allCases.last {
              Divider()
            }
          }
        }
      }
      .settingsSectionRows()

      SettingsSectionFooter("Allo is by Josh Puckett, Atkinson Hyperlegible Next by the Braille Institute, Fraunces by Undercase Type and Geist Pixel by Vercel, all licensed under the SIL Open Font License.")
    }
    .modifier(SettingsSubviewModifier(title: "Font"))
    .onDisappear {
      if appFont != selection.rawValue {
        appFont = selection.rawValue
        WidgetCenter.shared.reloadAllTimelines()
      }
    }
  }
}
