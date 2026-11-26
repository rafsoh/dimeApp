//
//  SettingsWeekStartView.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI
import WidgetKit

struct SettingsWeekStartView: View {
  @AppStorage("firstWeekday", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var firstWeekday: Int = 1
  @AppStorage("firstDayOfMonth", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var firstDayOfMonth: Int = 1
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

  @Namespace var animation

  var body: some View {
    ScrollViewReader { value in
      VStack(spacing: 0) {
        SettingsSectionHeader("Start of Week")

        VStack(spacing: 0) {
          ForEach(1 ... 7, id: \.self) { weekday in
            HStack {
              Text(dimeWeekdaySymbol(weekday))
                .font(.app(.body))
                .foregroundColor(Color.PrimaryText)

              Spacer()

              if firstWeekday == weekday {
                Image(systemName: "checkmark")
                  .font(.app(.subheadline, weight: .medium))
                  .foregroundColor(.DarkIcon.opacity(0.6))
                  .matchedGeometryEffect(id: "tick", in: animation)
              }
            }
            .frame(maxWidth: .infinity, minHeight: .settingsRowHeight)
            .contentShape(Rectangle())
            .onTapGesture {
              DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.15)) {
                  firstWeekday = weekday
                }
              }

              DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.presentationMode.wrappedValue.dismiss()
              }
            }
            .overlay(alignment: .bottom) {
              if weekday < 7 {
                Divider()
              }
            }
          }
        }
        .settingsSectionRows()
        .padding(.bottom, .settingsHeaderSpacing)

        SettingsSectionHeader("Start of Month")

        VStack(alignment: .leading, spacing: 0) {
          ForEach(1..<29) { day in

            HStack {
              Text("\(getOrdinal(day)) of month")
                .font(.app(.body))
                .foregroundColor(Color.PrimaryText)

              Spacer()

              if firstDayOfMonth == day {
                Image(systemName: "checkmark")
                  .font(.app(.subheadline, weight: .medium))
                  .foregroundColor(.DarkIcon.opacity(0.6))
                  .matchedGeometryEffect(id: "tick2", in: animation)
              }
            }
            .frame(maxWidth: .infinity, minHeight: .settingsRowHeight)
            .contentShape(Rectangle())
            .onTapGesture {
              DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.15)) {
                  firstDayOfMonth = day
                }
              }

              DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.presentationMode.wrappedValue.dismiss()
              }
            }
            .id(day)
            .overlay(alignment: .bottom) {
              if day < 28 {
                Divider()
              }
            }
          }
        }
        .settingsSectionRows()
      }
      .onAppear {
        value.scrollTo(firstDayOfMonth)
      }
      .onChange(of: firstWeekday) { _ in
        WidgetCenter.shared.reloadAllTimelines()
      }
      .onChange(of: firstDayOfMonth) { _ in
        WidgetCenter.shared.reloadAllTimelines()
      }
    }
    .modifier(SettingsSubviewModifier(title: "Time Frames"))
  }

  func getOrdinal(_ number: Int) -> String {
    //        if number == 1 {
    //            return String(localized: "Start")
    //        }
    //
    let formatter = NumberFormatter()
    formatter.numberStyle = .ordinal

    return formatter.string(from: number as NSNumber)!.replacingOccurrences(of: ".", with: "")
  }
}

/// The weekday's name as a standalone label, capitalized for languages like French that lowercase them.
/// `weekday` counts from 1 for Sunday, like `Calendar`.
func dimeWeekdaySymbol(_ weekday: Int) -> String {
  let symbols = Calendar.current.standaloneWeekdaySymbols
  return symbols[(weekday - 1 + symbols.count) % symbols.count].localizedCapitalized
}
