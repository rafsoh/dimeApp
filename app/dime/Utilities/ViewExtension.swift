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

extension View {
    @ViewBuilder func glassBackground<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = true, fallback: Color = Color.SecondaryBackground) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            background(fallback, in: shape)
        }
    }

    @ViewBuilder func whiteGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.plain)
                .glassEffect(.regular.tint(.white).interactive(), in: Capsule())
        } else {
            buttonStyle(WhiteCapsuleButtonStyle())
        }
    }
}

struct WhiteCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension View {
    @ViewBuilder func prominentToolbarButton(tint color: Color, isProminent: Bool) -> some View {
        if !isProminent {
            self
        } else if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent).tint(color)
        } else {
            tint(color)
        }
    }

    @ViewBuilder func bottomBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: .bottom, spacing: 0) {
                content()
                    .background {
                        LinearGradient(colors: [Color.PrimaryBackground.opacity(0), Color.PrimaryBackground], startPoint: .top, endPoint: .center)
                            .ignoresSafeArea(edges: .bottom)
                    }
            }
        }
    }

    @ViewBuilder func tabHeader<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0, content: content)
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            safeAreaInset(edge: .top, spacing: 0) {
                content()
                    .background(Color.PrimaryBackground.ignoresSafeArea(edges: .top))
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [Color.PrimaryBackground, Color.PrimaryBackground.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 24)
                            .offset(y: 24)
                            .allowsHitTesting(false)
                    }
            }
        }
    }
}

private struct TabBarTopKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private struct FloatingBarClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var tabBarTop: CGFloat? {
        get { self[TabBarTopKey.self] }
        set { self[TabBarTopKey.self] = newValue }
    }

    var floatingBarClearance: CGFloat {
        get { self[FloatingBarClearanceKey.self] }
        set { self[FloatingBarClearanceKey.self] = newValue }
    }
}

private struct TabBarClearanceModifier: ViewModifier {
    private static let gap: CGFloat = 24

    @Environment(\.tabBarTop) private var tabBarTop
    @Environment(\.floatingBarClearance) private var floatingBarClearance
    @State private var contentBottom: CGFloat?

    private var clearance: CGFloat {
        guard let tabBarTop, let contentBottom else { return floatingBarClearance }
        return max(0, contentBottom - tabBarTop) + Self.gap + floatingBarClearance
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: clearance)
                    .allowsHitTesting(false)
            }
            .background {
                GeometryReader { proxy in
                    let maxY = proxy.frame(in: .global).maxY
                    let safeBottom = proxy.safeAreaInsets.bottom
                    let bottom = maxY + safeBottom > UIScreen.main.bounds.height + 0.5 ? maxY - safeBottom : maxY
                    Color.clear
                        .onAppear { contentBottom = bottom }
                        .onChange(of: bottom) { contentBottom = $0 }
                }
            }
    }
}

extension View {
    func tabBarClearance() -> some View {
        modifier(TabBarClearanceModifier())
    }

    func floatingAboveTabBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(FloatingAboveTabBarModifier(bar: bar()))
    }
}

private struct FloatingAboveTabBarModifier<Bar: View>: ViewModifier {
    private static var gap: CGFloat { 12 }

    let bar: Bar

    @Environment(\.tabBarTop) private var tabBarTop
    @State private var containerBottom: CGFloat?
    @State private var barHeight: CGFloat = 0

    private var bottomPadding: CGFloat {
        guard let tabBarTop, let containerBottom else { return Self.gap }
        return max(0, containerBottom - tabBarTop) + Self.gap
    }

    func body(content: Content) -> some View {
        content
            .environment(\.floatingBarClearance, barHeight > 0 ? barHeight + Self.gap : 0)
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    GeometryReader { proxy in
                        let bottom = proxy.frame(in: .global).maxY
                        Color.clear
                            .onAppear { containerBottom = bottom }
                            .onChange(of: bottom) { containerBottom = $0 }
                    }
                    .allowsHitTesting(false)

                    bar
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear { barHeight = proxy.size.height }
                                    .onChange(of: proxy.size.height) { barHeight = $0 }
                            }
                        }
                        .padding(.bottom, bottomPadding)
                        .animation(.easeOut(duration: 0.25), value: bottomPadding)
                }
            }
    }
}

