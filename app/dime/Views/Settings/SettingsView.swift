//
//  SettingsView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import Combine
import ConfettiSwiftUI
import Foundation
import StoreKit
import SwiftUI
import UserNotifications
import WidgetKit

struct SettingsView: View {
  @Environment(\.dynamicTypeSize) var dynamicTypeSize

  @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var colourScheme: Int = 0
  var colourSchemeString: String {
    if colourScheme == 1 {
      return String(localized: "Light")
    } else if colourScheme == 2 {
      return String(localized: "Dark")
    } else {
      return String(localized: "System")
    }
  }

  @AppStorage("activeIcon", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var activeIcon: String = "AppIcon"
  var appIconString: String {
    if activeIcon == "AppIcon1" {
      return "v2.0"
    } else if activeIcon == "AppIcon2" {
      return "Unicorn"
    } else if activeIcon == "AppIcon3" {
      return "v1.5"
    } else {
      return "O.G."
    }
  }

  @AppStorage("firstWeekday", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var firstWeekday: Int = 1
  var firstWeekdayString: String {
    dimeWeekdaySymbol(firstWeekday)
  }

  @AppStorage("showNotifications", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var showNotifications: Bool = false
  @AppStorage("notificationOption", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var option: Int = 1
  var notificationString: String {
    if showNotifications {
      if option == 1 {
        return String(localized: "Mornings")
      } else if option == 2 {
        return String(localized: "Evenings")
      } else {
        return String(localized: "Custom")
      }
    } else {
      return String(localized: "Off")
    }
  }

  @EnvironmentObject var appLockVM: AppLockViewModel
  @Namespace var animation

  @AppStorage(DataController.iCloudSyncEnabledKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var iCloudSync: Bool = true
  @ObservedObject private var syncStatus = DataController.shared.syncStatus

  var iCloudString: String {
    if !iCloudSync {
      return String(localized: "Off")
    } else if case .problem = syncStatus.summary {
      return String(localized: "Not Syncing")
    } else {
      return String(localized: "On")
    }
  }

  @Environment(\.openURL) var openURL
  let supportEmail = SupportEmail(toAddress: "rafasohhh@gmail.com", subject: "Support Email")
  let featureRequestEmail = SupportEmail(
    toAddress: "rafasohhh@gmail.com", subject: "Feature Request")

  @AppStorage("numberEntryType", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var numberEntryType: Int = 2

  var numberEntryString: String {
    if numberEntryType == 1 {
      return String(localized: "Type 1")
    } else {
      return String(localized: "Type 2")
    }
  }

  @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var showCents: Bool = true

  @AppStorage("animated", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var animated:
    Bool = true

  @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency:
    String = Locale.current.currencyCode!

  @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var incomeTracking: Bool = true
    
  @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var showExpenseOrIncomeSign: Bool = true

  @AppStorage(
    "showUpcomingTransactions", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  var showUpcoming: Bool = true

  var upcomingString: String {
    if showUpcoming {
      return String(localized: "Shown")
    } else {
      return String(localized: "Hidden")
    }
  }

    @AppStorage("haptics", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var hapticType: Int = 1

    var hapticString: String {
      if hapticType == 0 {
        return String(localized: "None")
      } else if hapticType == 1 {
        return String(localized: "Subtle")
      } else {
        return String(localized: "Excessive")
      }
    }

  // popups

  @State var showTipJarMenu = false
  @State var showImportGuide = false
  @State var showUpdate: Bool = false
  @State var showExportSheet = false
  @State var exportFile: URL?

  @EnvironmentObject var tabBarManager: TabBarManager

  var body: some View {
    if #available(iOS 16.0, *) {
      NavigationStack { root }
    } else {
      NavigationView { root }
    }
  }

  private var root: some View {
    VStack {
      ScrollView(showsIndicators: false) {
        VStack(spacing: 0) {
          VStack(spacing: 0) {
            SettingsSectionHeader("General")

            VStack(spacing: 0) {

              NavigationLink(destination: SettingsNotificationsView()) {
                SettingsRowView(
                  systemImage: "bell.fill", title: "Notifications", colour: 102,
                  optionalText: notificationString)
              }

              NavigationLink(destination: SettingsCurrencyView()) {
                SettingsRowView(
                  systemImage: "coloncurrencysign.square.fill", title: "Currency", colour: 103,
                  optionalText: currency)
              }

              NavigationLink(
                destination: SettingsNumberEntryView()
                  .onAppear {
                    withAnimation(.easeOut.speed(1.5)) {
                      tabBarManager.navigationHideTab()
                    }
                  }
                  .onDisappear {
                    withAnimation(.easeOut.speed(1.5)) {
                      tabBarManager.navigationShowTab()
                    }
                  }
              ) {
                SettingsRowView(
                  systemImage: "keyboard.fill", title: "Number Entry", colour: 104,
                  optionalText: numberEntryString)
              }

              ToggleRow(
                icon: "faceid", color: "105", text: "Authentication",
                bool: appLockVM.isAppLockEnabled,
                onTap: {
                  appLockVM.appLockStateChange(appLockState: !appLockVM.isAppLockEnabled)
                })

              ToggleRow(
                icon: "banknote.fill", color: "106", text: "Income Tracking", bool: incomeTracking,
                onTap: {
                  incomeTracking.toggle()

                  if !incomeTracking {
                    UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.set(
                      false, forKey: "insightsViewIncomeFiltering")
                    UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.set(
                      3, forKey: "logInsightsType")
                  }
                })

              NavigationLink(destination: SettingsWeekStartView()) {
                SettingsRowView(systemImage: "calendar", title: "Time Frames", colour: 109)
              }
              
            }
            .settingsSectionRows()
          }
          .padding(.horizontal, .settingsPageInset)
          .padding(.top, 6)
          .padding(.bottom, .settingsHeaderSpacing)
          .onChange(of: currency) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }
          .onChange(of: firstWeekday) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }
          .onChange(of: showCents) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }

          VStack(spacing: 0) {
            SettingsSectionHeader("Appearance")

            VStack(spacing: 0) {
              NavigationLink(destination: SettingsAppearanceView()) {
                SettingsRowView(
                  systemImage: "circle.righthalf.filled", title: "Theme", colour: 100,
                  optionalText: colourSchemeString)
              }

              NavigationLink(destination: SettingsAppIconView()) {
                SettingsRowView(
                  systemImage: "app.badge.fill", title: "App Icon", colour: 101,
                  optionalText: appIconString)
              }

              ToggleRow(
                icon: "centsign.circle.fill", color: "107", text: "Display Cents", bool: showCents,
                onTap: {
                  showCents.toggle()
                })

              NavigationLink(destination: SettingsUpcomingView()) {
                SettingsRowView(
                  systemImage: "sun.min.fill", title: "Upcoming Logs", colour: 108,
                  optionalText: upcomingString)
              }
              
              ToggleRow(
                icon: "plusminus", color: "123", text: "Display +/- Symbol", bool: showExpenseOrIncomeSign,
                onTap: {
                    showExpenseOrIncomeSign.toggle()
                })

              ToggleRow(
                icon: "hare.fill", color: "121", text: "Animated Charts", bool: animated, smaller: true,
                onTap: {
                  animated.toggle()
                })

            }
            .settingsSectionRows()
          }
          .padding(.horizontal, .settingsPageInset)
          .padding(.bottom, .settingsHeaderSpacing)
          .onChange(of: currency) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }
          .onChange(of: firstWeekday) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }
          .onChange(of: showCents) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }

          VStack(spacing: 0) {
            SettingsSectionHeader("Data")

            VStack(spacing: 0) {
              NavigationLink(
                destination: SettingsCategoryView()
                  .onAppear {
                    withAnimation(.easeOut.speed(1.5)) {
                      tabBarManager.navigationHideTab()
                    }
                  }
                  .onDisappear {
                    withAnimation(.easeOut.speed(1.5)) {
                      tabBarManager.navigationShowTab()
                    }
                  }

              ) {
                SettingsRowView(
                  systemImage: "rectangle.grid.2x2.fill", title: "Categories", colour: 110)
              }

              NavigationLink(destination: SettingsCloudView()) {
                SettingsRowView(
                  systemImage: "icloud.fill", title: "iCloud Sync", colour: 111,
                  optionalText: iCloudString)
              }

              NavigationLink(destination: SettingsBackupsView()) {
                SettingsRowView(
                  systemImage: "clock.arrow.circlepath", title: "Backups", colour: 106)
              }

              //
              //                            NavigationLink(destination: SettingsQuickAddWidgetView()) {
              //                                SettingsRowView(systemImage: "bolt.square.fill", title: "Quick-Add Widget", colour: 115)
              //                            }

              Button {
                showImportGuide = true
              } label: {
                SettingsRowView(
                  systemImage: "square.and.arrow.down.fill", title: "Import Data", colour: 112)
              }

              Button {
                showExportSheet = true
              } label: {
                SettingsRowView(
                  systemImage: "square.and.arrow.up.fill", title: "Export Data", colour: 113)
              }

              NavigationLink(destination: SettingsEraseView()) {
                SettingsRowView(systemImage: "xmark.bin.fill", title: "Erase Data", colour: 114)
              }
            }
            .settingsSectionRows()
          }
          .padding(.horizontal, .settingsPageInset)
          .padding(.bottom, .settingsHeaderSpacing)

          VStack(spacing: 0) {
            SettingsSectionHeader("Others")

            VStack(spacing: 0) {

                NavigationLink(destination: SettingsHapticsView()) {
                  SettingsRowView(
                    systemImage: "hand.tap.fill", title: "Haptics", colour: 100,
                    optionalText: hapticString)
                }

              NavigationLink(destination: SettingsGoofyView()) {
                SettingsRowView(systemImage: "flame.fill", title: "Feature Lab", colour: 122)
              }

              Button {
                showTipJarMenu = true
              } label: {
                SettingsRowView(systemImage: "heart.fill", title: "Tip Jar", colour: 123)
              }

              Button {
                supportEmail.send(openURL: openURL)
              } label: {
                SettingsRowView(systemImage: "ladybug.fill", title: "Report Bug", colour: 124)
              }

              Button {
                featureRequestEmail.send(openURL: openURL)
              } label: {
                SettingsRowView(
                  systemImage: "hand.wave.fill", title: "Feature Request", colour: 125)
              }

              Button {
                let url = "https://apps.apple.com/app/id1635280255?action=write-review"
                guard let writeReviewURL = URL(string: url)
                else { fatalError("Expected a valid URL") }
                UIApplication.shared.open(writeReviewURL, options: [:], completionHandler: nil)
              } label: {
                SettingsRowView(systemImage: "star.fill", title: "Rate on App Store", colour: 126)
              }

              Button {
                shareSheet(url: "https://apps.apple.com/app/id1635280255")
              } label: {
                SettingsRowView(systemImage: "shareplay", title: "Share with Friends", colour: 127)
              }

              Button {
                if let url = URL(string: "https://www.x.com/budgetwithdime") {
                  UIApplication.shared.open(url)
                }
              } label: {
                SettingsRowView(systemImage: "bird.fill", title: "Follow Dime on X", colour: 128)
                  .frame(maxWidth: .infinity)
              }

              Button {
                if let url = URL(string: "https://www.x.com/rafsoh") {
                  UIApplication.shared.open(url)
                }
              } label: {
                SettingsRowView(
                  systemImage: "camera.fill", title: "Follow Rafael on X", colour: 129)
              }
            }
            .settingsSectionRows()
          }
          .padding(.horizontal, .settingsPageInset)
          .padding(.bottom, 15)

          VStack(spacing: 5) {
            HStack(spacing: 3) {
              Text("Version \(UIApplication.appVersion ?? "") (\(UIApplication.buildNumber ?? ""))")
                .font(.system(.footnote, design: .rounded).weight(.medium))

                //                                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color.SubtitleText)

              Text("·")
                .font(.system(.footnote, design: .rounded).weight(.medium))

                .foregroundColor(Color.SubtitleText)

              Button {
                showUpdate = true
              } label: {
                Text("What's New")
                  .font(.system(.footnote, design: .rounded).weight(.medium))
                  .foregroundColor(Color.PrimaryText)
              }
              .buttonStyle(.plain)
            }

            Text("Made with ❤️ by \(makeAttributedString()) from 🇸🇬")
              .font(.system(.footnote, design: .rounded).weight(.medium))

              .foregroundColor(Color.SubtitleText)
              .multilineTextAlignment(.center)
          }
          .padding(.horizontal, .settingsPageInset)
        }
      }
      .tabBarClearance()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .tabHeader {
        TabHeader("Settings")
      }
      .sheet(isPresented: $showExportSheet, onDismiss: shareExportIfNeeded) {
        ExportPeriodSheet { url in
          exportFile = url
        }
      }
    }
    .settingsNavigationBar(hidden: true)
    .background(Color.PrimaryBackground)
    .sheet(isPresented: $showTipJarMenu) {
      TipJarSheet()
    }
    .sheet(isPresented: $showUpdate) {
      WhatsNewSheet()
    }
    .sheet(isPresented: $showImportGuide) {
      ImportDataView()
    }
  }

  func shareExportIfNeeded() {
    guard let exportFile else { return }
    self.exportFile = nil
    shareSheet(url: exportFile)
  }

  @ViewBuilder
    func ToggleRow(icon: String, color: String, text: String, bool: Bool, smaller: Bool = false, onTap: @escaping () -> Void)
    -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
            .font(.system(smaller ? .subheadline : .body, design: .rounded))
        .foregroundColor(.white)
        .frame(
          width: dynamicTypeSize > .xLarge ? 40 : 30, height: dynamicTypeSize > .xLarge ? 40 : 30,
          alignment: .center
        )
        .background(Color(color), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

      Toggle(isOn: Binding(get: { bool }, set: { _ in withAnimation { onTap() } })) {
        Text(LocalizedStringKey(text))
          .font(.system(.body, design: .rounded).weight(.medium))
          .lineLimit(1)
          .foregroundColor(Color.PrimaryText)
      }
      .tint(.green)
    }
    .frame(maxWidth: .infinity, minHeight: .settingsRowHeight)
  }

  func makeAttributedString() -> AttributedString {
    var string = AttributedString("Rafael")
    string.foregroundColor = Color.PrimaryText
    string.link = URL(string: "https://www.x.com/rafsoh")

    return string
  }

  func shareSheet(url: String) {
    guard let url = URL(string: url) else { return }
    shareSheet(url: url)
  }

  func shareSheet(url: URL) {
    let activityView = UIActivityViewController(activityItems: [url], applicationActivities: nil)

    let allScenes = UIApplication.shared.connectedScenes
    let scene = allScenes.first { $0.activationState == .foregroundActive }

    if let windowScene = scene as? UIWindowScene {
      windowScene.keyWindow?.rootViewController?.present(
        activityView, animated: true, completion: nil)
    }
  }

}

struct TipJarSheet: View {
  @Environment(\.dismiss) var dismiss
  @EnvironmentObject var unlockManager: UnlockManager

