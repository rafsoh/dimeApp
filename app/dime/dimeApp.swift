//
//  dimeApp.swift
//  dime
//
//  Created by Rafael Soh on 11/7/22.
//

import SwiftUI

@main
struct dimeApp: App {
    @StateObject var dataController: DataController
    @StateObject var unlockManager: UnlockManager
    @StateObject var appLockVM = AppLockViewModel()
    @StateObject var tabBarManager = TabBarManager()

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            Group {
                if let failure = dataController.storeLoadFailure {
                    // Never a crash: people whose store won't open would otherwise delete the app to get past it.
                    StoreLoadFailedView(failure: failure) {
                        dataController.retryLoadingStore()
                    }
                } else {
                    ContentView()
                }
            }
            .environment(\.managedObjectContext, dataController.container.viewContext)
            .environmentObject(appLockVM)
            .environmentObject(dataController)
            .environmentObject(unlockManager)
            .environmentObject(tabBarManager)
        }
    }

    init() {
        // Before the store opens, so a migration failure is reported with the crash that follows it.
        SentryBootstrap.start()

        let dataController = DataController.shared
//        let dataController = DataController()
        let unlockManager = UnlockManager(dataController: dataController)

        _dataController = StateObject(wrappedValue: dataController)
        _unlockManager = StateObject(wrappedValue: unlockManager)

        UITableView.appearance().backgroundColor = .clear

        #if DEBUG
        // Launch with `-appFont <AppFont raw value>`, e.g. `-appFont 1` for Allo, `-appFont 0` for SF Pro Rounded.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-appFont"), index + 1 < arguments.count, let font = Int(arguments[index + 1]) {
            UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.set(font, forKey: AppFont.storageKey)
        }
        #endif

        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: UIFont.rounded(ofSize: 34, weight: .bold))
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: UIFont.rounded(ofSize: 17, weight: .semibold))
        ]

        KeyboardHeightCache.shared.start()

        // The New Expense control (Control Center, Lock Screen, Action Button) runs
        // OpenNewExpenseIntent in the app; route it through the same dimeapp://newExpense
        // link the widgets use, so app lock and the add sheet behave the same way.
        NewExpenseLauncher.open = {
            UIApplication.shared.open(NewExpenseLauncher.url)
        }
    }
}

/// Shown when the store can't be opened. Nothing is changed or deleted; the file stays as it was.
struct StoreLoadFailedView: View {
    let failure: DataController.StoreLoadFailure
    let retry: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44, weight: .regular))
                .foregroundColor(Color.SubtitleText)
                .accessibilityHidden(true)

            Text("Dime couldn't open your data")
                .font(.app(.title3, weight: .semibold))
                .foregroundColor(Color.PrimaryText)
                .multilineTextAlignment(.center)

            Text("Your entries are still on this device, and nothing has been changed or deleted. Please don't delete Dime: that would remove them. Try again, or contact support if this keeps happening.")
                .font(.app(.body))
                .foregroundColor(Color.SubtitleText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                isRetrying = true
                // Lets the button show its state before the main thread opens the store.
                DispatchQueue.main.async {
                    retry()
                    isRetrying = false
                }
            } label: {
                Text(isRetrying ? LocalizedStringKey("Trying Again…") : LocalizedStringKey("Try Again"))
                    .font(.app(.body, weight: .semibold))
                    .foregroundColor(Color.PrimaryBackground)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.DarkBackground, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
            .padding(.top, 8)

            Button {
                SupportEmail(toAddress: "rafasohhh@gmail.com", subject: "Dime couldn't open my data (\(failure.domain) \(failure.code))").send(openURL: openURL)
            } label: {
                Text("Contact Support")
                    .font(.app(.body, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)

            Text("\(failure.domain) \(String(failure.code))")
                .font(.app(.caption))
                .foregroundColor(Color.SubtitleText)
                .textSelection(.enabled)
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.PrimaryBackground.ignoresSafeArea())
    }
}