/// Fills and centres itself in the space it's given. Inside a ScrollView or List, add
/// `.fillsScrollViewport()` so it fills the visible space below its position instead.
struct EmptyStateView: View {
    private let systemImage: String
    private let title: LocalizedStringKey

    init(systemImage: String, title: LocalizedStringKey) {
        self.systemImage = systemImage
        self.title = title
    }

    var body: some View {
        EmptyStateLabel(systemImage: systemImage, title: title)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func fillsScrollViewport() -> some View {
        modifier(ScrollViewportFillModifier())
    }
}

private struct EmptyStateLabel: View {
    let systemImage: String
    let title: LocalizedStringKey

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .regular))
                .accessibilityHidden(true)

            Text(title)
                .font(.app(.title3, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(Color.SubtitleText)
        .frame(maxWidth: 280)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}

private struct ScrollViewportFillModifier: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .frame(minHeight: height)
            .background(ScrollViewportProbe(height: $height).allowsHitTesting(false))
    }
}

/// Measures the visible height of the enclosing UIScrollView below this view's top edge, at rest.
/// Content coordinates are used so the value doesn't change while scrolling or bouncing.
private struct ScrollViewportProbe: UIViewRepresentable {
    @Binding var height: CGFloat

    func makeUIView(context _: Context) -> ScrollViewportProbeView {
        let view = ScrollViewportProbeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ScrollViewportProbeView, context _: Context) {
        uiView.onChange = { newHeight in
            if abs(height - newHeight) > 0.5 {
                // Resizes after the first measurement follow the keyboard, so they ease along with it.
                withAnimation(height > 0 ? .easeOut(duration: 0.25) : nil) {
                    height = newHeight
                }
            }
        }
        uiView.setNeedsLayout()
    }
}

/// The visible height also excludes whatever the keyboard covers, since the app ignores the keyboard safe area.
final class ScrollViewportProbeView: UIView {
    var onChange: ((CGFloat) -> Void)?

    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private var keyboardObserver: NSObjectProtocol?
    private var keyboardFrame: CGRect = .null
    private var reported: CGFloat?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        observations = []
        scrollView = nil
        reported = nil
        if let keyboardObserver {
            NotificationCenter.default.removeObserver(keyboardObserver)
            self.keyboardObserver = nil
        }
        guard window != nil else { return }

        keyboardFrame = KeyboardHeightCache.shared.screenFrame
        keyboardObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] notification in
            self?.keyboardFrame = notification.keyboardEndFrame
            self?.scheduleMeasure()
        }

        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) {
            ancestor = view.superview
        }
        guard let scrollView = ancestor as? UIScrollView else { return }
        self.scrollView = scrollView

        observations = [
            scrollView.observe(\.frame) { [weak self] _, _ in self?.scheduleMeasure() },
            scrollView.observe(\.bounds) { [weak self] _, _ in self?.scheduleMeasure() },
            scrollView.observe(\.contentInset) { [weak self] _, _ in self?.scheduleMeasure() },
            scrollView.observe(\.contentSize) { [weak self] _, _ in self?.scheduleMeasure() }
        ]
        measure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        measure()
    }

    private func scheduleMeasure() {
        DispatchQueue.main.async { [weak self] in self?.measure() }
    }

    private func measure() {
        guard let scrollView, window != nil else { return }
        let insets = scrollView.adjustedContentInset
        let top = convert(CGPoint.zero, to: scrollView).y
        let bottom = min(scrollView.bounds.height - insets.bottom, keyboardTop(in: scrollView))
        let visible = (bottom - insets.top - top).rounded()
        let height = max(0, visible)
        guard height != reported else { return }
        reported = height
        let onChange = onChange
        DispatchQueue.main.async { onChange?(height) }
    }

    /// The keyboard's top edge measured from the scroll view's top edge. Empty frames come from
    /// a hidden or floating keyboard, which doesn't cover the bottom of the screen.
    private func keyboardTop(in scrollView: UIScrollView) -> CGFloat {
        guard !keyboardFrame.isEmpty, let screen = window?.windowScene?.screen else { return .infinity }
        let frame = scrollView.convert(keyboardFrame, from: screen.coordinateSpace)
        return frame.minY - scrollView.bounds.minY
    }
}