  @State private var contentHeight: CGFloat = 0
  @State private var confetti = 0

  var body: some View {
    if #available(iOS 16.0, *) {
      content
        .presentationDetents(detents)
        .presentationDragIndicator(.hidden)
    } else {
      content
    }
  }

  @available(iOS 16.0, *)
  var detents: Set<PresentationDetent> {
    if contentHeight == 0 {
      return [.height(420)]
    } else if contentHeight > UIScreen.main.bounds.height * 0.9 {
      return [.large]
    } else {
      return [.height(contentHeight)]
    }
  }

  var bottomCaption: Text {
    if unlockManager.failedTransaction {
      return Text("Tip failed to go through, please try again!")
    } else if unlockManager.purchaseCount > 0 {
      return Text("Thanks a million, \(Image(systemName: "heart.fill")) Rafael")
    } else {
      return Text("Have a great day ahead!")
    }
  }

  var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
          dismiss()
        }

        Spacer()
      }
      .frame(height: 44)
      .overlay {
        CategoryEditorTitle(title: "Tip Jar")
      }

      Text(
        "Hey! Dime was built by a solo student developer, and is intended to be completely free-of-charge, with no paywalls or ads. If you enjoy using Dime and want to support development, please consider a small tip."
      )
      .font(.system(.body, design: .rounded).weight(.medium))
      .foregroundColor(Color.SubtitleText)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, 20)
      .padding(.horizontal, 4)

      Group {
        switch unlockManager.requestState {
        case .loading:
          ProgressView()
            .frame(maxWidth: .infinity)
            .frame(height: 170)
        case .failed:
          Text("Unable to load tip options, please try again later 🥲")
            .font(.system(.body, design: .rounded).weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundColor(Color.SubtitleText)
            .frame(maxWidth: .infinity)
            .frame(height: 170)
        case .loaded:
          VStack(spacing: 10) {
            ForEach(sortedProducts, id: \.self) { product in
              TipOptionButton(product: product)
            }

            bottomCaption
              .font(.system(.subheadline, design: .rounded).weight(.medium))
              .foregroundColor(Color.SubtitleText)
              .frame(maxWidth: .infinity)
              .padding(.top, 10)
              .animation(.easeInOut, value: unlockManager.failedTransaction)
          }
        }
      }
      .padding(.top, 24)
    }
    .padding(.horizontal, 20)
    .padding(.top, 20)
    .padding(.bottom, 16)
    .fixedSize(horizontal: false, vertical: true)
    .background {
      GeometryReader { proxy in
        Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
      }
    }
    .onPreferenceChange(SheetContentHeightKey.self) { height in
      contentHeight = height
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .sheetBackground()
    .confettiCannon(
      counter: $confetti, num: 50, openingAngle: Angle(degrees: 0),
      closingAngle: Angle(degrees: 360), radius: 200
    )
    .onAppear {
      unlockManager.loadProductsIfNeeded()
    }
    .onChange(of: unlockManager.purchaseCount) { _ in
      confetti += 1
    }
  }

  var sortedProducts: [SKProduct] {
    unlockManager.loadedProducts.sorted {
      $0.price.doubleValue < $1.price.doubleValue
    }
  }
}

