import SwiftUI

struct ToolbarButton: View {
    var systemName: String
    var onTapGesture: (() -> Void)?

    var body: some View {
        Button {
            onTapGesture?()
        } label: {
            Image(systemName: systemName)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(Color.SubtitleText)
                .offset(y: 0.8)
                .frame(width: 33, height: 33)
                .dimeGlass(Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