struct GlassSheetHeader: View {
    let title: Text
    var showsBack: Bool = false
    var showsButton: Bool = true
    let action: () -> Void

    var body: some View {
        HStack {
            if showsButton {
                GlassIconButton(systemName: showsBack ? "chevron.left" : "xmark", accessibilityLabel: showsBack ? "Back" : "Close", action: action)
                    .hiddenInSideBar()
            }

            Spacer()
        }
        .frame(height: 44)
        .overlay {
            title
                .font(.app(.title3, weight: .semibold))
                .foregroundColor(Color.PrimaryText)
                .lineLimit(1)
                .padding(.horizontal, 56)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

struct TabHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.app(.title, weight: .semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(.PrimaryText)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            trailing
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 30)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

extension TabHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }
}

extension View {
    func glassField<S: InsettableShape>(in shape: S, isFocused: Bool) -> some View {
        background(shape.fill(Color.PrimaryText.opacity(0.06)))
            .glassBackground(in: shape, tint: Color.glassTint, interactive: false)
            .overlay(shape.strokeBorder(isFocused ? Color.SubtitleText : Color.PrimaryText.opacity(0.1), lineWidth: isFocused ? 2 : 1))
    }

    @ViewBuilder func sheetBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            background(Color.PrimaryBackground)
        }
    }
}

struct GlassIconButton: View {
    let systemName: String
    let accessibilityLabel: LocalizedStringKey
    var foreground: Color = .PrimaryText
    var tint: Color = .glassTint
    var fallback: Color = .SecondaryBackground
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.app(.body, weight: .semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(foreground)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassBackground(in: Circle(), tint: tint, fallback: fallback)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct GlassPopoverBackground: ViewModifier {
    var cornerRadius: CGFloat

    @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var colourScheme: Int = 0
    @Environment(\.colorScheme) var systemColorScheme

    var darkMode: Bool {
        (colourScheme == 0 && systemColorScheme == .dark) || colourScheme == 2
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .glassBackground(in: shape, tint: .glassTint, interactive: false, fallback: darkMode ? Color("AlwaysDarkBackground") : Color("AlwaysLightBackground"))
            .overlay(shape.strokeBorder(Color.PrimaryText.opacity(0.1), lineWidth: 1))
            .shadow(color: Color.black.opacity(darkMode ? 0.3 : 0.12), radius: 16, y: 6)
            .environment(\.colorScheme, darkMode ? .dark : .light)
    }
}

extension View {
    func glassPopoverBackground(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassPopoverBackground(cornerRadius: cornerRadius))
    }
}

struct GlassPopoverMenu<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.vertical, 4)
        .fixedSize(horizontal: true, vertical: false)
        .glassPopoverBackground()
    }
}

struct GlassPopoverRow: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var detail: LocalizedStringKey?
    var isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 18.5

    init(_ title: LocalizedStringKey, systemImage: String? = nil, detail: LocalizedStringKey? = nil, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.app(size: titleSize, weight: .medium))
                        .foregroundColor(Color.SubtitleText)
                        .frame(width: 24)
                }

                Text(title)
                    .font(.app(size: titleSize, weight: .medium))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)

                Spacer(minLength: 16)

                if let detail {
                    Text(detail)
                        .font(.app(size: titleSize))
                        .foregroundColor(Color.SubtitleText)
                        .lineLimit(1)
                }

                Image(systemName: "checkmark")
                    .font(.app(size: titleSize * 0.88, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minWidth: 220, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    @ViewBuilder func scrollDismissesKeyboardInteractively() -> some View {
        if #available(iOS 16.0, *) {
            scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }

    func glassCapsule(interactive: Bool = true) -> some View {
        frame(height: 44)
            .glassBackground(in: Capsule(), tint: .glassTint, interactive: interactive)
            .contentShape(Capsule())
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

private struct GlassCapsuleGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.app(.subheadline, weight: .semibold))
            .foregroundColor(Color.SubtitleText)
    }
}

