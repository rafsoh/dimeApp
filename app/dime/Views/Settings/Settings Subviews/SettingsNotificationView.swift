//
//  SettingsNotificationView.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import CoreData
import Foundation
import SwiftUI
import UserNotifications

struct SettingsNotificationsView: View {
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

  @AppStorage("showNotifications", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var showNotifications: Bool = false
  @AppStorage("notificationsEnabled", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var notificationsEnabled: Bool = true
  @AppStorage(NotificationScheduler.dailyReminderKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var dailyReminder: Bool = NotificationScheduler.dailyReminderDefault
  @AppStorage(NotificationScheduler.upcomingChargesKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var upcomingCharges: Bool = NotificationScheduler.upcomingChargesDefault
  @AppStorage(NotificationScheduler.upcomingChargesLeadDaysKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var leadDays: Int = NotificationScheduler.upcomingChargesLeadDaysDefault

  @State var option = 1
  @State var customTime = Date.now

  var center = UNUserNotificationCenter.current()

  @Namespace var animation

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        Toggle(isOn: Binding(get: { showNotifications }, set: { _ in toggleNotifications() })) {
          Text("Enable Notifications")
            .font(.app(.body))
            .foregroundColor(Color.PrimaryText)
        }
        .tint(.green)
        .frame(minHeight: .settingsRowHeight)
      }
      .settingsSectionRows()

      if showNotifications {
        remindersSection

        if dailyReminder || upcomingCharges {
          timeSection
        }

        if upcomingCharges {
          upcomingChargesSection
        }
      }
    }
    .modifier(SettingsSubviewModifier(title: "Notifications"))
    .onChange(of: dailyReminder) { _ in
      NotificationScheduler.shared.reschedule()
    }
    .onChange(of: upcomingCharges) { _ in
      NotificationScheduler.shared.reschedule()
    }
    .onChange(of: leadDays) { _ in
      NotificationScheduler.shared.reschedule()
    }
  }

  // MARK: Sections

  private var remindersSection: some View {
    VStack(spacing: 0) {
      SettingsSectionHeader("Reminders")

      VStack(spacing: 0) {
        NotificationToggleRow(
          title: "Daily Check-in",
          subtitle: "A nudge to log the day's spending",
          isOn: $dailyReminder.animation(.easeInOut(duration: 0.2))
        )

        Divider()

        NotificationToggleRow(
          title: "Upcoming Charges",
          subtitle: "A heads-up before a recurring expense is logged",
          isOn: $upcomingCharges.animation(.easeInOut(duration: 0.2))
        )
      }
      .settingsSectionRows()
    }
    .padding(.top, .settingsHeaderSpacing)
  }

  private var timeSection: some View {
    VStack(spacing: 0) {
      SettingsSectionHeader("Time")

      VStack(spacing: 0) {
        timeRow(1, title: "Every morning (8:00 AM)")

        Divider()

        timeRow(2, title: "Every evening (8:00 PM)")

        Divider()

        HStack {
          Text("Custom Time")
            .font(.app(.body))
            .foregroundColor(Color.PrimaryText)

          Spacer()

          if option == 3 {
            DatePicker(
              "Custom notification time", selection: $customTime,
              displayedComponents: .hourAndMinute
            )
            .labelsHidden()

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
            option = 3
          }
        }
      }
      .settingsSectionRows()
      .onChange(of: option) { newValue in
        UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.set(
          option, forKey: "notificationOption")

        if newValue == 3 {
          storeCustomTime()
        }

        NotificationScheduler.shared.reschedule()
      }
      .onChange(of: customTime) { _ in
        storeCustomTime()
        NotificationScheduler.shared.reschedule()
      }
      .onAppear(perform: loadTime)

      SettingsSectionFooter(timeFooter)
    }
    .padding(.top, .settingsHeaderSpacing)
  }

  private var upcomingChargesSection: some View {
    VStack(spacing: 0) {
      SettingsSectionHeader("Upcoming Charges")

      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Text("Remind Me")
            .font(.app(.body))
            .foregroundColor(Color.PrimaryText)
            .lineLimit(1)

          Spacer(minLength: 4)

          LeadDaysStepper(days: $leadDays)
        }
        .frame(maxWidth: .infinity, minHeight: .settingsRowHeight)
      }
      .settingsSectionRows()

      SettingsSectionFooter("Covers recurring expenses. Reminders are planned a couple of months ahead and refresh whenever you open Dime.")
    }
    .padding(.top, .settingsHeaderSpacing)
  }

