//
//  TransactionCategoryPicker.swift
//  dime
//
//  Created by Rafael Soh on 20/11/23.
//

import Foundation
import SwiftUI

extension Category {
    var tokenColour: Color {
        income ? Color.IncomeGreen : Color(hex: wrappedColour)
    }
}

struct CategoryToken: View {
    let category: Category?
    let isError: Bool
    let shake: Bool
    let action: () -> Void

    var colour: Color {
        if isError {
            return Color.AlertRed
        } else if let category {
            return category.tokenColour
        } else {
            return Color.SubtitleText.opacity(0.6)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let category {
                    Text(category.wrappedEmoji)
                    Text(category.wrappedName)
                        .lineLimit(1)
                } else {
                    Text("Category")
                        .lineLimit(1)
                }
            }
            .font(.app(.body, weight: .semibold))
            .foregroundColor(colour)
            .padding(.vertical, 11)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: shake ? -5 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.map { Text("Category") + Text(", ") + Text($0.wrappedName) } ?? Text("Choose category"))
        .accessibilityAddTraits(.isButton)
    }
}

struct CategoryPickerSheet: View {
    @Binding var category: Category?
    let income: Bool
    let allowsEditing: Bool
    private var allowsNone = false
    private var title: LocalizedStringKey?
    private var overall: Binding<Bool>?

    @FetchRequest private var categories: FetchedResults<Category>
    @Environment(\.dismiss) var dismiss
    @State private var showNewCategory = false
    @State private var bodyHeight: CGFloat = 0
    @State private var isExpanded = false

    private let headerHeight: CGFloat = 64
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents(detents, selection: detentSelection)
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }

    private var estimatedBodyHeight: CGFloat {
        guard showsGrid else { return 160 }

        let tileCount = categories.count + (overall == nil ? 0 : 1) + (allowsNone ? 1 : 0)
        let rows = CGFloat((tileCount + columns.count - 1) / columns.count)
        return 12 + rows * 84 + (rows - 1) * 10 + 16
    }

    private var fittedHeight: CGFloat {
        headerHeight + (bodyHeight > 0 ? bodyHeight : estimatedBodyHeight)
    }

    @available(iOS 16.0, *)
    private var compactDetent: PresentationDetent {
        fittedHeight <= UIScreen.main.bounds.height * 0.6 ? .height(fittedHeight) : .medium
    }

    @available(iOS 16.0, *)
    private var detents: Set<PresentationDetent> {
        [compactDetent, .large]
    }

    @available(iOS 16.0, *)
    private var detentSelection: Binding<PresentationDetent> {
        Binding {
            isExpanded ? .large : compactDetent
        } set: { newValue in
            isExpanded = newValue == .large
        }
    }

    var content: some View {
        Group {
            if showsGrid {
                categoryList
            } else {
                emptyState
            }
        }
        .tabHeader {
            HStack {
                GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                    dismiss()
                }
                .hiddenInSideBar()

                Spacer()

                if allowsEditing {
                    GlassIconButton(systemName: "pencil", accessibilityLabel: "Edit Categories") {
                        showNewCategory = true
                    }
                    .hiddenInSideBar()
                }
            }
            .frame(height: 44)
            .overlay {
                CategoryEditorTitle(title: title ?? (income ? "Income Category" : "Expense Category"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheetBackground()
        .sheet(isPresented: $showNewCategory) {
            CategoryView(mode: .transaction, income: income)
        }
        .onPreferenceChange(CategorySheetBodyHeightKey.self) { height in
            bodyHeight = height
        }
        .sideBarSheet {
            SideBarCloseItem { dismiss() }
            ToolbarItem(placement: .topBarTrailing) {
                if allowsEditing {
                    Button {
                        showNewCategory = true
                    } label: {
                        Label("Edit Categories", systemImage: "pencil")
                    }
                }
            }
        }
    }

    var categoryList: some View {
        ScrollView(showsIndicators: false) {
            CategoryTileGrid(categories: categories, category: $category, overall: overall, noneIncome: allowsNone ? income : nil) {
                dismiss()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .measureCategorySheetBody()
        }
    }

    private var showsGrid: Bool {
        !categories.isEmpty || overall != nil
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Text(income ? LocalizedStringKey("no_income_categories") : LocalizedStringKey("no_expense_categories"))
                .font(.app(.body, weight: .medium))
                .foregroundColor(Color.SubtitleText)
                .multilineTextAlignment(.center)

            NewCategoryCapsule {
                showNewCategory = true
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .measureCategorySheetBody()
        .frame(maxHeight: .infinity)
    }

    /// `allowsNone` adds a No Category tile, for transactions that can be left uncategorised.
    init(category: Binding<Category?>, income: Bool, allowsEditing: Bool = true, allowsNone: Bool = false) {
        _category = category
        self.income = income
        self.allowsEditing = allowsEditing
        self.allowsNone = allowsNone
        _categories = FetchRequest<Category>(
            sortDescriptors: [SortDescriptor(\.order)],
            predicate: NSPredicate(format: "income = %d", income)
        )
    }

    /// Expense categories that can carry a budget: those without one, plus the one already linked to `editing`.
    /// Passing `overall` adds an Everything tile that stands for the overall budget.
    init(budgetCategory category: Binding<Category?>, overall: Binding<Bool>?, editing budget: Budget?) {
        _category = category
        income = false
        allowsEditing = true
        title = "Budget Category"
        self.overall = overall

        _categories = FetchRequest<Category>(
            sortDescriptors: [SortDescriptor(\.order)],
            predicate: Category.budgetablePredicate(editing: budget)
        )
    }
}

extension Category {
    /// Expense categories without a budget, plus the one already linked to `budget`.
    static func budgetablePredicate(editing budget: Budget?) -> NSPredicate {
        let available: NSPredicate
        if let budget {
            available = NSPredicate(format: "budget == nil OR budget == %@", budget)
        } else {
            available = NSPredicate(format: "budget == nil")
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "income = %d", false),
            available
        ])
    }
}

struct NewCategoryCapsule: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.app(.subheadline, weight: .semibold))
                Text("New Category")
                    .font(.app(.body, weight: .semibold))
            }
            .foregroundColor(Color.PrimaryText)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassBackground(in: Capsule(), tint: Color.glassTint)
    }
}

