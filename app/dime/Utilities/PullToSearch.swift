import SwiftUI
import UIKit

/// Tracks how far a scroll view is pulled down past its top edge and fires
/// `onTrigger` when the user lets go beyond `threshold`.
///
/// Reads `contentOffset` straight from the backing `UIScrollView` through KVO, so a
/// long list only pays a comparison per scroll frame. Only views observing this model
/// re-render, and only while the list is overscrolled at the top.
final class PullToSearchModel: NSObject, ObservableObject {
    static let threshold: CGFloat = 60

    /// 0 at rest, 1 at the trigger threshold.
    @Published private(set) var progress: CGFloat = 0
    @Published private(set) var armed = false

    var onTrigger: () -> Void = {}

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    func attach(to scrollView: UIScrollView) {
        guard scrollView !== self.scrollView else { return }
        detach()
        self.scrollView = scrollView
        observation = scrollView.observe(\.contentOffset) { [weak self] scrollView, _ in
            self?.scrollViewDidScroll(scrollView)
        }
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
    }

    func detach() {
        observation = nil
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
        scrollView = nil
    }

    deinit {
        detach()
    }

    private func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let pull = -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        guard pull > 0 || progress > 0 else { return }

        let tracking = scrollView.isTracking
        if tracking, progress == 0 {
            haptic.prepare()
        }

        let target = min(max(pull / Self.threshold, 0), 1)
        // Momentum bounces at the top shouldn't grow the button; they can only
        // shrink it back after a release.
        let next = tracking ? target : min(target, progress)
        if next != progress, abs(next - progress) > 0.005 || next == 0 || next == 1 {
            progress = next
        }

        guard tracking else { return }
        if pull >= Self.threshold, !armed {
            withAnimation(Self.popAnimation) {
                armed = true
            }
            haptic.impactOccurred()
        } else if pull < Self.threshold, armed {
            withAnimation(Self.popAnimation) {
                armed = false
            }
        }
    }

    private static let popAnimation = Animation.spring(response: 0.25, dampingFraction: 0.55)

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .ended:
            guard armed else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                armed = false
                progress = 0
            }
            onTrigger()
        case .cancelled, .failed:
            armed = false
        case .possible, .began, .changed:
            break
        @unknown default:
            break
        }
    }
}

extension View {
    /// Attach inside a `ScrollView`'s content to drive `model` from that scroll view.
    func pullToSearch(_ model: PullToSearchModel, onTrigger: @escaping () -> Void) -> some View {
        background(PullToSearchAnchor(model: model, onTrigger: onTrigger).allowsHitTesting(false))
    }

    /// Grows the view as the list is pulled, with a pop once release would trigger.
    func pullToSearchScale(_ model: PullToSearchModel) -> some View {
        modifier(PullToSearchScale(model: model))
    }
}

private struct PullToSearchScale: ViewModifier {
    @ObservedObject var model: PullToSearchModel

    func body(content: Content) -> some View {
        // Separate effects so per-frame progress updates don't cut off the animated pop.
        content
            .scaleEffect(1 + 0.25 * model.progress)
            .scaleEffect(model.armed ? 1.08 : 1)
    }
}

private struct PullToSearchAnchor: UIViewRepresentable {
    let model: PullToSearchModel
    let onTrigger: () -> Void

    func makeUIView(context _: Context) -> AnchorView {
        AnchorView(model: model)
    }

    func updateUIView(_: AnchorView, context _: Context) {
        model.onTrigger = onTrigger
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator _: ()) {
        uiView.model.detach()
    }

    final class AnchorView: UIView {
        let model: PullToSearchModel

        init(model: PullToSearchModel) {
            self.model = model
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // SwiftUI finishes inserting the hosting views after this call.
            DispatchQueue.main.async { [weak self] in
                guard let self, let scrollView = self.enclosingScrollView() else { return }
                self.model.attach(to: scrollView)
            }
        }

        private func enclosingScrollView() -> UIScrollView? {
            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                view = current.superview
            }
            return nil
        }
    }
}