private struct TipOptionButton: View {
  @EnvironmentObject var unlockManager: UnlockManager
  let product: SKProduct

  var body: some View {
    Button {
      unlockManager.buy(product: product)
    } label: {
      HStack(spacing: 12) {
        Text(title)
          .foregroundColor(Color.PrimaryText)
          .lineLimit(1)
          .minimumScaleFactor(0.8)

        Spacer(minLength: 12)

        Text(product.localizedPrice)
          .monospacedDigit()
          .foregroundColor(Color.LightIcon)
          .padding(.horizontal, 14)
          .frame(height: 36)
          .background(Color.DarkBackground, in: Capsule())
      }
      .font(.system(.body, design: .rounded).weight(.semibold))
      .padding(.leading, 18)
      .padding(.trailing, 7)
      .frame(height: 50)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .glassBackground(in: Capsule(), tint: Color.glassTint)
    .accessibilityLabel(Text("\(title), \(product.localizedPrice)"))
  }

  var title: String {
    switch product.productIdentifier {
    case "com.rafaelsoh.dime.smalltip":
      return String(localized: "☕ Coffee-Sized Tip")
    case "com.rafaelsoh.dime.mediumtip":
      return String(localized: "🌮 Taco-Sized Tip")
    case "com.rafaelsoh.dime.largetip":
      return String(localized: "🍕 Pizza-Sized Tip")
    default:
      return product.localizedTitle
    }
  }
}

struct SettingsRowView: View {
  var systemImage: String
  var title: String
  var colour: Int
  var optionalText: String?

