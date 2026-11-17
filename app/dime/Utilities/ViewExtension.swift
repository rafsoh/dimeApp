//
//  ViewExtension.swift
//  xpenz
//
//  Created by Rafael Soh on 16/5/22.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
    extension View {
        func hideKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
#endif

extension View {
    @ViewBuilder func scrollEnabled(_ enabled: Bool) -> some View {
        if enabled {
            self
        } else {
            simultaneousGesture(DragGesture(minimumDistance: 0),
                                including: .all)
        }
    }
}

extension HorizontalAlignment {
    struct MoneySubtitle: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat {
            d[.top]
        }
    }

    static let moneySubtitle = HorizontalAlignment(MoneySubtitle.self)
}

extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}

class Utilities {
    @AppStorage("colourScheme") var selectedAppearance = 0
    var userInterfaceStyle: ColorScheme? = .dark

    func overrideDisplayMode() {
        var userInterfaceStyle: UIUserInterfaceStyle

        if selectedAppearance == 2 {
            userInterfaceStyle = .dark
        } else if selectedAppearance == 1 {
            userInterfaceStyle = .light
        } else {
            userInterfaceStyle = .unspecified
        }

        (UIApplication.shared.connectedScenes.first as?
            UIWindowScene)?.windows.first!.overrideUserInterfaceStyle = userInterfaceStyle
    }
}

// MARK: - Liquid Glass

/// Liquid Glass for floating controls (toolbar buttons, toasts, the add button).
/// On iOS 26+ it renders `.glassEffect`; on older systems, or with Reduce Transparency on,
/// it falls back to the flat fill the app has always used, so nothing changes there.
/// Keep it off content (transaction rows, charts, the amount display).
struct DimeGlass<S: Shape>: ViewModifier {
    let shape: S
    var fallback: Color = .SecondaryBackground
    var tint: Color?
    var interactive = false
    /// Keep the fallback fill under the glass, for primary controls whose solid colour is the brand.
    var solid = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            if solid {
                content
                    .background(fallback, in: shape)
                    .glassEffect(glass, in: shape)
            } else {
                content.glassEffect(glass, in: shape)
            }
        } else {
            content.background(fallback, in: shape)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

extension View {
    func dimeGlass<S: Shape>(_ shape: S, fallback: Color = .SecondaryBackground, tint: Color? = nil, interactive: Bool = false, solid: Bool = false) -> some View {
        modifier(DimeGlass(shape: shape, fallback: fallback, tint: tint, interactive: interactive, solid: solid))
    }
}
