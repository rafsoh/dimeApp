//
//  SettingsSubviewModifier.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI

extension CGFloat {
    static let settingsRowHeight: CGFloat = 48
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .settingsNavigationBar(hidden: false)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func insetContent(_ content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .top)
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
        background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
