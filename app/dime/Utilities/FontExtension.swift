//
//  FontExtension.swift
//  dime
//
//  Created by Rafael Soh on 29/7/22.
//

import UIKit
import SwiftUI

extension UIFont {

    static func getBodyFontSize(dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        switch dynamicTypeSize {
        case .xSmall:
            return 14
        case .small:
            return 15
        case .medium:
            return 16
        case .large:
            return 17
        case .xLarge:
            return 19
        case .xxLarge:
            return 21
        case .xxxLarge:
            return 23
        default:
            return 23
        }
    }

    class func rounded(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        if AppFont.current == .allo, let allo = UIFont(name: AppFont.alloName(for: weight), size: size) {
            return allo
        }
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        let font: UIFont

        if let descriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: descriptor, size: size)
        } else {
            font = systemFont
        }
        return font
    }

    class func roundedSpecial(ofStyle style: UIFont.TextStyle, weight: UIFont.Weight, size: Double) -> UIFont {
        if AppFont.current == .allo, let allo = UIFont(name: AppFont.alloName(for: weight), size: size) {
            return UIFontMetrics(forTextStyle: style).scaledFont(for: allo)
        }
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        let font: UIFont

        if let descriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: descriptor, size: size)
        } else {
            font = systemFont
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    static func textStyleSize(_ style: UIFont.TextStyle) -> CGFloat {
        UIFont.preferredFont(forTextStyle: style).pointSize
    }

}

/// The typeface chosen in Settings > Font. Read by the app and the widgets, so it lives in the app group.
enum AppFont: Int, CaseIterable {
    case sfProRounded = 0
    case allo = 1

    static let storageKey = "appFont"
    private static let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")

    static var current: AppFont {
        AppFont(rawValue: defaults?.integer(forKey: storageKey) ?? 0) ?? .sfProRounded
    }

    var displayName: String {
        switch self {
        case .sfProRounded: return "SF Pro Rounded"
        case .allo: return "Allo"
        }
    }

    /// Allo ships as static faces (Allo-Regular.ttf, …) in the app and widget bundles, listed under UIAppFonts.
    static func alloName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Allo-Bold"
        case .semibold: return "Allo-SemiBold"
        case .medium: return "Allo-Medium"
        default: return "Allo-Regular"
        }
    }

    static func alloName(for weight: UIFont.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Allo-Bold"
        case .semibold: return "Allo-SemiBold"
        case .medium: return "Allo-Medium"
        default: return "Allo-Regular"
        }
    }

    /// Point sizes of the text styles at the default (Large) Dynamic Type size; custom fonts scale from these.
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        default: return 17
        }
    }
}

extension Font {
    /// The app's font for a text style: SF Pro Rounded or Allo, following Settings. Scales with Dynamic Type.
    static func app(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        switch AppFont.current {
        case .sfProRounded:
            let font = Font.system(style, design: .rounded)
            return weight.map { font.weight($0) } ?? font
        case .allo:
            let resolved = weight ?? (style == .headline ? .semibold : .regular)
            return .custom(AppFont.alloName(for: resolved), size: AppFont.baseSize(style), relativeTo: style)
        }
    }

    /// The app's font at a fixed size, like `.system(size:weight:design: .rounded)`.
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch AppFont.current {
        case .sfProRounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .allo:
            return .custom(AppFont.alloName(for: weight), fixedSize: size)
        }
    }
}
