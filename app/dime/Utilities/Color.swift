//
//  Color.swift
//  xpenz
//
//  Created by Rafael Soh on 10/5/22.
//

import Combine
import Foundation
import SwiftUI
import WidgetKit

extension Color {
    static let colourMigrationDictionary: [String: String] = [
        "1": "#279AF4",
        "2": "#EC7A58",
        "3": "#A6678A",
        "4": "#C56AF7",
        "5": "#6E7BF1",
        "6": "#F3BF56",
        "7": "#ED80A2",
        "8": "#F6D24A",
        "9": "#E34D63",
        "10": "#61C7FA",
        "11": "#7014F5",
        "12": "#EB7068",
        "13": "#84B4EB",
        "14": "#4088AD",
        "15": "#B8D6FA",
        "16": "#C38D5D",
        "17": "#A0ACF9",
        "18": "#7CB0AA",
        "19": "#F6D489",
        "20": "#88997A",
        "21": "#F1AF8A",
        "22": "#2D4B7B",
        "23": "#5FAF9F",
        "24": "#D46D7F"
    ]

    static let colorArray: [String] = [
        "#279AF4",
        "#EC7A58",
        "#A6678A",
        "#C56AF7",
        "#6E7BF1",
        "#F3BF56",
        "#ED80A2",
        "#F6D24A",
        "#E34D63",
        "#61C7FA",
        "#7014F5",
        "#EB7068",
        "#84B4EB",
        "#4088AD",
        "#B8D6FA",
        "#C38D5D",
        "#A0ACF9",
        "#7CB0AA",
        "#F6D489",
        "#88997A",
        "#F1AF8A",
        "#2D4B7B",
        "#5FAF9F",
        "#D46D7F"
    ]

    static let neuBackground = Color(hex: "f0f0f3")
    static let dropShadow = Color(hex: "aeaec0").opacity(0.4)
    static let dropLight = Color(hex: "ffffff")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (12-bit)
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (16-bit)
            (_, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    func toHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        if components.count >= 4 {
            a = Float(components[3])
        }

        if a != Float(1.0) {
            return String(format: "#%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }

    func luminance() -> Double {
        let components = UIColor(self).cgColor.components
        let r = components?[0] ?? 0
        let g = components?[1] ?? 0
        let b = components?[2] ?? 0
        return 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
    }

    static var PrimaryBackground: Color {
        return Color("PrimaryBackground")
    }

    static var SecondaryBackground: Color {
        return Color("SecondaryBackground")
    }

    static var DarkBackground: Color {
        return Color("DarkBackground")
    }

    static var PrimaryText: Color {
        return Color("PrimaryText")
    }

    static var AlertRed: Color {
        return Color("AlertRed")
    }

    static var IncomeGreen: Color {
        return Color("IncomeGreen")
    }

    static var BudgetBackground: Color {
        return Color("BudgetBackground")
    }

    static var SubtitleText: Color {
        return Color("SubtitleText")
    }

    static var Outline: Color {
        return Color("Outline")
    }

    static var LightIcon: Color {
        return Color("LightIcon")
    }

    static var DarkIcon: Color {
        return Color("DarkIcon")
    }

    static var GreyIcon: Color {
        return Color("GreyIcon")
    }

    static var BudgetRed: Color {
        return Color("BudgetRed")
    }

    static var Alert: Color {
        return Color("Alert")
    }

    static var TertiaryBackground: Color {
        return Color("TertiaryBackground")
    }

    static var SettingsBackground: Color {
        return Color("Settings")
    }

    static var EvenLighterText: Color {
        return Color("EvenLighterText")
    }
}

public extension View {
    @available(iOS 14.0, *)
    func colorPickerSheet(isPresented: Binding<Bool>, selection: Binding<Color>, supportsAlpha: Bool = true, title: String? = nil) -> some View {
        background(ColorPickerSheet(isPresented: isPresented, selection: selection, supportsAlpha: supportsAlpha, title: title))
    }
}

func blend(over color: Color, withAlpha alpha: CGFloat) -> Color {
    let uiColor = UIColor(color)
    let alphaClamped = min(max(alpha, 0), 1)

    guard let inputRGBComponents = uiColor.cgColor.components else {
        return color
    }

    let inputRed = inputRGBComponents[0]
    let inputGreen = inputRGBComponents[1]
    let inputBlue = inputRGBComponents[2]

    let whiteComponents: [CGFloat] = [1, 1, 1]
    let whiteRed = whiteComponents[0]
    let whiteGreen = whiteComponents[1]
    let whiteBlue = whiteComponents[2]

    // alpha blending
    let red = inputRed * alphaClamped + whiteRed * (1 - alphaClamped)
    let green = inputGreen * alphaClamped + whiteGreen * (1 - alphaClamped)
    let blue = inputBlue * alphaClamped + whiteBlue * (1 - alphaClamped)

    return Color(UIColor(red: red, green: green, blue: blue, alpha: 1))
}

@available(iOS 14.0, *)
private struct ColorPickerSheet: UIViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var selection: Color
    var supportsAlpha: Bool
    var title: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, isPresented: $isPresented)
    }

