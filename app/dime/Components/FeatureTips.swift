//
//  FeatureTips.swift
//  dime
//

import SwiftUI

/// A callout pointing at a feature people might not discover. Mark the feature with `.featureTip(_:)`, add
/// `.featureTipHost()` to a view around it, and call `markUsed()` when the feature is used. A tip shows on up to
/// `FeatureTipStore.maxShows` visits, until it's closed or the feature is used.
enum FeatureTip: String, CaseIterable {
    case currencySymbol

    var title: LocalizedStringKey {
        switch self {
        case .currencySymbol:
            return "Log in Any Currency"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .currencySymbol:
            return "Tap the symbol to change this transaction's currency."
        }
    }

    func markUsed() {
        FeatureTipStore.shared.finish(self)
    }
}

final class FeatureTipStore: ObservableObject {
    static let shared = FeatureTipStore()
    static let maxShows = 3

    private let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime") ?? .standard

    private func key(_ tip: FeatureTip, _ suffix: String) -> String {
        "featureTip.\(tip.rawValue).\(suffix)"
    }

    func isFinished(_ tip: FeatureTip) -> Bool {
        defaults.bool(forKey: key(tip, "finished"))
    }

    func isPending(_ tip: FeatureTip) -> Bool {
        !isFinished(tip) && defaults.integer(forKey: key(tip, "shows")) < Self.maxShows
    }

    func recordShow(_ tip: FeatureTip) {
        defaults.set(defaults.integer(forKey: key(tip, "shows")) + 1, forKey: key(tip, "shows"))
    }

    func finish(_ tip: FeatureTip) {
        guard !isFinished(tip) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            objectWillChange.send()
            defaults.set(true, forKey: key(tip, "finished"))
        }
    }
}

private struct FeatureTipAnchorKey: PreferenceKey {
    static let defaultValue: [FeatureTip: Anchor<CGRect>] = [:]

    static func reduce(value: inout [FeatureTip: Anchor<CGRect>], nextValue: () -> [FeatureTip: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks the view a tip points at. It only shows inside a `featureTipHost()`.
    func featureTip(_ tip: FeatureTip) -> some View {
        anchorPreference(key: FeatureTipAnchorKey.self, value: .bounds) { [tip: $0] }
    }

    /// Shows one pending tip at a time over this view, kept within its bounds. Use a view large enough to hold the
    /// callout above or below the target.
    func featureTipHost() -> some View {
        modifier(FeatureTipHost())
    }
}

private struct FeatureTipHost: ViewModifier {
    @ObservedObject private var store = FeatureTipStore.shared

    /// Decided once the screen settles, so a tip reaching its last show stays up for the rest of the visit.
    @State private var pendingTips: [FeatureTip]?
    @State private var shownTips: Set<FeatureTip> = []

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(FeatureTipAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if let tip = pendingTips?.first(where: { anchors[$0] != nil && !store.isFinished($0) }), let anchor = anchors[tip] {
                        FeatureTipCallout(tip: tip, target: proxy[anchor], bounds: proxy.size) {
                            store.finish(tip)
                        }
                        .id(tip)
                        .transition(.opacity)
                        .onAppear {
                            if shownTips.insert(tip).inserted {
                                store.recordShow(tip)
                            }
                        }
                    }
                }
            }
            .onAppear {
                // Waits for the sheet or push to finish so the callout doesn't arrive mid-transition.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    guard pendingTips == nil else { return }
                    pendingTips = FeatureTip.allCases.filter(store.isPending)
                }
            }
    }
}

private struct FeatureTipCallout: View {
    let tip: FeatureTip
    let target: CGRect
    let bounds: CGSize
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size: CGSize = .zero
    @State private var appeared = false

    private static let gap: CGFloat = 4
    private static let maxWidth: CGFloat = 330

    private var width: CGFloat {
        min(bounds.width, Self.maxWidth)
    }

    private var spaceAbove: CGFloat {
        target.minY - Self.gap
    }

    private var spaceBelow: CGFloat {
        bounds.height - target.maxY - Self.gap
    }

    /// Above the target when it fits, since below is where the note field sits.
    private var placedAbove: Bool {
        spaceAbove >= size.height || spaceAbove > spaceBelow
    }

    private var minX: CGFloat {
        min(max(target.midX - width / 2, 0), bounds.width - width)
    }

    private var minY: CGFloat {
        placedAbove ? target.minY - Self.gap - size.height : target.maxY + Self.gap
    }

    private var shape: FeatureTipShape {
        FeatureTipShape(arrowX: target.midX - minX, pointsUp: !placedAbove)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)

                Text(tip.message)
                    .font(.app(.subheadline))
                    .foregroundColor(Color.SubtitleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.app(.caption, weight: .bold))
                    .foregroundColor(Color.SubtitleText)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, -4)
            .padding(.trailing, -6)
            .accessibilityLabel(Text("Close"))
        }
        .padding(.leading, 16)
        .padding([.vertical, .trailing], 12)
        .padding(placedAbove ? .bottom : .top, FeatureTipShape.arrowSize.height)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.PrimaryBackground.opacity(0.5), in: shape)
        .glassBackground(in: shape, tint: .glassTint, interactive: false)
        .overlay(shape.stroke(Color.PrimaryText.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: FeatureTipSizeKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(FeatureTipSizeKey.self) { size = $0 }
        .scaleEffect(appeared || reduceMotion ? 1 : 0.9, anchor: UnitPoint(x: (target.midX - minX) / width, y: placedAbove ? 1 : 0))
        .opacity(appeared ? 1 : 0)
        .offset(x: minX, y: minY)
        .onChange(of: size) { newSize in
            guard !appeared, newSize != .zero else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }
}

private struct FeatureTipSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// A rounded rectangle with a soft arrow on its top edge, or its bottom edge when `pointsUp` is false.
private struct FeatureTipShape: Shape {
    /// The arrow's horizontal position, kept clear of the corners.
    var arrowX: CGFloat
    var pointsUp: Bool

    static let arrowSize = CGSize(width: 24, height: 9)
    private static let cornerRadius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let arrowWidth = Self.arrowSize.width
        let top = rect.minY + Self.arrowSize.height
        let radius = min(Self.cornerRadius, (rect.maxY - top) / 2)
        let x = min(max(rect.minX + arrowX, rect.minX + radius + arrowWidth / 2), rect.maxX - radius - arrowWidth / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: top))
        path.addLine(to: CGPoint(x: x - arrowWidth / 2, y: top))
        path.addCurve(to: CGPoint(x: x, y: rect.minY), control1: CGPoint(x: x - arrowWidth / 4, y: top), control2: CGPoint(x: x - 3, y: rect.minY))
        path.addCurve(to: CGPoint(x: x + arrowWidth / 2, y: top), control1: CGPoint(x: x + 3, y: rect.minY), control2: CGPoint(x: x + arrowWidth / 4, y: top))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: top), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.maxX, y: top), radius: radius)
        path.closeSubpath()

        guard !pointsUp else { return path }
        return path.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.minY + rect.maxY))
    }
}
