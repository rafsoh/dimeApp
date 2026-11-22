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

    private var usesVerticalBar: Bool {
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

        let usesVerticalBar = usesVerticalBar
        // HomeView hides every UITabBar through the appearance proxy, so the system bar has to be revealed explicitly.
        tabBarController?.tabBar.isHidden = !usesVerticalBar

        DispatchQueue.main.async { [weak self] in
            self?.onChange?(usesVerticalBar)
        }
    }
}

extension View {
    /// Reports whether the system places tabs in a vertical bar (iPhone Duo), and shows the native tab bar when it does.
    /// Apply to a view inside a `TabView` tab so the probe can reach the tab bar controller.
    func readsVerticalBar(_ usesVerticalBar: Binding<Bool>) -> some View {
        background(VerticalBarReader(usesVerticalBar: usesVerticalBar).frame(width: 0, height: 0))
    }
}
