//
//  SettingsShortcutView.swift
//  dime
//
//  Created by Claude on 12/2/26.
//

import AppIntents
import Foundation
import SwiftUI

struct SettingsShortcutView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Quick Log")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(Color.PrimaryText)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    Button {
                        self.presentationMode.wrappedValue.dismiss()
                    } label: {
                        SettingsBackButton()
                    }
                }
                .padding(.bottom, 30)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Hero card
                    VStack(spacing: 16) {
                        Image(systemName: "bolt.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.orange)
                            .padding(.top, 8)

                        Text("Quick Log Shortcut")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.PrimaryText)

                        Text("Add this shortcut to quickly log transactions after a payment. Dime will save the amount and remind you to categorize it later.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(Color.SubtitleText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 15)
                    .frame(maxWidth: .infinity)
                    .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 12))

                    // Steps card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("HOW IT WORKS")
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)

                        StepRow(number: "1", icon: "hand.tap.fill", text: "Tap \"Add to Shortcuts\" below")
                        StepRow(number: "2", icon: "bolt.fill", text: "Select \"Quick Log Transaction\" in Shortcuts")
                        StepRow(number: "3", icon: "square.grid.2x2.fill", text: "Add it to Home Screen or set as Automation")
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 12))

                    // Usage tips card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("AFTER SETUP")
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)

                        HStack(spacing: 12) {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.green)
                                .frame(width: 24)
                            Text("Run the shortcut after a payment — enter only the amount")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundColor(Color.PrimaryText)
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("A notification appears — tap it to categorize the transaction")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundColor(Color.PrimaryText)
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            Text("Done! No more forgotten expenses")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundColor(Color.PrimaryText)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 12))

                    Spacer().frame(height: 10)

                    // Add to Shortcuts button
                    if #available(iOS 16.4, *) {
                        ShortcutsLink()
                            .shortcutsLinkStyle(.automaticOutline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    } else {
                        Button {
                            // Fallback: open Shortcuts app
                            if let url = URL(string: "shortcuts://") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open Shortcuts App")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Spacer().frame(height: 80)
                }
            }
        }
        .modifier(SettingsSubviewModifier())
    }
}

private struct StepRow: View {
    let number: String
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.DarkIcon.opacity(0.6), in: Circle())

            Image(systemName: icon)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(Color.DarkIcon.opacity(0.7))
                .frame(width: 20)

            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(Color.PrimaryText)
        }
    }
}
