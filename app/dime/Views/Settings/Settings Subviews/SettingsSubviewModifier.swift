//
//  SettingsSubviewModifier.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI

/// The Settings page's section style, shared by every page built from sections.
extension CGFloat {
    static let settingsRowHeight: CGFloat = 48
    /// From the screen edge to a section's edge.
    static let settingsPageInset: CGFloat = 16
    /// From a section's edge to its rows, header and footer text.
    static let settingsRowInset: CGFloat = 14
    static let settingsSectionRadius: CGFloat = 22
    /// Between one section and the next when the next has no header.
    static let settingsSectionSpacing: CGFloat = 25
    /// Between one section and the next section's header.
    static let settingsHeaderSpacing: CGFloat = 25
}

struct SettingsSubviewModifier: ViewModifier {
    let title: LocalizedStringKey
    var scrollable: Bool = true

    func body(content: Content) -> some View {
        Group {
            if scrollable {
                ScrollView(showsIndicators: false) {
                    insetContent(content)
                }
                .tabBarClearance()
            } else {
                insetContent(content)
                    .padding(.bottom, 20)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.PrimaryBackground.ignoresSafeArea())
        .modifier(SettingsPageHeader(title: title))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func insetContent(_ content: Content) -> some View {
        content
            .padding(.horizontal, .settingsPageInset)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// A pushed Settings page's header. Settings never shows the system navigation bar: when it appears for a pushed page,
/// it takes over the top scroll edge effect of the page beneath, which drops out while popping back to the root.
struct SettingsPageHeader: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    let title: LocalizedStringKey

    func body(content: Content) -> some View {
        content
            .tabHeader {
                GlassSheetHeader(title: Text(title), showsBack: true) {
                    dismiss()
                }
            }
            .settingsNavigationBar(hidden: true)
    }
}

extension View {
    @ViewBuilder func settingsNavigationBar(hidden: Bool) -> some View {
        if #available(iOS 16.0, *) {
            toolbar(hidden ? .hidden : .visible, for: .navigationBar)
        } else {
            navigationBarHidden(hidden)
        }
    }

    func settingsSectionBackground() -> some View {
        background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: .settingsSectionRadius, style: .continuous))
    }

    /// Insets a section's rows and draws its background.
    func settingsSectionRows() -> some View {
        padding(.horizontal, .settingsRowInset)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .settingsSectionBackground()
    }
}

struct SettingsSectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(Color.SubtitleText)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, .settingsRowInset)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

extension SettingsSectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }
}

struct SettingsSectionFooter: View {
    let text: Text

    init(_ text: LocalizedStringKey) {
        self.text = Text(text)
    }

    init(verbatim text: String) {
        self.text = Text(text)
    }

    var body: some View {
        text
            .font(.system(.footnote, design: .rounded).weight(.medium))
            .foregroundColor(Color.SubtitleText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, .settingsRowInset)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