  private func timeRow(_ value: Int, title: LocalizedStringKey) -> some View {
    HStack {
      Text(title)
        .font(.app(.body))
        .foregroundColor(Color.PrimaryText)

      Spacer()

      if option == value {
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
        option = value
      }
    }
  }

  private var timeFooter: LocalizedStringKey {
    if dailyReminder && upcomingCharges {
      return "Check-ins and charge reminders both arrive at this time."
    } else if dailyReminder {
      return "Your check-in arrives at this time every day."
    } else {
      return "Charge reminders arrive at this time."
    }
  }

  // MARK: Actions

  private func storeCustomTime() {
    let components = Calendar.current.dateComponents([.hour, .minute], from: customTime)
    let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!
    defaults.set(components.hour!, forKey: "customHour")
    defaults.set(components.minute!, forKey: "customMinute")
  }

  private func loadTime() {
    let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!

    if defaults.object(forKey: "notificationOption") != nil {
      option = defaults.integer(forKey: "notificationOption")
    }

    if defaults.object(forKey: "customHour") != nil, defaults.object(forKey: "customMinute") != nil {
      var components = DateComponents()
      components.hour = defaults.integer(forKey: "customHour")
      components.minute = defaults.integer(forKey: "customMinute")
      customTime = Calendar.current.date(from: components)!
    }
  }

  func toggleNotifications() {
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
                NotificationScheduler.shared.reschedule()
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
              NotificationScheduler.shared.reschedule()
            }
          }
        }
      }
    }
  }
}

private struct NotificationToggleRow: View {
  let title: LocalizedStringKey
  let subtitle: LocalizedStringKey
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.app(.body))
          .foregroundColor(Color.PrimaryText)

        Text(subtitle)
          .font(.app(.footnote, weight: .medium))
          .foregroundColor(Color.SubtitleText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .tint(.green)
    .padding(.vertical, 10)
    .frame(minHeight: .settingsRowHeight)
  }
}

/// A compact − value + control for how many days ahead an upcoming charge is announced.
private struct LeadDaysStepper: View {
  @Binding var days: Int

  var body: some View {
    HStack(spacing: 0) {
      stepButton("minus", label: "Fewer days", enabled: days > NotificationScheduler.leadDaysRange.lowerBound) {
        days -= 1
      }

      Text(label)
        .font(.app(.subheadline, weight: .semibold))
        .foregroundColor(Color.PrimaryText)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(minWidth: 96)
        .animation(nil, value: days)

      stepButton("plus", label: "More days", enabled: days < NotificationScheduler.leadDaysRange.upperBound) {
        days += 1
      }
    }
    .padding(.horizontal, 2)
    .frame(height: 36)
    .background(Color.SecondaryBackground, in: Capsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Remind Me"))
    .accessibilityValue(Text(label))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        days = min(days + 1, NotificationScheduler.leadDaysRange.upperBound)
      case .decrement:
        days = max(days - 1, NotificationScheduler.leadDaysRange.lowerBound)
      @unknown default:
        break
      }
    }
  }

  private var label: LocalizedStringKey {
    switch days {
    case 0:
      return "On the day"
    case 1:
      return "1 day before"
    default:
      return "\(days) days before"
    }
  }

  private func stepButton(_ systemName: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button {
      action()
      UISelectionFeedbackGenerator().selectionChanged()
    } label: {
      Image(systemName: systemName)
        .font(.app(.footnote, weight: .bold))
        .foregroundColor(Color.PrimaryText)
        .frame(width: 34, height: 34)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.3)
    .accessibilityLabel(label)
  }
}

