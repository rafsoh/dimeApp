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

    // liquid glass on ios 26+, existing flat fill on older systems
    @ViewBuilder func dimeGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil, fallback: Color) -> some View {
        if #available(iOS 26, *) {
            glassEffect(dimeGlassStyle(tint: tint, interactive: interactive), in: shape)
        } else {
            background(fallback, in: shape)
        }
    }

    // glass circle behind a plain icon on ios 26+, unchanged on older systems
    @ViewBuilder func dimeGlassIcon(padding: CGFloat = 4) -> some View {
        if #available(iOS 26, *) {
            self.padding(padding).glassEffect(.regular.interactive(), in: Circle())
        } else {
            self
        }
    }

    // a highlight that only older systems need, since glass replaces it on ios 26+
    @ViewBuilder func backgroundBeforeIOS26<B: View>(@ViewBuilder _ highlight: () -> B) -> some View {
        if #available(iOS 26, *) {
            self
        } else {
            self.background { highlight() }
        }
    }

    // glass capsule on ios 26+, outlined capsule on older systems
    @ViewBuilder func dimeGlassCapsule(strokeFallback: Color) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            overlay(Capsule().stroke(strokeFallback, lineWidth: 1.3))
        }
    }

    // the floating glass tab bar is taller than the old opaque strip, so tab content needs extra bottom clearance
    @ViewBuilder func tabBarBottomPadding(_ legacy: CGFloat) -> some View {
        if #available(iOS 26, *) {
            padding(.bottom, legacy + CustomTabBar.floatingExtraInset)
        } else {
            padding(.bottom, legacy)
        }
    }
}

// builds the glass value outside the result builder, which does not allow assignments
@available(iOS 26, *)
private func dimeGlassStyle(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint {
        glass = glass.tint(tint)
    }
    if interactive {
        glass = glass.interactive()
    }
    return glass
}

// on/off switch used by the custom settings toggles: glass thumb on ios 26+, the original capsule and circle before
struct DimeSwitch: View {
    var isOn: Bool
    var id: String
    var namespace: Namespace.ID

    var body: some View {
        if #available(iOS 26, *) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .frame(width: 58, height: 26)
                    .foregroundColor(isOn ? .green : .gray.opacity(0.5))

                // a lightly white-tinted glass thumb, a little taller than the track so the glass refracts over its edges
                Color.clear
                    .frame(width: 40, height: 30)
                    .glassEffect(.regular.tint(Color.white.opacity(0.5)).interactive(), in: Capsule())
                    .padding(.horizontal, 1)
                    .matchedGeometryEffect(id: id, in: namespace)
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "On" : "Off")
        } else {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .frame(width: 42, height: 28)
                    .foregroundColor(isOn ? .green : .gray.opacity(0.8))

                Circle()
                    .foregroundColor(Color.white)
                    .padding(2)
                    .frame(width: 28, height: 28)
                    .matchedGeometryEffect(id: id, in: namespace)
            }
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
