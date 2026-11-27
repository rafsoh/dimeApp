//
//  ContentView.swift
//
//  Created by Rafael Soh on 3/6/22.
//

import Foundation
import SwiftUI
import WidgetKit

struct ContentView: View {
    @EnvironmentObject var appLockVM: AppLockViewModel
    @ObservedObject var dataController = DataController.shared
    @ObservedObject private var backupManager = BackupManager.shared

    @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var colourScheme: Int = 0
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("showNotifications", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var showNotifications: Bool = false
    @AppStorage("notificationsEnabled", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var notificationsEnabled: Bool = true

    @AppStorage("firstLaunch", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var firstLaunch: Bool = true

    // adds category orders
    @AppStorage("dataMigration1", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var dataMigration1: Bool = true

    // converts category colors to hex codes
    @AppStorage("dataMigration2", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var dataMigration2: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode ?? "USD"

    @State var showIntro: Bool = false
    @State var showWhatsNew: Bool = false
    @State var whatsNewPending: Bool = false
    @State var whatsNewReleases: [WhatsNewRelease] = []
    @State var showAccountsIntro: Bool = false

    var center = UNUserNotificationCenter.current()

    private var isUsingDemoData: Bool {
        #if DEBUG
        DemoDataset(arguments: ProcessInfo.processInfo.arguments) != nil
        #else
        false
        #endif
    }

    /// Takes the main currency from iCloud key-value storage, or stores `fallback` there when it has none.
    ///
    /// Reading it can wait on the system's sync daemon; at launch on the main thread, that ended in the
    /// watchdog killing the app (DIME-IOS-W). It's read on a background queue, and the currency changes on the
    /// main thread only if nobody picked one meanwhile, such as during onboarding.
    private func adoptICloudCurrency(storingIfMissing fallback: String) {
        let currencyBefore = currency

        DispatchQueue.global(qos: .userInitiated).async {
            let store = NSUbiquitousKeyValueStore.default

            guard let stored = store.string(forKey: "currency") else {
                store.set(fallback, forKey: "currency")
                return
            }

            DispatchQueue.main.async {
                guard currency == currencyBefore, stored != currency else { return }
                currency = stored
                dataController.refreshExchangeRates()
            }
        }
    }

    @AppStorage("topEdge", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var savedTopEdge: Double = 30
    @AppStorage("bottomEdge", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var savedBottomEdge: Double = 15

    var body: some View {
        GeometryReader { proxy in
            let topEdge = proxy.safeAreaInsets.top
            let bottomEdge = proxy.safeAreaInsets.bottom

            HomeView(topEdge: topEdge, bottomEdge: bottomEdge == 0 ? 15 : bottomEdge)
                .ignoresSafeArea(.all, edges: .bottom)
                .preferredColorScheme(colourScheme == 1 ? .light : colourScheme == 2 ? .dark : nil)
                .fullScreenCover(isPresented: $showIntro) {
                    WelcomeSheetView()
                }
                .sheet(isPresented: $showWhatsNew) {
                    WhatsNewSheet(releases: whatsNewReleases)
                }
                .sheet(isPresented: $showAccountsIntro) {
                    AccountsIntroSheet()
                        .environmentObject(dataController)
                }
                .alert(item: Binding(get: { dataController.saveFailure }, set: { if $0 == nil { dataController.acknowledgeSaveFailure() } })) { failure in
                    // The changes are still in memory and are saved again when Dime comes back to the
                    // foreground; closing the app before then loses them.
                    Alert(
                        title: Text("Dime couldn't save your changes"),
                        message: Text(failure.isOutOfSpace
                            ? LocalizedStringKey("This device is out of storage. Free up some space in the Settings app, and Dime will save your changes when you come back.")
                            : LocalizedStringKey("Dime will try again. If this keeps happening, contact support.")),
                        dismissButton: .default(Text("OK"))
                    )
                }
                .onAppear {
                    savedTopEdge = topEdge
                    savedBottomEdge = bottomEdge
                }
        }
        .ignoresSafeArea(.keyboard)
        .alert(item: $backupManager.suggestedRestore) { suggestion in
            Alert(
                title: Text("Some of your data may be missing"),
                message: Text("Backup from \(suggestion.backup.createdAt.formatted(date: .abbreviated, time: .shortened)): \(suggestion.backup.transactionCount) transactions. On this device now: \(suggestion.currentTransactionCount). Restore what's missing? Nothing you have now will be removed or changed."),
                primaryButton: .default(Text("Restore")) {
                    backupManager.restore(suggestion.backup) { _ in }
                },
                secondaryButton: .cancel(Text("Not Now")) {
                    backupManager.dismissSuggestion(suggestion)
                }
            )
        }
        .onAppear {
//            UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.set(false, forKey: "newTransactionAdded")
//            WidgetCenter.shared.reloadTimelines(ofKind: "TemplateTransactions")

            backupManager.start()

            if appLockVM.isAppLockEnabled {
                appLockVM.appLockValidation()
            }

            let defaults =
                UserDefaults(suiteName: "group.com.rafaelsoh.dime") ?? UserDefaults.standard

            if defaults.object(forKey: "firstDayOfMonth") == nil {
                defaults.set(1, forKey: "firstDayOfMonth")
            }

            if firstLaunch {
                showIntro = true
                firstLaunch = false
                WhatsNew.markSeen()
                // Onboarding has its own accounts step.
                AccountsIntro.markSeen()

                // Fresh installs have no legacy data, and running these on categories that are still
                // arriving from iCloud would overwrite the user's order and colours on every device.
                dataMigration1 = false
                dataMigration2 = false

                defaults.set(1, forKey: "firstWeekday")
                defaults.set(1, forKey: "haptics")
                defaults.set(1, forKey: "firstDayOfMonth")
                defaults.set(1, forKey: "notificationOption")
                defaults.set(false, forKey: "confetti")
                defaults.set(false, forKey: "chromatic")
                defaults.set(true, forKey: "showCents")
                defaults.set(true, forKey: "animated")

                if isUsingDemoData {
                    // Demo data sets its own currency, and must not reach iCloud's copy.
                } else {
                    adoptICloudCurrency(storingIfMissing: Locale.current.currencyCode ?? "USD")
                }

                defaults.set(2, forKey: "numberEntryType")
            } else if isUsingDemoData {
                // Demo data sets its own currency, and must not reach iCloud's copy.
            } else {
                // Before iCloud's copy arrives, keep this device's currency rather than the locale's:
                // transactions name their currency, so a silent switch would make them all foreign.
                adoptICloudCurrency(storingIfMissing: currency)
            }

            dataController.refreshExchangeRates()
            MainCurrencyChangeManager.shared.resumeIfNeeded()

            if dataMigration1 {
                let categoryFetch = dataController.fetchRequestForCategoriesMigration(income: false)
                let categories = dataController.results(for: categoryFetch)

                categories.forEach { category in
                    category.order = Int64(categories.firstIndex(of: category) ?? 0)
                }

                dataController.save()

                dataMigration1 = false
            }

            if dataMigration2 {
                let categoryFetch = dataController.fetchRequestForCategoriesMigration()
                let categories = dataController.results(for: categoryFetch)

                categories.forEach { category in
                    if category.income {
                        category.colour = "#76FBB1"
                    } else {
                        if Double(category.wrappedColour) != nil {
                            category.colour = Color.colourMigrationDictionary[category.wrappedColour] ?? "#FFFFFF"
                        }
                    }
                }

                dataController.save()

                dataMigration2 = false
            }

            whatsNewReleases = WhatsNew.unseenReleases
            whatsNewPending = !whatsNewReleases.isEmpty || !AccountsIntro.isSeen

            #if DEBUG
            // Screenshots, removed with the other accounts launch arguments: `-accountsScreen intro` shows the
            // accounts introduction people updating see, and `-onboarding welcome|categories|accounts` the
            // onboarding a new install sees, at that page.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-accountsScreen"), index + 1 < arguments.count, arguments[index + 1] == "intro" {
                // Someone updating, even when it's the simulator's first launch.
                showIntro = false
                showAccountsIntro = true
            }
            if arguments.contains("-onboarding") {
                showIntro = true
            }
            #endif

            presentWhatsNewIfReady()

            center.getNotificationSettings { settings in
                if settings.authorizationStatus == .authorized {
                    if !showNotifications && notificationsEnabled == false {
                        showNotifications = true
                        notificationsEnabled = true
                    }

                    // Upcoming charge reminders only look a couple of months ahead, so top them up on every launch.
                    if showNotifications {
                        NotificationScheduler.shared.reschedule()
                    }
                } else if settings.authorizationStatus == .denied {
                    notificationsEnabled = false

                    if showNotifications {
                        showNotifications = false
                        center.removeAllPendingNotificationRequests()
                    }
                }
            }
        }
        .onChange(of: appLockVM.isAppUnLocked) { _ in
            presentWhatsNewIfReady()
        }
        .onReceive(NotificationCenter.default.publisher(for: DataController.dataIsCurrentNotification)) { _ in
            MainCurrencyChangeManager.shared.resumeIfNeeded()
        }
        .onChange(of: backupManager.suggestedRestore == nil) { _ in
            presentWhatsNewIfReady()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background || newPhase == .inactive {
                if newPhase == .background {
                    dataController.save()
                    backupManager.backUpIfNeeded()
                }

                if appLockVM.isAppLockEnabled {
                    appLockVM.isAppUnLocked = false
                }
            } else if newPhase == .active {
                dataController.refreshExchangeRates()
                MainCurrencyChangeManager.shared.resumeIfNeeded()

                center.getNotificationSettings { settings in
                    if settings.authorizationStatus == .authorized {
                        if !showNotifications && notificationsEnabled == false {
                            showNotifications = true
                            notificationsEnabled = true
                        }

                        if showNotifications {
                            NotificationScheduler.shared.reschedule()
                        }
                    } else if settings.authorizationStatus == .denied {
                        notificationsEnabled = false

                        if showNotifications {
                            showNotifications = false
                            center.removeAllPendingNotificationRequests()
                        }
                    }
                }
            }
        }
    }

    /// Waits for the lock screen and any restore offer, since the sheet would cover the first and block the second.
    func presentWhatsNewIfReady() {
        guard whatsNewPending, !showIntro, !showWhatsNew, !showAccountsIntro, backupManager.suggestedRestore == nil, !appLockVM.isAppLockEnabled || appLockVM.isAppUnLocked else {
            return
        }

        whatsNewPending = false

        // Lets the home screen settle first; a restore offer can still arrive in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard backupManager.suggestedRestore == nil, !appLockVM.isAppLockEnabled || appLockVM.isAppUnLocked else {
                whatsNewPending = true
                return
            }

            // Accounts get their own sheet, ahead of the release notes, which wait for the next launch
            // rather than following straight after. Anyone who already has accounts, say from another
            // device, has found them.
            if !AccountsIntro.isSeen {
                AccountsIntro.markSeen()
                if dataController.accountCount() == 0 {
                    showAccountsIntro = true
                    return
                }
            }

            guard !whatsNewReleases.isEmpty else { return }
            WhatsNew.markSeen()
            showWhatsNew = true
        }
    }
}