/// Sizes shared by the category tiles and the pickers drawn like them, such as the budget page's accounts.
enum PickerTiles {
    static let height: CGFloat = 84
    static let spacing: CGFloat = 10
    static let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    /// Matches a tile's width in the 3-column grid laid out with 20pt page margins.
    static var rowTileWidth: CGFloat {
        (UIScreen.main.bounds.width - 40 - spacing * 2) / 3
    }

    /// A horizontal strip stays one row until it has more than six selectable tiles.
    static func scrollingRows(selectableCount: Int) -> Int {
        selectableCount > 6 ? 2 : 1
    }

    static func scrollingHeight(rows: Int) -> CGFloat {
        height * CGFloat(rows) + spacing * CGFloat(rows - 1)
    }

    /// `rows` rows of tiles, each as wide as a tile in the 3-column grid, for a strip that scrolls sideways.
    static func strip<Content: View>(rows: Int, @ViewBuilder content: () -> Content) -> some View {
        let tiles = content()

        return LazyHGrid(rows: Array(repeating: GridItem(.fixed(height), spacing: spacing), count: rows), spacing: spacing) {
            Group {
                tiles
            }
            .frame(width: rowTileWidth)
        }
    }
}

/// A picker tile: an icon over a name on a tinted rounded rectangle, filled more and outlined when selected.
struct PickerTile<Icon: View>: View {
    let name: Text
    let tint: Color
    let fill: Double
    let selectedFill: Double
    let isSelected: Bool
    let accessibilityLabel: Text
    let action: () -> Void
    let icon: Icon

    /// Every icon gets an emoji's height, so names line up across tiles whatever the symbol's shape.
    @ScaledMetric(relativeTo: .title2) private var iconHeight: CGFloat = 28

    init(
        _ name: Text,
        tint: Color,
        fill: Double = 0.25,
        selectedFill: Double = 0.45,
        isSelected: Bool,
        accessibilityLabel: Text? = nil,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.name = name
        self.tint = tint
        self.fill = fill
        self.selectedFill = selectedFill
        self.isSelected = isSelected
        self.accessibilityLabel = accessibilityLabel ?? name
        self.action = action
        self.icon = icon()
    }

