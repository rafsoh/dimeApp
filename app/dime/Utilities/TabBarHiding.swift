//
//  TabBarHiding.swift
//  dime
//
//  Created by Rafael Soh on 18/9/22.
//

import Foundation
import SwiftUI
import UIKit

class TabBarManager: ObservableObject {
    @Published var hideTab = false
    @Published var inNavigationLink = false

    func navigationHideTab() {
        inNavigationLink = true
        hideTab = true
    }

    func navigationShowTab() {
        inNavigationLink = false
        hideTab = false
    }

    func scrollHideTab() {
        if !inNavigationLink {
            hideTab = true
        }
    }

    func scrollShowTab() {
        if !inNavigationLink {
            hideTab = false
        }
    }
}

enum VerticalBar {
    /// Whether the system places bars vertically along a side edge, as on the iPhone Duo's cover screen.
    static func isActive(in traitCollection: UITraitCollection) -> Bool {
        guard #available(iOS 27.1, *) else { return false }

        switch traitCollection.verticalBarEdge {
        case .leading, .trailing:
            return true
        case .unspecified:
            return false
        @unknown default:
            return false
        }
    }

    static var isActiveInKeyWindow: Bool {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard let keyWindow else { return false }
        return isActive(in: keyWindow.traitCollection)
    }
}

private struct UsesVerticalBarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the tabs sit in a vertical bar (iPhone Duo), where navigation buttons belong in that bar too.
    var usesVerticalBar: Bool {
        get { self[UsesVerticalBarKey.self] }
        set { self[UsesVerticalBarKey.self] = newValue }
    }
}

private struct SheetButtonsInSideBarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether `sideBarSheet` has moved this sheet's top buttons into the iPhone Duo's side bar.
    var sheetButtonsInSideBar: Bool {
        get { self[SheetButtonsInSideBarKey.self] }
        set { self[SheetButtonsInSideBarKey.self] = newValue }
    }
}

/// On the iPhone Duo the system bar runs down the side, and a sheet's close and action buttons belong there
/// rather than in its own header. Wraps the sheet in a navigation stack whose toolbar holds `items`.
/// Everywhere else the sheet is left exactly as it was.
private struct SideBarSheet<Items: ToolbarContent>: ViewModifier {
    let items: () -> Items

    @State private var usesVerticalBar = VerticalBar.isActiveInKeyWindow

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 16.0, *), usesVerticalBar {
                NavigationStack {
                    content
                        .toolbar { items() }
                }
            } else {
                content
            }
        }
        .environment(\.sheetButtonsInSideBar, usesVerticalBar)
        .readsVerticalBar($usesVerticalBar)
    }
}

private struct HiddenInSideBar: ViewModifier {
    @Environment(\.sheetButtonsInSideBar) private var inSideBar

    @ViewBuilder func body(content: Content) -> some View {
        if !inSideBar {
            content
        }
    }
}

extension View {
    /// Puts this sheet's top buttons in the iPhone Duo's side bar. Mark the header's own buttons `hiddenInSideBar()`.
    func sideBarSheet<Items: ToolbarContent>(@ToolbarContentBuilder items: @escaping () -> Items) -> some View {
        modifier(SideBarSheet(items: items))
    }

    /// Leaves out a sheet header's button where `sideBarSheet` shows it in the side bar instead.
    func hiddenInSideBar() -> some View {
        modifier(HiddenInSideBar())
    }
}

/// A `sideBarSheet` sheet's close button, or its back button while it shows a page within the sheet.
struct SideBarCloseItem: ToolbarContent {
    var isBack = false
    var isShown = true
    let action: () -> Void

    var body: some ToolbarContent {
        // Conditions go inside the item: `if` in toolbar content needs iOS 16.
        ToolbarItem(placement: .topBarLeading) {
            if isShown {
                Button(action: action) {
                    if isBack {
                        Label("Back", systemImage: "chevron.left")
                    } else {
                        Label("Close", systemImage: "xmark")
                    }
                }
            }
        }
    }
}

/// A `sideBarSheet` sheet's confirm button, drawn prominent like the dark checkmark in the sheet's own header.
struct SideBarConfirmItem: ToolbarContent {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: action) {
                Label(title, systemImage: "checkmark")
            }
            .prominentToolbarButton(tint: Color.DarkBackground, isProminent: true)
        }
    }
}

#if DEBUG
// SCREENSHOT ONLY, remove before merging: `-sideBarShot <name>` opens that sheet.
func sideBarShot(_ name: String, perform action: @escaping () -> Void) {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "-sideBarShot"), index + 1 < arguments.count, arguments[index + 1] == name else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: action)
}
#endif

