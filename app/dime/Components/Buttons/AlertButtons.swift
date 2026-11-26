//
//  File.swift
//  dime
//
//  Created by Rafael Soh on 4/11/23.
//

import Foundation
import SwiftUI

private struct ConfirmationSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ConfirmationSheet<Actions: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var systemImage: String?
    let actions: Actions

    @State private var contentHeight: CGFloat = 0

    init(title: LocalizedStringKey, message: LocalizedStringKey, systemImage: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents(detents)
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }

    @available(iOS 16.0, *)
    var detents: Set<PresentationDetent> {
        if contentHeight == 0 {
            return [.height(260)]
        } else if contentHeight > UIScreen.main.bounds.height * 0.9 {
            return [.large]
        } else {
            return [.height(contentHeight)]
        }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.app(.callout, weight: .semibold))
                }

                Text(title)
                    .font(.app(.title3, weight: .semibold))
            }
            .foregroundColor(Color.PrimaryText)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.app(.body))
                .foregroundColor(Color.SubtitleText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(spacing: 10) {
                actions
            }
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ConfirmationSheetHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(ConfirmationSheetHeightKey.self) { height in
            contentHeight = height
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheetBackground()
    }
}

struct ConfirmationDestructiveButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey = "Delete", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.app(.body, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassBackground(in: Capsule(), tint: Color.AlertRed, fallback: Color.AlertRed)
    }
}

struct ConfirmationCancelButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey = "Cancel", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.app(.body, weight: .semibold))
                .foregroundColor(Color.PrimaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassBackground(in: Capsule(), tint: Color.glassTint)
    }
}

extension View {
    func confirmationSheet(
        isPresented: Binding<Bool>,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        destructiveTitle: LocalizedStringKey = "Delete",
        onDismiss: (() -> Void)? = nil,
        onConfirm: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            ConfirmationSheet(title: title, message: message) {
                ConfirmationDestructiveButton(destructiveTitle) {
                    isPresented.wrappedValue = false
                    onConfirm()
                }

                ConfirmationCancelButton {
                    isPresented.wrappedValue = false
                }
            }
        }
    }

    func confirmationSheet<Item: Identifiable>(
        item: Binding<Item?>,
        title: @escaping (Item) -> LocalizedStringKey,
        message: @escaping (Item) -> LocalizedStringKey,
        destructiveTitle: LocalizedStringKey = "Delete",
        onDismiss: (() -> Void)? = nil,
        onConfirm: @escaping (Item) -> Void
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { presented in
            ConfirmationSheet(title: title(presented), message: message(presented)) {
                ConfirmationDestructiveButton(destructiveTitle) {
                    item.wrappedValue = nil
                    onConfirm(presented)
                }

                ConfirmationCancelButton {
                    item.wrappedValue = nil
                }
            }
        }
    }
}