  @Environment(\.dynamicTypeSize) var dynamicTypeSize

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(.body, design: .rounded))

        //                .font(.system(size: 17))
        //                .padding(5)
        .foregroundColor(.white)
        .frame(
          width: dynamicTypeSize > .xLarge ? 40 : 30, height: dynamicTypeSize > .xLarge ? 40 : 30,
          alignment: .center
        )
        .background(Color("\(colour)"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

      Text(LocalizedStringKey(title))
        .font(.system(.body, design: .rounded).weight(.medium))

        //                .font(.system(size: 17, weight: .medium, design: .rounded))
        .lineLimit(1)
        .foregroundColor(Color.PrimaryText)

      Spacer()

      if optionalText != nil {
        Text(optionalText!)
          .font(.system(.body, design: .rounded))

          //                    .font(.system(size: 17, weight: .regular, design: .rounded))
          .foregroundColor(.DarkIcon.opacity(0.6))
          .layoutPriority(1)
          .padding(.trailing, -8)
      }

      Image(systemName: "chevron.forward")
        .font(.system(.subheadline, design: .rounded))
        //                .font(.system(size: 15))
        .foregroundColor(.DarkIcon.opacity(0.6))
    }
    .frame(maxWidth: .infinity, minHeight: .settingsRowHeight)
    .contentShape(Rectangle())
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }
}

struct SettingsCategoryView: View {
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

  var body: some View {
    CategoryView(mode: .settings, income: false)
      .background(Color.PrimaryBackground)
  }
}
