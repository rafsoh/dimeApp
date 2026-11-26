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

    /// The app's font (see `AppFont`) at a fixed size. Named for SF Pro Rounded, the default.
    class func rounded(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let current = AppFont.current
        if let name = current.faceName(for: weight), let custom = UIFont(name: name, size: size) {
            return custom
        }
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        guard current.usesRoundedSystemFont, let descriptor = systemFont.fontDescriptor.withDesign(.rounded) else {
            return systemFont
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    class func roundedSpecial(ofStyle style: UIFont.TextStyle, weight: UIFont.Weight, size: Double) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: rounded(ofSize: size, weight: weight))
    }

    static func textStyleSize(_ style: UIFont.TextStyle) -> CGFloat {
        UIFont.preferredFont(forTextStyle: style).pointSize
    }

}

/// The typeface chosen in Settings > Font. Read by the app and the widgets, so it lives in the app group.
/// Raw values are stored, so never change them; cases are listed in the order Settings shows them.
enum AppFont: Int, CaseIterable {
    case sfProRounded = 0
    case sfPro = 2
    case allo = 1
    case atkinson = 3
    case fraunces = 4
    case geistPixel = 5

    static let storageKey = "appFont"
    private static let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")

    static var current: AppFont {
        AppFont(rawValue: defaults?.integer(forKey: storageKey) ?? 0) ?? .sfProRounded
    }

    var displayName: String {
        switch self {
        case .sfProRounded: return "SF Pro Rounded"
        case .sfPro: return "SF Pro"
        case .allo: return "Allo"
        case .atkinson: return "Atkinson Hyperlegible"
        case .fraunces: return "Fraunces"
        case .geistPixel: return "Geist Pixel"
        }
    }

    /// The system design for the SF fonts; nil for fonts bundled with the app.
    var systemDesign: Font.Design? {
        switch self {
        case .sfProRounded: return .rounded
        case .sfPro: return .default
        default: return nil
        }
    }

    var usesRoundedSystemFont: Bool { self == .sfProRounded }

    /// Bundled fonts ship as static faces in the app and widget bundles (dime/Fonts, listed under UIAppFonts).
    /// Returns the PostScript name of the face closest to `weight`, or nil for the system fonts.
    func faceName(for weight: Font.Weight) -> String? {
        let face: String
        switch weight {
        case .bold, .heavy, .black: face = "Bold"
        case .semibold: face = "SemiBold"
        case .medium: face = "Medium"
        default: face = "Regular"
        }
        switch self {
        case .sfProRounded, .sfPro: return nil
        case .allo: return "Allo-\(face)"
        case .atkinson: return "AtkinsonHyperlegibleNext-\(face)"
        case .fraunces: return "Fraunces-\(face)"
        // Geist Pixel has a single weight.
        case .geistPixel: return "GeistPixel-Square"
        }
    }

    func faceName(for weight: UIFont.Weight) -> String? {
        switch weight {
        case .bold, .heavy, .black: return faceName(for: Font.Weight.bold)
        case .semibold: return faceName(for: Font.Weight.semibold)
        case .medium: return faceName(for: Font.Weight.medium)
        default: return faceName(for: Font.Weight.regular)
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
    /// The app's font for a text style, following Settings > Font. Scales with Dynamic Type.
    static func app(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        app(style, weight: weight, font: .current)
    }

    static func app(_ style: Font.TextStyle, weight: Font.Weight? = nil, font appFont: AppFont) -> Font {
        if let design = appFont.systemDesign {
            let font = Font.system(style, design: design)
            return weight.map { font.weight($0) } ?? font
        }
        let resolved = weight ?? (style == .headline ? .semibold : .regular)
        return .custom(appFont.faceName(for: resolved) ?? "", size: AppFont.baseSize(style), relativeTo: style)
    }

    /// The app's font at a fixed size, like `.system(size:weight:design: .rounded)`.
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let appFont = AppFont.current
        if let design = appFont.systemDesign {
            return .system(size: size, weight: weight, design: design)
        }
        return .custom(appFont.faceName(for: weight) ?? "", fixedSize: size)
    }
}
