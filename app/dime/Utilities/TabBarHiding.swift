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
