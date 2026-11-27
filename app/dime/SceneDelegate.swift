//
//  SceneDelegate.swift
//  dime
//
//  Created by Rafael Soh on 24/8/22.
//

import SwiftUI

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    // Not @Environment(\.openURL): this isn't a view, so SwiftUI never installs an environment here.
    // Opening the app's own link reaches the scene's onOpenURL handlers the same way.
    func scene(
        _: UIScene,
        willConnectTo _: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            guard let url = URL(string: shortcutItem.type) else {
                return
            }

            UIApplication.shared.open(url)
        }
    }

    func windowScene(
        _: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: shortcutItem.type) else {
            completionHandler(false)
            return
        }

        UIApplication.shared.open(url, options: [:], completionHandler: completionHandler)
    }
}
