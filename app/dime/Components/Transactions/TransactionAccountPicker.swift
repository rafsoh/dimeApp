//
//  TransactionAccountPicker.swift
//  dime
//

import Foundation
import SwiftUI

struct NewAccountPickerView: View {
    @Binding var account: Account?
    @Binding var showPicker: Bool
    @Binding var showingAccountView: Bool
    @FetchRequest(sortDescriptors: [SortDescriptor(\.order, order: .reverse)]) private var accounts: FetchedResults<Account>
    @Environment(\.colorScheme) var colorScheme

    let layout = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: layout, spacing: 10) {
                ForEach(accounts) { item in
                    HStack(spacing: 7) {
                        Text(item.wrappedEmoji)
                            .font(.system(.subheadline, design: .rounded))

                        Text(item.wrappedName)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                    }
                    .id(item.id)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .foregroundColor(Color(hex: item.wrappedColour))
                    .background(
                        Color(hex: item.wrappedColour).opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                    )
                    .contentShape(Rectangle())
                    .overlay {
                        if item == account {
                            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                .strokeBorder(Color(hex: item.wrappedColour),
                                              style: StrokeStyle(lineWidth: 2))
                        }
                    }
                    .onTapGesture {
                        withAnimation {
                            if account == item {
                                account = nil
                            } else {
                                account = item
                            }
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation {
                                showPicker = false
                            }
                        }
                    }
                    .opacity(account != nil ? (account == item ? 1 : 0.5) : 1)
                }
            }
        }
        .keyboardAwareHeight(showToolbar: false)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .overlay(alignment: .bottom) {
            HStack(spacing: 4) {
                Image(systemName: "pencil")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text("Edit")
                    .font(.system(.body, design: .rounded).weight(.semibold))
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 18)
            .foregroundColor(Color.SubtitleText)
            .background(
                RoundedRectangle(cornerRadius: 11.5, style: .continuous).fill(Color.SecondaryBackground).shadow(
                    color: colorScheme == .light ? Color.Outline : Color.clear, radius: 6)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                let impactMed = UIImpactFeedbackGenerator(style: .light)
                impactMed.impactOccurred()
                showPicker = false
                showingAccountView = true
            }
            .padding(.bottom, 15)
        }
    }
}
