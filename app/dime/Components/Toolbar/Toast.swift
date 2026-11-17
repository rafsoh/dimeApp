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
