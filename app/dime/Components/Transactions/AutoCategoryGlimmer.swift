//
//  AutoCategoryGlimmer.swift
//  dime
//
//  What a log row looks like while Apple Intelligence picks its category.
//

import SwiftUI

/// The glimmer's colours, after Apple Intelligence's.
enum AutoCategoryGlimmerStyle {
    static let colours: [Color] = [
        Color(hex: "FFB36B"),
        Color(hex: "FF6B8A"),
        Color(hex: "D17CFF"),
        Color(hex: "8C8CFF"),
        Color(hex: "5FC9FF"),
    ]

    /// The colours around a ring, ending where they start so there's no seam.
    static var ring: Gradient {
        Gradient(colors: colours + [colours[0]])
    }

    #if DEBUG
    /// Screenshots only: `-autoCategoryGlimmerPhase 0.4` holds the glimmer at that point of its sweep.
    static let heldPhase: Double? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-autoCategoryGlimmerPhase"), index + 1 < arguments.count else {
            return nil
        }
        return Double(arguments[index + 1])
    }()
    #else
    static let heldPhase: Double? = nil
    #endif
}

extension View {
    /// Sweeps a band of colour through the view's text and shapes, over a soft tint, while active.
    func autoCategoryGlimmer(_ isActive: Bool, cornerRadius: CGFloat = 14) -> some View {
        modifier(AutoCategoryGlimmer(isActive: isActive, cornerRadius: cornerRadius))
    }
}

private struct AutoCategoryGlimmer: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LinearGradient(colors: AutoCategoryGlimmerStyle.colours, startPoint: .leading, endPoint: .trailing))
                        .opacity(0.1)
                        .transition(.opacity)
                }
            }
            .overlay {
                if isActive {
                    // Masked by the row itself, so only its text and shapes catch the light.
                    GlimmerBand(reduceMotion: reduceMotion)
                        .mask { content }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: isActive)
    }
}

private struct GlimmerBand: View {
    let reduceMotion: Bool

    /// Seconds for the band to cross the row.
    private static let period = 1.8

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            GeometryReader { proxy in
                if reduceMotion {
                    // A slow fade in and out instead of a sweep.
                    LinearGradient(colors: AutoCategoryGlimmerStyle.colours, startPoint: .leading, endPoint: .trailing)
                        .opacity(0.35 + 0.3 * sin(time * 2.2))
                } else {
                    let band = max(proxy.size.width * 0.5, 140)
                    let progress = CGFloat(AutoCategoryGlimmerStyle.heldPhase ?? time.truncatingRemainder(dividingBy: Self.period) / Self.period)

                    LinearGradient(colors: [.clear] + AutoCategoryGlimmerStyle.colours + [.clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: band)
                        .offset(x: -band + progress * (proxy.size.width + band))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A ring of colour turning around a category tile while Apple Intelligence picks the category.
struct AutoCategoryTileRing: View {
    var cornerRadius: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let degrees = AutoCategoryGlimmerStyle.heldPhase.map { $0 * 360 } ?? (timeline.date.timeIntervalSinceReferenceDate * 200).truncatingRemainder(dividingBy: 360)
            let gradient = AngularGradient(gradient: AutoCategoryGlimmerStyle.ring, center: .center, angle: .degrees(degrees))
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            shape
                .strokeBorder(gradient, lineWidth: 2)
                .background {
                    shape
                        .strokeBorder(gradient, lineWidth: 4)
                        .blur(radius: 5)
                        .opacity(0.8)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
