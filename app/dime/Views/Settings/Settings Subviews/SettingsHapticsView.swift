//
//  SettingsHapticsView.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI

struct SettingsHapticsView: View {
    @AppStorage("haptics", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var hapticType: Int = 1
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    let options = ["None", "Subtle", "Excessive"]

    @Namespace var animation

    @State var shake: Bool = false
    @State var alternateShake: Bool = false

    @State var wordShake: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { option in
                    HStack {
                        Text(LocalizedStringKey(options[option]))
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(Color.PrimaryText)

                        Spacer()

                        if hapticType == option {
                            Image(systemName: "checkmark")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundColor(.DarkIcon.opacity(0.6))
                                .matchedGeometryEffect(id: "tick", in: animation)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: .settingsRowHeight)
                    .contentShape(Rectangle())
                    .offset(x: wordShake && option == 1 ? -5 : 0)
                    .onTapGesture {
                        withAnimation(.easeIn(duration: 0.15)) {
                            hapticType = option
                        }

//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
//                            self.presentationMode.wrappedValue.dismiss()
//                        }
                    }
                    .overlay(alignment: .bottom) {
                        if option < (options.count - 1) {
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .settingsSectionBackground()
            .offset(x: shake ? -5 : 5)
            .offset(x: alternateShake ? 0 : -5)

            Text("The 'Excessive' mode makes the entire numpad haptic.")
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundColor(Color.SubtitleText)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(SettingsSubviewModifier(title: "Haptic Feedback"))
        .onChange(of: hapticType) { newValue in
            if newValue == 2 {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

                withAnimation(.easeInOut(duration: 0.1)) {
                    alternateShake = true
                }
                withAnimation(.easeInOut(duration: 0.1).repeatCount(5)) {
                    shake = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        shake = false
                        alternateShake = false
                    }
                }
            } else if newValue == 1 {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                withAnimation(.easeInOut(duration: 0.1).repeatCount(5)) {
                    wordShake = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        wordShake = false
                    }
                }
            }
        }
    }
}
