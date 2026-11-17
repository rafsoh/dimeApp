//
//  TransactionCategoryPicker.swift
//  dime
//
//  Created by Rafael Soh on 20/11/23.
//

import Foundation
import SwiftUI

struct NewCategoryPickerView: View {
    @Binding var category: Category?
    @Binding var showPicker: Bool
    @Binding var showingCategoryView: Bool
    @FetchRequest private var categories: FetchedResults<Category>
    @Environment(\.colorScheme) var colorScheme

    // compact tiles: four per row, so ~16 categories fit without scrolling
    let layout = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: layout, spacing: 8) {
                ForEach(categories) { item in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation {
                            category = item
                            showPicker = false
                        }
                    } label: {
                        VStack(spacing: 4) {
                            CategoryIcon(item.wrappedIcon)
                                .font(.system(.title2, design: .rounded))

                            Text(item.wrappedName)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundColor(Color.PrimaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 66)
                        .background(
                            Color(hex: item.wrappedColour).opacity(item == category ? 0.4 : 0.18),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .overlay {
                            if item == category {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(Color(hex: item.wrappedColour), lineWidth: 2)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .id(item.id)
                    .accessibilityLabel(Text(item.wrappedName))
                    .accessibilityAddTraits(item == category ? .isSelected : [])
                }
            }
            .padding(.bottom, 60) // room above the Edit button
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
                    color: colorScheme == .light ? Color.Outline  : Color.clear, radius: 6)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                let impactMed = UIImpactFeedbackGenerator(style: .light)
                impactMed.impactOccurred()
                showPicker = false
                showingCategoryView = true
            }
            .padding(.bottom, 15)
        }
    }

    init(
        category: Binding<Category?>?, showPicker: Binding<Bool>, showSheet: Binding<Bool>,
        income: Bool
    ) {
        _categories = FetchRequest<Category>(
            sortDescriptors: [
                SortDescriptor(\.order, order: .reverse)
            ], predicate: NSPredicate(format: "income = %d", income))

        _category = category ?? Binding.constant(nil)
        _showPicker = showPicker
        _showingCategoryView = showSheet
    }
}
