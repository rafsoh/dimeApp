//
//  SettingsNotificationView.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI

struct SettingsNotificationsView: View {
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

  @AppStorage("showNotifications", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var showNotifications: Bool = false
  @AppStorage("notificationsEnabled", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var notificationsEnabled: Bool = true
  @State var option = 1
  @State private var customTimerList: [Date] = []

  var center = UNUserNotificationCenter.current()

  @Namespace var animation

  var body: some View {
    VStack {
      Text("Notifications")
        .font(.system(.title3, design: .rounded).weight(.semibold))
        .foregroundColor(Color.PrimaryText)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
          Button {
            self.presentationMode.wrappedValue.dismiss()
          } label: {
            SettingsBackButton()
          }
        }
        .padding(.bottom, 20)

      VStack(spacing: 0) {
        HStack {
          Text("Enable Notifications")
            .font(.system(.body, design: .rounded))
            .foregroundColor(Color.PrimaryText)

          Spacer()

          ZStack(alignment: showNotifications ? .trailing : .leading) {
            Capsule()
              .frame(width: 42, height: 28)
              .foregroundColor(showNotifications ? .green : .gray.opacity(0.8))

            Circle()
              .foregroundColor(Color.white)
              .padding(2)
              .frame(width: 28, height: 28)
              .matchedGeometryEffect(id: "toggle", in: animation)
          }
          .onTapGesture {
            if showNotifications {
              withAnimation(.easeInOut(duration: 0.2)) {
                center.removeAllPendingNotificationRequests()
                showNotifications.toggle()
              }
            } else {
              center.getNotificationSettings { settings in
                if settings.authorizationStatus == .notDetermined {
                  center.requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
                    if success {
                      withAnimation(.easeInOut(duration: 0.2)) {
                        showNotifications.toggle()
                        newNotification()
                      }
                    } else if let error = error {
                      print(error.localizedDescription)
                      notificationsEnabled = false
                    }
                  }
                } else if settings.authorizationStatus == .denied {
                  notificationsEnabled = false

                  DispatchQueue.main.async {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                      UIApplication.shared.open(settingsURL)
                    }
                  }

                } else {
                  withAnimation(.easeInOut(duration: 0.2)) {
                    showNotifications.toggle()
                    if showNotifications {
                      newNotification()
                    }
                  }
                }
              }
            }
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
      }
      .padding(.horizontal, 15)
      .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
      .padding(.bottom, 20)

      if showNotifications {
        VStack(spacing: 0) {
          HStack {
            Text("Every morning (8:00 AM)")
              .font(.system(.body, design: .rounded))
              .foregroundColor(Color.PrimaryText)

            Spacer()

            if option == 1 {
              Image(systemName: "checkmark")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.DarkIcon.opacity(0.6))
                .matchedGeometryEffect(id: "tick", in: animation)
            }
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
          .onTapGesture {
            withAnimation(.easeIn(duration: 0.15)) {
              option = 1
            }
          }
          .padding(.vertical, 9)
          .overlay(alignment: .bottom) {
            Divider()
          }

          HStack {
            Text("Every evening (8:00 PM)")
              .font(.system(.body, design: .rounded))
              .foregroundColor(Color.PrimaryText)

            Spacer()

            if option == 2 {
              Image(systemName: "checkmark")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.DarkIcon.opacity(0.6))
                .matchedGeometryEffect(id: "tick", in: animation)
            }
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
          .onTapGesture {
            withAnimation(.easeIn(duration: 0.15)) {
              option = 2
            }
          }
          .padding(.vertical, 9)
          .overlay(alignment: .bottom) {
            Divider()
          }
            
          NavigationLink(destination: SettingsNotificationCustomTimeView(customTimerList: $customTimerList, onDismiss: onDismiss)) {
                
              HStack {
                Text("Custom Time")
                  .font(.system(.body, design: .rounded))
                  .foregroundColor(Color.PrimaryText)

                Spacer()

                  if option == 3 {
                      Image(systemName: "checkmark")
                          .font(.system(.subheadline, design: .rounded))
                          .foregroundColor(.DarkIcon.opacity(0.6))
                          .matchedGeometryEffect(id: "tick", in: animation)
                  }
                  
                  Image(systemName: "chevron.forward")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.DarkIcon.opacity(0.6))

              }
              .frame(maxWidth: .infinity)
              .contentShape(Rectangle())
              .padding(.vertical, 9)
            }

        }
        .padding(.horizontal, 15)
        .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
        .onChange(of: option) { newValue in
          UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.set(
            option, forKey: "notificationOption")

            newNotification()
        }
        .onChange(of: customTimerList) { _ in
          UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.saveCustomTimerList(customTimerList)
          newNotification()
        }
        .onAppear {
          if UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.object(
            forKey: "notificationOption") != nil {
            option = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(
              forKey: "notificationOption")
          }

          self.customTimerList = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.loadCustomTimerList()
        }
      }
    }
    .modifier(SettingsSubviewModifier())
  }
    
    private func onDismiss(){
        self.option = 3
    }
}

func newNotification() {
  UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

  let content = UNMutableNotificationContent()
  content.title = String(localized: "Keep the streak going!")
  content.subtitle = String(localized: "Remember to input your expenses today.")
  content.sound = UNNotificationSound.default

  // show this notification five seconds from now
  var dateComponentsList : [DateComponents] = []
  var option = 1

  if UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.object(forKey: "notificationOption")
    != nil {
    option = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(
      forKey: "notificationOption")
  }

  if option == 1 {
      var dateComponents = DateComponents()
      dateComponents.hour = 8
      dateComponents.minute = 0
      dateComponentsList.append(dateComponents)
  } else if option == 2 {
      var dateComponents = DateComponents()
      dateComponents.hour = 20
      dateComponents.minute = 0
      dateComponentsList.append(dateComponents)
  } else {
      let customTimes = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.loadCustomTimerList()
      if !customTimes.isEmpty {
          for item in customTimes {
              let dateComponents = Calendar.current.dateComponents([.hour, .minute], from: item)
              dateComponentsList.append(dateComponents)
          }
      } else {
          var dateComponent = DateComponents()
           dateComponent.hour = 8
           dateComponent.minute = 0
           dateComponentsList.append(dateComponent)
      }
  }

    for components in dateComponentsList {
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        // choose a random identifier
        let request = UNNotificationRequest(
          identifier: UUID().uuidString, content: content, trigger: trigger)
        // add our notification request
        UNUserNotificationCenter.current().add(request)
    }


}