struct GlassCapsuleButton: View {
    let title: LocalizedStringKey
    let trailingSystemImage: String
    let font: Font
    let action: () -> Void

    init(_ title: LocalizedStringKey, trailingSystemImage: String, font: Font = .app(.body, weight: .medium), action: @escaping () -> Void) {
        self.title = title
        self.trailingSystemImage = trailingSystemImage
        self.font = font
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(font)
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)

                GlassCapsuleGlyph(systemName: trailingSystemImage)
            }
            .padding(.horizontal, 16)
            .glassCapsule()
        }
        .buttonStyle(.plain)
    }
}

struct GlassCapsuleTag: View {
    let title: LocalizedStringKey
    let trailingSystemImage: String
    let trailingAccessibilityLabel: LocalizedStringKey
    let trailingAction: () -> Void

    init(_ title: LocalizedStringKey, trailingSystemImage: String = "xmark", trailingAccessibilityLabel: LocalizedStringKey, trailingAction: @escaping () -> Void) {
        self.title = title
        self.trailingSystemImage = trailingSystemImage
        self.trailingAccessibilityLabel = trailingAccessibilityLabel
        self.trailingAction = trailingAction
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.app(.body, weight: .medium))
                .foregroundColor(Color.PrimaryText)
                .lineLimit(1)

            Button(action: trailingAction) {
                GlassCapsuleGlyph(systemName: trailingSystemImage)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(trailingAccessibilityLabel)
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .glassCapsule()
    }
}

struct GlassStepperCapsule: View {
    var accessibilityTitle: String?
    let previousLabel: LocalizedStringKey
    let nextLabel: LocalizedStringKey
    /// The title `offset` steps from the current one (negative is earlier), or nil past either end.
    let title: (Int) -> String?
    /// Moves by a number of steps; called once per tap, or once when a drag is released.
    let onStep: (Int) -> Void

    @ScaledMetric(relativeTo: .body) private var capsuleWidth: CGFloat = 288

    @State private var isScrubbing = false
    /// The end the drag is held against: 1 for the latest, -1 for the earliest, 0 for neither.
    @State private var pinnedDirection = 0
    /// Accelerated drag distance; positive is rightward, towards earlier dates.
    @State private var travel: CGFloat = 0
    /// Where the drag would land, in steps from the current one.
    @State private var pending = 0
    /// The steps that have a title, found when a drag starts; one gauge tick each.
    @State private var reachable = 0...0
    @State private var isTouching = false
    /// Set when a touch turns out to be a vertical drag, so it never becomes a scrub.
    @State private var ignoresTouch = false
    @State private var pressTimer: DispatchWorkItem?
    @State private var latestTranslation: CGFloat = 0
    @State private var lastTranslation: CGFloat = 0
    @State private var lastSampleTime = Date.distantPast
    @State private var scrubStart = Date.distantPast
    /// Distance moved since the scrub began, used to ease in its first stretch.
    @State private var warmup: CGFloat = 0
    @State private var lastScrubEnd = Date.distantPast
    @State private var haptics = StepperHaptics()

    /// Drag distance per step at slow speeds, and the spacing of the gauge ticks.
    private let tickSpacing: CGFloat = 9
    private let scrubSpring = Animation.spring(response: 0.38, dampingFraction: 0.78)

