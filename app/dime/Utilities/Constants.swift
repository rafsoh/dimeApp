//
//  Constants.swift
//  dime
//

import Foundation

enum Constants {
    // API key is loaded from Secrets.swift (not tracked by git)
    // Create app/dime/Utilities/Secrets.swift with:
    //   enum Secrets { static let geminiAPIKey = "YOUR_KEY_HERE" }
    static let geminiAPIKey = Secrets.geminiAPIKey
}
