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
            ContentView()
                .environment(\.managedObjectContext, dataController.container.viewContext)
                .environmentObject(appLockVM)
                .environmentObject(dataController)
                .environmentObject(unlockManager)
                .environmentObject(tabBarManager)
        }
    }

    init() {
        let dataController = DataController.shared
//        let dataController = DataController()
        let unlockManager = UnlockManager(dataController: dataController)

        _dataController = StateObject(wrappedValue: dataController)
        _unlockManager = StateObject(wrappedValue: unlockManager)

        UITableView.appearance().backgroundColor = .clear

        #if DEBUG
        // Launch with `-appFont 1` for Allo, `-appFont 0` for SF Pro Rounded.
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