    var body: some View {
        let shape = PickerTiles.shape

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 6) {
                icon
                    .frame(height: iconHeight)

                name
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: PickerTiles.height)
            .background(shape.fill(tint.opacity(isSelected ? selectedFill : fill)))
            .overlay {
                if isSelected {
                    shape.strokeBorder(tint, lineWidth: 2)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(BouncyButton(duration: 0.15, scale: 0.96))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The dashed New tile that ends a picker's tiles.
struct NewPickerTile: View {
    let accessibilityLabel: Text
    let action: () -> Void

    var body: some View {
        let shape = PickerTiles.shape

        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.app(.title2, weight: .medium))
                    .foregroundColor(Color.SubtitleText)

                Text("New")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundColor(Color.SubtitleText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: PickerTiles.height)
            .overlay(shape.strokeBorder(Color.SubtitleText.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(shape)
        }
        .buttonStyle(BouncyButton(duration: 0.15, scale: 0.96))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }
}

/// The 3-column grid of tinted category tiles, or a horizontally scrolling grid of `rows` rows of the same tiles.
/// Passing `overall` adds a leading Everything tile; passing `noneIncome` adds a leading No Category tile;
/// passing `onAdd` adds a trailing New Category tile.
struct CategoryTileGrid<Categories: RandomAccessCollection>: View where Categories.Element == Category {
    let categories: Categories
    @Binding var category: Category?
    var overall: Binding<Bool>?
    /// Whether the No Category tile is for income, or nil for no such tile.
    var noneIncome: Bool?
    var rows: Int?
    var onAdd: (() -> Void)?
    let onSelect: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PickerTiles.spacing), count: 3)

    init(categories: Categories, category: Binding<Category?>, overall: Binding<Bool>? = nil, noneIncome: Bool? = nil, rows: Int? = nil, onAdd: (() -> Void)? = nil, onSelect: @escaping () -> Void) {
        self.categories = categories
        _category = category
        self.overall = overall
        self.noneIncome = noneIncome
        self.rows = rows
        self.onAdd = onAdd
        self.onSelect = onSelect
    }

    var body: some View {
        if let rows {
            PickerTiles.strip(rows: rows) {
                tiles
            }
        } else {
            LazyVGrid(columns: columns, spacing: PickerTiles.spacing) {
                tiles
            }
        }
    }

    @ViewBuilder var tiles: some View {
        if let overall {
            everythingTile(overall)
        }

        if let noneIncome {
            noneTile(income: noneIncome)
        }

        ForEach(categories) { item in
            categoryTile(item)
        }

        if let onAdd {
            NewPickerTile(accessibilityLabel: Text("New Category"), action: onAdd)
        }
    }

    func categoryTile(_ item: Category) -> some View {
        PickerTile(Text(item.wrappedName), tint: item.tokenColour, isSelected: item == category && overall?.wrappedValue != true) {
            category = item
            overall?.wrappedValue = false
            onSelect()
        } icon: {
            Text(item.wrappedEmoji)
                .font(.system(.title2))
        }
    }

    func everythingTile(_ overall: Binding<Bool>) -> some View {
        PickerTile(
            Text("Everything"),
            tint: Color.PrimaryText,
            fill: 0.08,
            selectedFill: 0.2,
            isSelected: overall.wrappedValue,
            accessibilityLabel: Text("Everything, overall budget")
        ) {
            overall.wrappedValue = true
            category = nil
            onSelect()
        } icon: {
            Image(systemName: "square.grid.2x2.fill")
                .font(.app(.title2))
                .foregroundColor(Color.PrimaryText)
        }
    }

    func noneTile(income: Bool) -> some View {
        PickerTile(
            Text("category-picker-none"),
            tint: Color(hex: Uncategorised.colour),
            isSelected: category == nil,
            accessibilityLabel: Text("No Category")
        ) {
            category = nil
            onSelect()
        } icon: {
            Image(systemName: Uncategorised.symbol(income: income))
                .font(.app(.title2, weight: .semibold))
                .foregroundColor(Color.PrimaryText)
        }
    }
}

private struct CategorySheetBodyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func measureCategorySheetBody() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: CategorySheetBodyHeightKey.self, value: proxy.size.height)
            }
        }
    }
}