private struct VerticalBarReader: UIViewRepresentable {
    @Binding var usesVerticalBar: Bool

    func makeUIView(context: Context) -> VerticalBarProbeView {
        let view = VerticalBarProbeView()
        view.onChange = { usesVerticalBar = $0 }
        return view
    }

    func updateUIView(_ uiView: VerticalBarProbeView, context: Context) {
        uiView.onChange = { usesVerticalBar = $0 }
    }
}

private final class VerticalBarProbeView: UIView {
    var onChange: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        if #available(iOS 27.1, *) {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (view: VerticalBarProbeView, _: UITraitCollection) in
                view.update()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        update()
    }

    private var tabBarController: UITabBarController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UITabBarController {
                return controller
            }
            responder = current.next
        }
        return nil
    }

    private func update() {
        guard #available(iOS 27.1, *), window != nil else { return }

        let usesVerticalBar = VerticalBar.isActive(in: traitCollection)
        // HomeView hides every UITabBar through the appearance proxy, so the system bar has to be revealed explicitly.
        tabBarController?.tabBar.isHidden = !usesVerticalBar

        DispatchQueue.main.async { [weak self] in
            self?.onChange?(usesVerticalBar)
        }
    }
}

extension GeometryProxy {
    /// Space covered by system elements along the side edges, such as the iPhone Duo's vertical status bar.
    /// Sheets don't receive this as a safe area inset.
    var sideOcclusionInsets: EdgeInsets {
        guard #available(iOS 27.1, *) else { return EdgeInsets() }

        var insets = EdgeInsets()
        for region in reservedRegions(kind: .occlusion) where region.frame.width < size.width / 2 {
            if region.frame.maxX >= size.width {
                insets.trailing = max(insets.trailing, size.width - region.frame.minX)
            }
            if region.frame.minX <= 0 {
                insets.leading = max(insets.leading, region.frame.maxX)
            }
        }
        return insets
    }
}

extension View {
    /// Reports whether the system places tabs in a vertical bar (iPhone Duo), and shows the native tab bar when it does.
    /// Apply to a view inside a `TabView` tab so the probe can reach the tab bar controller.
    func readsVerticalBar(_ usesVerticalBar: Binding<Bool>) -> some View {
        background(VerticalBarReader(usesVerticalBar: usesVerticalBar).frame(width: 0, height: 0))
    }
}

/// Replaces the tab bar controller's switch transition, which scales and fades the page on iOS 26, with an instant one.
/// SwiftUI drives `TabView` through the controller's delegate, so every other delegate call is passed on to it.
private final class InstantTabTransition: NSObject, UITabBarControllerDelegate, UIViewControllerAnimatedTransitioning {
    weak var forwarded: UITabBarControllerDelegate?

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (forwarded?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        forwarded?.responds(to: selector) == true ? forwarded : nil
    }

    func tabBarController(_: UITabBarController, animationControllerForTransitionFrom _: UIViewController, to _: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        self
    }

    func transitionDuration(using _: UIViewControllerContextTransitioning?) -> TimeInterval {
        0
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        if let toView = context.view(forKey: .to), let toController = context.viewController(forKey: .to) {
            toView.frame = context.finalFrame(for: toController)
            context.containerView.addSubview(toView)
        }
        context.view(forKey: .from)?.removeFromSuperview()
        context.completeTransition(!context.transitionWasCancelled)
    }
}

private struct InstantTabSwitching: UIViewRepresentable {
    func makeUIView(context _: Context) -> InstantTabSwitchingProbeView {
        InstantTabSwitchingProbeView()
    }

    func updateUIView(_: InstantTabSwitchingProbeView, context _: Context) {}
}

private final class InstantTabSwitchingProbeView: UIView {
    private static let transition = InstantTabTransition()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        install()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        install()
    }

    /// SwiftUI can replace the delegate when it updates the `TabView`, so this re-wraps whatever delegate is current.
    private func install() {
        var responder: UIResponder? = self
        while let current = responder, !(current is UITabBarController) {
            responder = current.next
        }
        guard let tabBarController = responder as? UITabBarController else { return }

        let transition = Self.transition
        guard tabBarController.delegate !== transition else { return }
        transition.forwarded = tabBarController.delegate
        tabBarController.delegate = transition
    }
}

extension View {
    /// Switches tabs without the system's transition. Apply to a view inside a `TabView` tab.
    func instantTabSwitching() -> some View {
        background(InstantTabSwitching().frame(width: 0, height: 0))
    }
}
