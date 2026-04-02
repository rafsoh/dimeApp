//
//  AppDelegate.swift
//  dime
//
//  Created by Rafael Soh on 24/8/22.
//

import SwiftUI
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Register notification categories with action buttons

        // Daily reminder category with "Quick Log" action
        let quickLogAction = UNNotificationAction(
            identifier: "QUICK_LOG_ACTION",
            title: String(localized: "Quick Log"),
            options: [.foreground]
        )

        let reminderCategory = UNNotificationCategory(
            identifier: "DAILY_REMINDER",
            actions: [quickLogAction],
            intentIdentifiers: [],
            options: []
        )

        // Categorize transaction category with "Categorize Now" action
        let categorizeAction = UNNotificationAction(
            identifier: "CATEGORIZE_ACTION",
            title: String(localized: "Categorize Now"),
            options: [.foreground]
        )

        let categorizeCategory = UNNotificationCategory(
            identifier: "CATEGORIZE_TRANSACTION",
            actions: [categorizeAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([reminderCategory, categorizeCategory])

        return true
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let sceneConfiguration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        sceneConfiguration.delegateClass = SceneDelegate.self
        return sceneConfiguration
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        let actionIdentifier = response.actionIdentifier

        switch actionIdentifier {
        case "QUICK_LOG_ACTION":
            // "Quick Log" button on daily reminder → open new expense
            if let url = URL(string: "dimeapp://newExpense") {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
            }

        case "CATEGORIZE_ACTION":
            // "Categorize Now" button on categorize notification → open transaction edit
            openCategorizeURL(from: response)

        case UNNotificationDefaultActionIdentifier:
            // Default tap on notification body
            if categoryIdentifier == "CATEGORIZE_TRANSACTION" {
                openCategorizeURL(from: response)
            } else if categoryIdentifier == "DAILY_REMINDER" {
                if let url = URL(string: "dimeapp://newExpense") {
                    DispatchQueue.main.async {
                        UIApplication.shared.open(url)
                    }
                }
            }

        default:
            break
        }

        completionHandler()
    }

    private func openCategorizeURL(from response: UNNotificationResponse) {
        if let transactionID = response.notification.request.content.userInfo["transactionID"] as? String {
            if let url = URL(string: "dimeapp://categorize?id=\(transactionID)") {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}