// MARK: - Scheduling

/// Owns every local notification Dime sends: the daily check-in and reminders for upcoming recurring expenses.
/// Each reschedule clears all pending requests and adds them again from the current settings and data.
final class NotificationScheduler {
  static let shared = NotificationScheduler()

  static let dailyReminderKey = "dailyReminderEnabled"
  static let dailyReminderDefault = true
  static let upcomingChargesKey = "upcomingChargeRemindersEnabled"
  static let upcomingChargesDefault = true
  static let upcomingChargesLeadDaysKey = "upcomingChargeLeadDays"
  static let upcomingChargesLeadDaysDefault = 1
  static let leadDaysRange = 0 ... 7

  private static let dailyIdentifier = "daily-check-in"
  private static let upcomingPrefix = "upcoming-charge-"
  /// iOS keeps at most 64 pending requests per app; one is the daily check-in.
  private static let upcomingLimit = 60
  /// How far ahead charges are looked up. Anything later is picked up on a later reschedule.
  private static let lookaheadDays = 62

  private let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!
  private let center = UNUserNotificationCenter.current()
  private var pendingReschedule: DispatchWorkItem?
  private var observer: NSObjectProtocol?

  private init() {
    // Adding, editing, deleting or syncing a recurring expense changes which reminders are due.
    observer = NotificationCenter.default.addObserver(
      forName: .NSManagedObjectContextObjectsDidChange,
      object: DataController.shared.container.viewContext,
      queue: .main
    ) { [weak self] note in
      guard Self.touchesTransactions(note) else { return }
      self?.scheduleDebouncedReschedule()
    }
  }

  /// Rebuilds every pending notification. Safe to call from any thread.
  func reschedule() {
    DispatchQueue.main.async { [self] in
      pendingReschedule?.cancel()
      pendingReschedule = nil
      rescheduleNow()
    }
  }