    var body: some View {
        let restingWidth = min(capsuleWidth, UIScreen.main.bounds.width - 32)
        let scrubbingWidth = min(capsuleWidth + 56, UIScreen.main.bounds.width - 32)
        let currentTitle = title(0) ?? ""

        HStack(spacing: 8) {
            chevron("chevron.left", label: previousLabel, enabled: title(-1) != nil) { onStep(-1) }

            VStack(spacing: 6) {
                Text(isScrubbing ? title(pending) ?? currentTitle : currentTitle)
                    .font(.app(.body, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .monospacedDigit()
                    .padding(.horizontal, 4)
                    .accessibilityLabel(accessibilityTitle ?? currentTitle)

                if isScrubbing {
                    gauge
                        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .top)))
                }
            }
            .frame(maxWidth: .infinity)

            chevron("chevron.right", label: nextLabel, enabled: title(1) != nil) { onStep(1) }
        }
        .padding(4)
        .frame(width: isScrubbing ? scrubbingWidth : restingWidth, height: isScrubbing ? 66 : 44)
        .glassBackground(in: Capsule(), tint: .glassTint)
        .contentShape(Capsule())
        .simultaneousGesture(scrubGesture)
        .frame(width: restingWidth, height: 44, alignment: .bottom)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    var gauge: some View {
        Canvas { context, size in
            let mid = size.width / 2
            // Tick `step` sits at `mid + step * tickSpacing + travel`, so earlier steps lie to the left.
            let first = max(reachable.lowerBound, Int(((-mid - travel) / tickSpacing).rounded(.down)))
            let last = min(reachable.upperBound, Int(((mid - travel) / tickSpacing).rounded(.up)))
            guard first <= last else { return }

            for step in first...last {
                let x = mid + CGFloat(step) * tickSpacing + travel
                let isCentre = step == pending
                let closeness = max(0, 1 - abs(x - mid) / mid)
                let height = isCentre ? 12 : 3 + 6 * closeness * closeness
                let width: CGFloat = isCentre ? 2 : 1.5
                let tick = CGRect(x: x - width / 2, y: (size.height - height) / 2, width: width, height: height)
                let opacity = isCentre ? 1 : 0.08 + 0.27 * closeness
                context.fill(Path(roundedRect: tick, cornerRadius: width / 2), with: .color(Color.PrimaryText.opacity(opacity)))
            }
        }
        .frame(height: 12)
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.25),
                .init(color: .black, location: 0.75),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        }
        .padding(.horizontal, -24)
        .accessibilityHidden(true)
    }

    var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let now = Date()
                latestTranslation = value.translation.width

                if !isTouching {
                    isTouching = true
                    ignoresTouch = false
                    haptics.prepare()
                    let press = DispatchWorkItem {
                        if isTouching && !ignoresTouch && !isScrubbing {
                            beginScrub()
                        }
                    }
                    pressTimer = press
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: press)
                    return
                }

                guard isScrubbing else {
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    guard !ignoresTouch, max(horizontal, vertical) > 8 else { return }
                    if horizontal > vertical {
                        beginScrub()
                    } else {
                        // A vertical drag belongs to whatever is behind the island.
                        ignoresTouch = true
                        pressTimer?.cancel()
                    }
                    return
                }

                let delta = value.translation.width - lastTranslation
                let elapsed = max(now.timeIntervalSince(lastSampleTime), 1 / 120)
                lastTranslation = value.translation.width
                lastSampleTime = now

                // Flicking speeds up the steps, so long ranges cross in one swipe while slow drags stay precise.
                let speed = abs(delta) / CGFloat(elapsed)
                let gain = 1 + min(max(speed - 250, 0) / 400, 4)

                // Ease in the first stretch of movement so the gauge is in place before dates start moving.
                warmup += abs(delta)
                let settle = min(1, CGFloat(now.timeIntervalSince(scrubStart)) / 0.2)
                let ease = min(settle, warmup / 18)
                scrub(by: delta * gain * ease * ease)
            }
            .onEnded { _ in
                isTouching = false
                pressTimer?.cancel()
                pressTimer = nil
                guard isScrubbing else { return }

                let steps = pending
                lastScrubEnd = Date()
                if steps != 0 {
                    haptics.light.impactOccurred()
                }
                withAnimation(scrubSpring) {
                    isScrubbing = false
                    pinnedDirection = 0
                    travel = 0
                    pending = 0
                }
                if steps != 0 {
                    onStep(steps)
                }
            }
    }

    /// Expands the island and shows the gauge, from a long press or the start of a sideways drag.
    func beginScrub() {
        let now = Date()
        lastTranslation = latestTranslation
        lastSampleTime = now
        scrubStart = now
        warmup = 0
        reachable = limit(towards: -1)...limit(towards: 1)
        haptics.soft.impactOccurred(intensity: 0.7)
        haptics.prepare()
        withAnimation(scrubSpring) {
            isScrubbing = true
        }
    }

    /// Dragging right travels back in time, like pulling earlier dates into view.
    func scrub(by distance: CGFloat) {
        if distance * CGFloat(pinnedDirection) > 0 {
            pinnedDirection = 0
        }

        var next = travel + distance
        let target = -Int((next / tickSpacing).rounded())
        let reached = min(max(target, reachable.lowerBound), reachable.upperBound)

        if reached != target {
            // Hold the gauge just shy of the step past the end.
            let direction = target > reached ? 1 : -1
            next = -CGFloat(reached) * tickSpacing - CGFloat(direction) * tickSpacing * 0.4
            if pinnedDirection != direction {
                pinnedDirection = direction
                haptics.rigid.impactOccurred(intensity: 0.8)
                haptics.rigid.prepare()
            }
        }

        travel = next
        if reached != pending {
            pending = reached
            haptics.tick()
        }
    }

    /// The furthest step with a title in one direction, found by doubling then halving so long histories stay cheap.
    func limit(towards direction: Int) -> Int {
        var found = 0
        var missing: Int?
        var probe = 1

        while missing == nil, probe <= 1 << 16 {
            if title(probe * direction) != nil {
                found = probe
                probe *= 2
            } else {
                missing = probe
            }
        }

        guard var missing else { return found * direction }
        while missing - found > 1 {
            let middle = (found + missing) / 2
            if title(middle * direction) != nil {
                found = middle
            } else {
                missing = middle
            }
        }
        return found * direction
    }

    func chevron(_ systemName: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            // A drag that starts on a chevron can end as a tap on it.
            guard !isScrubbing, Date().timeIntervalSince(lastScrubEnd) > 0.3 else { return }
            haptics.tick()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.app(.subheadline, weight: .semibold))
                .foregroundColor(Color.PrimaryText)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(StepperChevronButtonStyle())
        .opacity(isScrubbing ? 0 : (enabled ? 1 : 0.3))
        .scaleEffect(isScrubbing ? 0.6 : 1)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The stepper's feedback generators, kept warm so the first tick isn't late.
