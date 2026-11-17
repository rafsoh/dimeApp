import SwiftUI

struct Toast: View {
    @Binding var showToast: Bool
    @Binding var toastTitle: String
    @Binding var toastImage: String
    @Binding var toastColor: Color

    var body: some View {
        if showToast {
            HStack(spacing: 6.5) {
                Image(systemName: toastImage)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundColor(toastColor)

                Text(toastTitle)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .lineLimit(1)
                    .foregroundColor(toastColor)
            }
            .padding(8)
            .dimeGlass(
                RoundedRectangle(cornerRadius: 9, style: .continuous),
                fallback: toastColor.opacity(0.23),
                tint: toastColor.opacity(0.18)
            )
            .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
            .frame(maxWidth: 250)
            .frame(height: 35)
            .padding(20)
        }
    }
}

/// A glass HUD at the top of the screen: icon, title and subtitle. Hides itself after `duration`;
/// tapping it runs `onTap` instead of `onTimeout` (used for "Log Deleted — tap to undo").
struct HUDToast: ViewModifier {
    @Binding var isPresented: Bool
    var duration: Double = 4
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var onTap: (() -> Void)?
    var onTimeout: (() -> Void)?

    @State private var timer: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    Button {
                        timer?.cancel()
                        onTap?()
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented = false
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .foregroundColor(tint)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(LocalizedStringKey(title))
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundColor(Color.PrimaryText)
                                Text(LocalizedStringKey(subtitle))
                                    .font(.system(.caption, design: .rounded).weight(.medium))
                                    .foregroundColor(Color.SubtitleText)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .dimeGlass(Capsule(), fallback: Color.SecondaryBackground, interactive: true)
                        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPresented)
            .onChange(of: isPresented) { shown in
                timer?.cancel()
                guard shown else { return }
                UIAccessibility.post(notification: .announcement, argument: NSLocalizedString(title, comment: "") + ", " + NSLocalizedString(subtitle, comment: ""))
                let work = DispatchWorkItem {
                    onTimeout?()
                    isPresented = false
                }
                timer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
            }
    }
}

extension View {
    func hudToast(
        isPresented: Binding<Bool>, duration: Double = 4, icon: String, tint: Color,
        title: String, subtitle: String,
        onTap: (() -> Void)? = nil, onTimeout: (() -> Void)? = nil
    ) -> some View {
        modifier(HUDToast(isPresented: isPresented, duration: duration, icon: icon, tint: tint, title: title, subtitle: subtitle, onTap: onTap, onTimeout: onTimeout))
    }
}
