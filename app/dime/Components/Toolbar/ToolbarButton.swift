import SwiftUI

struct ToolbarButton: View {
    var systemName: String
    var accessibilityLabel: String?
    var onTapGesture: (() -> Void)?

    var body: some View {
        let button = Button {
            onTapGesture?()
        } label: {
            Image(systemName: systemName)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(Color.SubtitleText)
                .offset(y: 0.8)
                .frame(width: 33, height: 33)
                .contentShape(Circle())
                .dimeGlass(in: Circle(), interactive: true, fallback: Color.SecondaryBackground)
        }
        .buttonStyle(.plain)

        // only override the voiceover label when the caller provides one
        if let accessibilityLabel {
            button.accessibilityLabel(accessibilityLabel)
        } else {
            button
        }
    }
}