private final class StepperHaptics {
    let selection = UISelectionFeedbackGenerator()
    let soft = UIImpactFeedbackGenerator(style: .soft)
    let rigid = UIImpactFeedbackGenerator(style: .rigid)
    let light = UIImpactFeedbackGenerator(style: .light)
    private var lastTick = Date.distantPast

    func prepare() {
        selection.prepare()
        soft.prepare()
        rigid.prepare()
        light.prepare()
    }

    /// Fast flicks can cross a step on every touch update; spacing the ticks keeps them crisp instead of a buzz.
    func tick() {
        let now = Date()
        guard now.timeIntervalSince(lastTick) > 0.03 else { return }
        lastTick = now
        selection.selectionChanged()
        selection.prepare()
    }
}

/// Shows the circle behind a chevron only while it's pressed.
private struct StepperChevronButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Color.PrimaryText.opacity(configuration.isPressed ? 0.1 : 0)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GlassToast: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 6.5) {
            Image(systemName: systemImage)
                .font(.app(.subheadline, weight: .semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            Text(LocalizedStringKey(title))
                .font(.app(.body, weight: .semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Capsule().fill(color.opacity(0.12)))
        .glassBackground(in: Capsule(), tint: color.opacity(0.25), interactive: false, fallback: color.opacity(0.23))
        .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
        .frame(maxWidth: 280)
        .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
    }
}

struct SectionHeaderButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var color: Color = .SubtitleText
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.app(.subheadline, weight: .semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(color)
                .frame(width: 44, height: 32, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct GlassSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey)]

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.title)
                        .font(.app(.body, weight: .semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .lineLimit(1)
                        .foregroundColor(isSelected ? Color.PrimaryText : Color.SubtitleText)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.PrimaryText.opacity(0.18))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .glassBackground(in: Capsule(), tint: .glassTint)
    }
}

