import SwiftUI

struct ToolbarButton: View {
    var systemName: String
    var onTapGesture: (() -> Void)?

    var body: some View {
        Circle()
            .fill(Color.SecondaryBackground)
            .frame(width: 33, height: 33)
            .overlay {
                Image(systemName: systemName)
                    .font(.app(.callout, weight: .semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundColor(Color.SubtitleText)
                    .offset(y: 0.8)
            }
            .onTapGesture {
                onTapGesture?()
            }
    }
}
