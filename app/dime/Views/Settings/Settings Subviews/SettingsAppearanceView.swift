//
//  SettingsAppearanceView.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI

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
              .font(.system(.body, design: .rounded))
              .foregroundColor(Color.PrimaryText)

            Spacer()

            if colourScheme == option {
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