// MARK: - Date picker

/// A calendar that scrolls through the weeks without month pages, plus an optional time row that uses the system
/// time picker. Plain numerals, one filled circle on the chosen day and a dot under today; the month's name sits
/// between the rows above each 1st. Weeks start on the app's `firstWeekday` setting; days outside `range` are
/// dimmed and can't be picked.
struct GlassDatePicker: View {
    @Binding var selection: Date
    let range: ClosedRange<Date>?
    let showsTime: Bool
    let visibleWeeks: Int
    /// Called after a day is tapped, even when it was already chosen. Time changes don't call it.
    let onPick: () -> Void

    private let calendar: Calendar
    /// The first day of every week the calendar can scroll to. Worked out once, so picking a day doesn't move the rows.
    @State private var weeks: [Date]

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 18.5

    static var rowHeight: CGFloat { 46 }
    /// Room above the top row for a month name that sits on that row's top edge.
    static var labelOverhang: CGFloat { 5 }
    /// Lines the time row's text up with the numerals in the calendar's outer columns.
    static var edgeInset: CGFloat { 14 }

    init(
        selection: Binding<Date>,
        in range: ClosedRange<Date>? = nil,
        showsTime: Bool = false,
        visibleWeeks: Int = 6,
        onPick: @escaping () -> Void = {}
    ) {
        _selection = selection
        self.range = range
        self.showsTime = showsTime
        self.visibleWeeks = visibleWeeks
        self.onPick = onPick

        var calendar = Calendar.current
        let firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.integer(forKey: "firstWeekday") ?? 0
        if (1 ... 7).contains(firstWeekday) {
            calendar.firstWeekday = firstWeekday
        }
        self.calendar = calendar

        // Without a range the calendar reaches five years back and two years ahead of today and the chosen day.
        let chosen = selection.wrappedValue
        let lower = range?.lowerBound ?? calendar.date(byAdding: .year, value: -5, to: min(chosen, Date.now)) ?? chosen
        let upper = range?.upperBound ?? calendar.date(byAdding: .year, value: 2, to: max(chosen, Date.now)) ?? chosen
        let first = Self.startOfWeek(lower, calendar)
        let days = calendar.dateComponents([.day], from: first, to: Self.startOfWeek(upper, calendar)).day ?? 0
        _weeks = State(initialValue: (0 ... max(0, days / 7)).compactMap { calendar.date(byAdding: .day, value: $0 * 7, to: first) })
    }

    static func startOfWeek(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func isSelectable(_ day: Date, _ range: ClosedRange<Date>?, _ calendar: Calendar) -> Bool {
        guard let range else { return true }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        return start <= range.upperBound && end > range.lowerBound
    }

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader

            weeksView

            if showsTime {
                timeRow
                    .padding(.top, 8)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: Calendar

    var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols

        return HStack(spacing: 0) {
            ForEach(0 ..< 7, id: \.self) { column in
                Text(symbols[(calendar.firstWeekday - 1 + column) % 7])
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundColor(Color.SubtitleText)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }

    /// Opens with the chosen day's week on the bottom row, so the weeks before it are already in view.
    var weeksView: some View {
        ScrollViewReader { reader in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(weeks, id: \.self) { week in
                        weekRow(week)
                            .id(week)
                    }
                }
                .padding(.top, Self.labelOverhang)
            }
            .frame(height: Self.labelOverhang + Self.rowHeight * CGFloat(visibleWeeks))
            .snapsToRows(height: Self.rowHeight)
            .onAppear {
                reader.scrollTo(Self.startOfWeek(selection, calendar), anchor: .bottom)
            }
        }
    }

    func weekRow(_ week: Date) -> some View {
        let days = (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: week) }
        let firstOfMonth = days.firstIndex { calendar.component(.day, from: $0) == 1 }

        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
        .overlay {
            if let column = firstOfMonth {
                MonthTitle(column: column, title: monthTitle(days[column]))
                    .opacity(Self.isSelectable(days[column], range, calendar) ? 1 : 0.25)
            }
        }
    }