  private func scheduleDebouncedReschedule() {
    pendingReschedule?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.rescheduleNow() }
    pendingReschedule = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
  }

  private func rescheduleNow() {
    center.removeAllPendingNotificationRequests()

    guard defaults.bool(forKey: "showNotifications") else {
      return
    }

    let time = deliveryTime()

    if bool(Self.dailyReminderKey, default: Self.dailyReminderDefault) {
      addDailyReminder(at: time)
    }

    if bool(Self.upcomingChargesKey, default: Self.upcomingChargesDefault) {
      addUpcomingChargeReminders(at: time)
    }
  }

  // MARK: Daily check-in

  private func addDailyReminder(at time: DateComponents) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Keep the streak going!")
    content.subtitle = String(localized: "Remember to input your expenses today.")
    content.sound = .default
    content.threadIdentifier = Self.dailyIdentifier

    let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
    center.add(UNNotificationRequest(identifier: Self.dailyIdentifier, content: content, trigger: trigger))
  }

  // MARK: Upcoming charges

  private struct UpcomingCharge {
    let transaction: Transaction
    let chargeDay: Date
    let fireDate: Date
  }

  private func addUpcomingChargeReminders(at time: DateComponents) {
    let leadDays = min(max(integer(Self.upcomingChargesLeadDaysKey, default: Self.upcomingChargesLeadDaysDefault), Self.leadDaysRange.lowerBound), Self.leadDaysRange.upperBound)

    let calendar = Calendar.current
    let now = Date.now
    let startOfToday = calendar.startOfDay(for: now)

    guard let horizon = calendar.date(byAdding: .day, value: Self.lookaheadDays + leadDays, to: startOfToday) else {
      return
    }

    let dataController = DataController.shared
    var seen = Set<UUID>()
    var charges: [UpcomingCharge] = []

    for transaction in dataController.results(for: dataController.fetchRequestForRecurringTransactions()) {
      guard !transaction.income, (1 ... 3).contains(transaction.recurringType) else { continue }

      // Sync can leave duplicate copies of a recurring transaction under the same id; only the first counts.
      if let id = transaction.id, !seen.insert(id).inserted { continue }

      // Same rule the Log and Insights use for when a recurring transaction next lands.
      var day = calendar.startOfDay(for: transaction.wrappedDate > now ? transaction.wrappedDate : transaction.nextTransactionDate)

      while day < horizon {
        if let fireDate = fireDate(for: day, leadDays: leadDays, time: time, calendar: calendar), fireDate > now {
          charges.append(UpcomingCharge(transaction: transaction, chargeDay: day, fireDate: fireDate))
        }

        guard let next = transaction.recurrenceDate(after: day), next > day else { break }
        day = calendar.startOfDay(for: next)
      }
    }

    charges.sort { $0.fireDate < $1.fireDate }

    for charge in charges.prefix(Self.upcomingLimit) {
      add(charge, leadDays: leadDays, calendar: calendar)
    }
  }

  private func fireDate(for chargeDay: Date, leadDays: Int, time: DateComponents, calendar: Calendar) -> Date? {
    guard let reminderDay = calendar.date(byAdding: .day, value: -leadDays, to: chargeDay) else {
      return nil
    }

    return calendar.date(bySettingHour: time.hour ?? 8, minute: time.minute ?? 0, second: 0, of: reminderDay)
  }

  private func add(_ charge: UpcomingCharge, leadDays: Int, calendar: Calendar) {
    let transaction = charge.transaction
    let name = transaction.displayTitle
    let currencyCode = transaction.currencyCode ?? CurrencyConverter.current().mainCurrency
    let showCents = defaults.object(forKey: "showCents") == nil ? true : defaults.bool(forKey: "showCents")
    let amount = MoneyFormatter.string(transaction.amount, currencyCode: currencyCode, showCents: showCents)

    let content = UNMutableNotificationContent()
    content.sound = .default
    content.threadIdentifier = "upcoming-charges"

    switch leadDays {
    case 0:
      content.title = String(localized: "Due today: \(name)")
      content.body = String(localized: "\(amount) will be added to your log today.")
    case 1:
      content.title = String(localized: "Due tomorrow: \(name)")
      content.body = String(localized: "\(amount) will be added to your log tomorrow.")
    default:
      let dateString = charge.chargeDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
      content.title = String(localized: "Due in \(leadDays) days: \(name)")
      content.body = String(localized: "\(amount) will be added to your log on \(dateString).")
    }

    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: charge.fireDate)
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

    let dayKey = calendar.dateComponents([.year, .month, .day], from: charge.chargeDay)
    let identifier = Self.upcomingPrefix
      + (transaction.id?.uuidString ?? transaction.objectID.uriRepresentation().absoluteString)
      + "-\(dayKey.year ?? 0)-\(dayKey.month ?? 0)-\(dayKey.day ?? 0)"

    center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
  }

  // MARK: Helpers

  /// The hour and minute picked on the Notifications page: 8:00 AM, 8:00 PM or a custom time.
  private func deliveryTime() -> DateComponents {
    var components = DateComponents()

    switch integer("notificationOption", default: 1) {
    case 2:
      components.hour = 20
      components.minute = 0
    case 3 where defaults.object(forKey: "customHour") != nil && defaults.object(forKey: "customMinute") != nil:
      components.hour = defaults.integer(forKey: "customHour")
      components.minute = defaults.integer(forKey: "customMinute")
    default:
      components.hour = 8
      components.minute = 0
    }

    return components
  }

  private func bool(_ key: String, default value: Bool) -> Bool {
    defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
  }

  private func integer(_ key: String, default value: Int) -> Int {
    defaults.object(forKey: key) == nil ? value : defaults.integer(forKey: key)
  }

  private static func touchesTransactions(_ note: Notification) -> Bool {
    let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]

    return keys.contains { key in
      guard let objects = note.userInfo?[key] as? Set<NSManagedObject> else { return false }
      return objects.contains { $0 is Transaction }
    }
  }
}
