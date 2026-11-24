//
//  SettingsEraseView.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI

struct SettingsEraseView: View {
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

  @State var showAlert = false

  var body: some View {
    VStack(spacing: 0) {
      Button {
        showAlert = true
      } label: {
        Text("Permanently Delete Everythin'")
          .font(.system(.body, design: .rounded))
          .foregroundColor(Color.AlertRed)
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(minHeight: .settingsRowHeight)
          .settingsSectionRows()
      }

      SettingsSectionFooter("This action would delete all existing transactions, categories, and budgets, and cannot be undone.")
    }
    .modifier(SettingsSubviewModifier(title: "Erase Data"))
    .sheet(isPresented: $showAlert) {
      DeleteAllAlert()
    }
  }
}

struct DeleteAllAlert: View {
  @EnvironmentObject var dataController: DataController
  @Environment(\.dismiss) var dismiss

  @GestureState var isDetectingLongPress = false
  @State var completedLongPress = false

  var body: some View {
    ConfirmationSheet(
      title: "Danger Zone",
      message: "This action genuinely cannot be undone. Long press to confirm.",
      systemImage: "exclamationmark.triangle.fill"
    ) {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Rectangle()
            .fill(Color.AlertRed)
            .offset(x: completedLongPress || isDetectingLongPress ? 0 : -proxy.size.width)
            .animation(.easeInOut(duration: 2), value: isDetectingLongPress)

          Text("Delete Literally Everything")
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundColor(.white)
            .frame(width: proxy.size.width, alignment: .center)
        }
        .frame(height: proxy.size.height)
        .clipShape(Capsule())
      }
      .frame(height: 50)
      .frame(maxWidth: .infinity)
      .glassBackground(in: Capsule(), tint: Color.AlertRed.opacity(0.35), interactive: false, fallback: Color.AlertRed.opacity(0.35))
      .contentShape(Capsule())
      .gesture(
        LongPressGesture(minimumDuration: 2)
          .updating($isDetectingLongPress) { currentState, state, _ in
            state = currentState
          }
          .onEnded { _ in
            completedLongPress.toggle()
          }
      )
      .onChange(of: completedLongPress) { _ in
        if completedLongPress {
          let impactMed = UIImpactFeedbackGenerator(style: .heavy)
          impactMed.impactOccurred()

          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dataController.deleteAll()

            dismiss()
          }
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Delete Literally Everything")
      .accessibilityAddTraits(.isButton)

      ConfirmationCancelButton("Back Out") {
        dismiss()
      }
    }
  }
}