    func dayCell(_ day: Date) -> some View {
        let number = calendar.component(.day, from: day)
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let enabled = Self.isSelectable(day, range, calendar)

        return Text("\(number)")
            .font(.app(size: 19, weight: isSelected || isToday ? .semibold : .regular))
            .monospacedDigit()
            .foregroundColor(isSelected ? Color.LightIcon : Color.PrimaryText)
            .frame(maxWidth: .infinity)
            .frame(height: Self.rowHeight)
            // Leaves `labelOverhang` clear above and below, where month names sit on the row edges.
            .background {
                Circle()
                    .fill(Color.DarkBackground)
                    .frame(width: 36, height: 36)
                    .opacity(isSelected ? 1 : 0)
            }
            .overlay {
                Circle()
                    .fill(Color.PrimaryText)
                    .frame(width: 4, height: 4)
                    .offset(y: 13)
                    .opacity(isToday && !isSelected ? 1 : 0)
            }
        .opacity(enabled ? 1 : 0.25)
        .contentShape(Rectangle())
        // A tap gesture, not a button: in a sheet a button still fires after a scroll starts on it (FB18927179).
        .onTapGesture {
            pick(day)
        }
        .disabled(!enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The name above the 1st: the short month name, or the year where a new year starts.
    func monthTitle(_ day: Date) -> String {
        if calendar.component(.month, from: day) == 1 {
            return day.formatted(.dateTime.year())
        }
        // Some languages end the short name with a full stop ("nov."), which the label doesn't need.
        return day.formatted(.dateTime.month(.abbreviated)).trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()
    }

    func pick(_ day: Date) {
        let time = calendar.dateComponents([.hour, .minute, .second], from: selection)
        guard var date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) else { return }
        if let range {
            date = min(max(date, range.lowerBound), range.upperBound)
        }

        UISelectionFeedbackGenerator().selectionChanged()
        selection = date
        onPick()
    }

    // MARK: Time

    var timeRow: some View {
        HStack(spacing: 12) {
            Text("Time")
                .font(.app(size: titleSize, weight: .medium))
                .foregroundColor(Color.PrimaryText)
                .lineLimit(1)

            Spacer(minLength: 16)

            timePicker
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Color.PrimaryText)
        }
        .padding(.horizontal, Self.edgeInset)
        .frame(height: 52)
    }

    @ViewBuilder var timePicker: some View {
        if let range {
            DatePicker("Time", selection: $selection, in: range, displayedComponents: .hourAndMinute)
        } else {
            DatePicker("Time", selection: $selection, displayedComponents: .hourAndMinute)
        }
    }
}

/// The month's name over the 1st, centred on the row's top edge so the numerals stay in line.
private struct MonthTitle: View {
    let column: Int
    let title: String

    var body: some View {
        GeometryReader { proxy in
            Text(title)
                .font(.app(size: 11, weight: .semibold))
                .foregroundColor(Color.SubtitleText)
                .lineLimit(1)
                .fixedSize()
                .position(x: proxy.size.width / 7 * (CGFloat(column) + 0.5), y: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Makes a vertical scroll view of equal-height rows come to rest on a whole row.
@available(iOS 17.0, *)
private struct RowSnapping: ScrollTargetBehavior {
    let height: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context _: TargetContext) {
        target.rect.origin.y = (target.rect.origin.y / height).rounded() * height
    }
}

private extension View {
    @ViewBuilder func snapsToRows(height: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            scrollTargetBehavior(RowSnapping(height: height))
        } else {
            self
        }
    }
}

extension Color {
    static let glassTint = Color.PrimaryText.opacity(0.1)
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