    class Coordinator: NSObject, UIColorPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
        @Binding var selection: Color
        @Binding var isPresented: Bool
        var didPresent = false

        init(selection: Binding<Color>, isPresented: Binding<Bool>) {
            _selection = selection
            _isPresented = isPresented
        }

        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            selection = Color(viewController.selectedColor)
        }

        func colorPickerViewControllerDidFinish(_: UIColorPickerViewController) {
            isPresented = false
            didPresent = false
        }

        func presentationControllerDidDismiss(_: UIPresentationController) {
            isPresented = false
            didPresent = false
            print("change3")
        }
    }

    func getTopViewController(from view: UIView) -> UIViewController? {
        guard var top = view.window?.rootViewController else {
            return nil
        }
        while let next = top.presentedViewController {
            top = next
        }
        return top
    }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if isPresented && !context.coordinator.didPresent {
            let modal = UIColorPickerViewController()
            modal.selectedColor = UIColor(selection)
            modal.supportsAlpha = supportsAlpha
            modal.title = title
            modal.delegate = context.coordinator
            modal.presentationController?.delegate = context.coordinator

            let top = getTopViewController(from: uiView)
            top?.present(modal, animated: true)
            context.coordinator.didPresent = true
        }
    }
}

// MARK: - Tinted & clear home screen

/// In the tinted and clear home-screen modes every colour is flattened to one tint,
/// so a grey track and a dark progress fill would look identical. Tracks fade back,
/// and the data itself is marked accentable so it takes the accent tint.
@available(iOS 16.0, *)
private struct WidgetTrack: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content.opacity(renderingMode == .fullColor ? 1 : 0.25)
    }
}

extension View {
    @ViewBuilder
    func widgetTrack() -> some View {
        if #available(iOS 16.0, *) {
            modifier(WidgetTrack())
        } else {
            self
        }
    }

    @ViewBuilder
    func widgetAccent() -> some View {
        if #available(iOS 16.0, *) {
            widgetAccentable()
        } else {
            self
        }
    }
}

// MARK: - Category icons

extension Color {
    /// Whether a `#RRGGBB` colour is light enough to need a dark glyph on top (WCAG relative luminance).
    static func isLight(hex: String) -> Bool {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count >= 6, let value = UInt64(clean.suffix(6), radix: 16) else { return true }
        func channel(_ c: UInt64) -> Double {
            let v = Double(c) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(value >> 16 & 0xFF) + 0.7152 * channel(value >> 8 & 0xFF) + 0.0722 * channel(value & 0xFF)
        // pick whichever of black/white contrasts more
        return (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05)
    }
}

/// A category's SF Symbol on its own; size it with `.font`, tint it with `.foregroundColor`.
struct CategoryIcon: View {
    let icon: String

    init(_ icon: String) {
        self.icon = icon
    }

    var body: some View {
        Image(systemName: UIImage(systemName: icon) == nil ? CategorySymbols.fallback : icon)
            .symbolRenderingMode(.monochrome)
            .accessibilityHidden(true)
    }
}

/// The category's symbol on a circle in its colour, with a black or white glyph chosen for contrast.
struct CategoryBadge: View {
    let icon: String
    let colour: String
    var size: CGFloat = 40
    var outlined = false

    var body: some View {
        ZStack {
            if outlined {
                Circle()
                    .strokeBorder(Color(hex: colour), lineWidth: 2)
            } else {
                Circle()
                    .fill(Color(hex: colour))
            }

            CategoryIcon(icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(outlined ? Color(hex: colour) : (Color.isLight(hex: colour) ? Color.black.opacity(0.8) : Color.white))
        }
        .frame(width: size, height: size)
    }
}
