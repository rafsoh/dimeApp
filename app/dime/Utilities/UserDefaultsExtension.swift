//
//  UserDefaultsExtension.swift
//  dime
//
//  Created by Ahmer Mughal on 01.08.25.
//

import Foundation

extension UserDefaults {
    private static let customTimerKey = "customTimerList"

    func saveCustomTimerList(_ dates: [Date]) {
        if let encoded = try? JSONEncoder().encode(dates) {
            set(encoded, forKey: UserDefaults.customTimerKey)
        }
    }

    func loadCustomTimerList() -> [Date] {
        if let savedData = data(forKey: UserDefaults.customTimerKey),
           let decoded = try? JSONDecoder().decode([Date].self, from: savedData) {
            return decoded
        }
        return []
    }
}
