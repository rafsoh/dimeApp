//
//  SettingsQuickAddView.swift
//  dime
//
//  Quick Add templates: up to four transactions the Quick Add widget logs with one tap.
//  The list works like Categories: swipe to edit or delete, and Reorder to drag templates around.
//

import CoreData
import SwiftUI

struct SettingsQuickAddView: View {
  @EnvironmentObject private var dataController: DataController

  @FetchRequest(sortDescriptors: [SortDescriptor(\.order)]) private var templates: FetchedResults<TemplateTransaction>

  @FetchRequest private var recentTransactions: FetchedResults<Transaction>

  /// The template the editor is open for; `.new` adds one.
  @State private var editing: EditorItem?
  @State private var toDelete: TemplateTransaction?
  @State private var isReordering = false

  private struct EditorItem: Identifiable {
    let target: TransactionView.TemplateTarget

    var id: String {
      switch target {
      case .new:
        return "new"
      case let .existing(template):
        return template.objectID.uriRepresentation().absoluteString
      }
    }
  }

  private var canAdd: Bool {
    templates.count < TemplateTransaction.quickAddLimit
  }

  /// Recent transactions worth offering as templates: one of each, and none that's already a template.
  private var suggestions: [Transaction] {
    var seen = Set(templates.map { QuickAddKey(template: $0) })
    var picked = [Transaction]()

    for transaction in recentTransactions where picked.count < 5 {
      if seen.insert(QuickAddKey(transaction: transaction)).inserted {
        picked.append(transaction)
      }
    }

    return picked
  }

  init() {
    let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
    request.predicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as NSDate)
    request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
    request.fetchLimit = 60
    _recentTransactions = FetchRequest(fetchRequest: request)
  }

  var body: some View {
    List {
      Section(header: templatesHeader, footer: footer) {
        ForEach(templates) { template in
          QuickAddRow(title: template.displayTitle, category: template.category, income: template.income, amount: template.amount, currencyCode: template.currencyCode)
            .foregroundColor(toDelete == template ? Color.AlertRed : Color.PrimaryText)
            .settingsListRow()
            .onTapGesture {
              editing = EditorItem(target: .existing(template))
            }
            .swipeActions(edge: .trailing) {
              Button {
                toDelete = template
              } label: {
                Image(systemName: "trash.fill")
              }
              .tint(Color.AlertRed)
            }
            .swipeActions(edge: .leading) {
              Button {
                editing = EditorItem(target: .existing(template))
              } label: {
                Image(systemName: "pencil")
              }
              .tint(Color("Yellow"))
            }
            .accessibilityAddTraits(.isButton)
        }
        .onMove { source, destination in
          dataController.moveQuickAddTemplates(fromOffsets: source, toOffset: destination)
        }

        if !isReordering {
          Button {
            editing = EditorItem(target: .new)
          } label: {
            HStack(spacing: 10) {
              Image(systemName: "plus")
                .font(.system(.body, design: .rounded).weight(.semibold))

              (canAdd ? Text("New Template") : Text("You can have up to 4 templates"))
                .font(.system(.body, design: .rounded))

              Spacer()
            }
            .foregroundColor(canAdd ? Color.PrimaryText : Color.SubtitleText)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(!canAdd)
          .settingsListRow()
        }
      }

      if canAdd && !isReordering && !suggestions.isEmpty {
        Section(header: sectionHeader(Text("Add From Recent"))) {
          ForEach(suggestions) { transaction in
            QuickAddRow(title: transaction.displayTitle, category: transaction.category, income: transaction.income, amount: transaction.amount, currencyCode: transaction.currencyCode, showsAdd: true)
              .settingsListRow()
              .onTapGesture {
                withAnimation {
                  _ = dataController.addQuickAddTemplate(from: transaction)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
              }
              .accessibilityAddTraits(.isButton)
              .accessibilityHint(Text("Adds a template"))
          }
        }
      }
    }
    .modifier(HiddenListBackground())
    .environment(\.editMode, .constant(isReordering ? EditMode.active : EditMode.inactive))
    .environment(\.defaultMinListRowHeight, .settingsRowHeight)
    .settingsListMargins()
    .tabBarClearance()
    .background(Color.PrimaryBackground.ignoresSafeArea())
    .modifier(SettingsPageHeader(title: "Quick Add"))
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .onChange(of: templates.count) { count in
      if count < 2 {
        isReordering = false
      }
    }
    .confirmationSheet(
      item: $toDelete,
      title: { _ in "Delete Template?" },
      message: { _ in "Transactions you've logged with it stay as they are." }
    ) { template in
      withAnimation {
        dataController.deleteQuickAddTemplate(template)
      }
    }
    .sheet(item: $editing) { item in
      TransactionView(template: item.target)
    }
  }

  private var templatesHeader: some View {
    sectionHeader(Text("Templates")) {
      Text("\(templates.count)/\(TemplateTransaction.quickAddLimit)")
        .accessibilityLabel(Text("\(templates.count) of \(TemplateTransaction.quickAddLimit) templates"))

      if templates.count > 1 {
        SectionHeaderButton(
          title: isReordering ? "Done" : "Reorder",
          systemImage: isReordering ? "checkmark" : "arrow.up.arrow.down",
          color: isReordering ? Color.IncomeGreen : Color.SubtitleText
        ) {
          withAnimation {
            isReordering.toggle()
          }
        }
      }
    }
  }

  private var footer: some View {
    Text("Log a template with one tap from the Quick Add widget, without opening Dime. Each one becomes its own transaction, so editing or deleting a template never changes what you've logged.")
      .font(.system(.footnote, design: .rounded).weight(.medium))
      .foregroundColor(Color.SubtitleText)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, 4)
      .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
  }

  /// A section header in the Categories list's style, with optional trailing content.
  private func sectionHeader<Trailing: View>(_ title: Text, @ViewBuilder trailing: () -> Trailing) -> some View {
    HStack(spacing: 8) {
      title

      Spacer()

      trailing()
    }
    .font(.system(.subheadline, design: .rounded).weight(.semibold))
    .frame(height: 32)
    .foregroundColor(Color.SubtitleText)
    .textCase(.uppercase)
    .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
  }

  private func sectionHeader(_ title: Text) -> some View {
    sectionHeader(title) { EmptyView() }
  }
}

private struct HiddenListBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    } else {
      content
    }
  }
}

private extension View {
  /// A row on a settings section's background, as in the Categories list.
  func settingsListRow() -> some View {
    frame(minHeight: .settingsRowHeight)
      .contentShape(Rectangle())
      .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
      .listRowBackground(Rectangle().fill(Color.SettingsBackground))
      .listRowSeparatorTint(Color.Outline)
  }
}

/// A template or transaction as it appears on the Quick Add page: its category tile, name and amount.
private struct QuickAddRow: View {
  let title: String
  let category: Category?
  let income: Bool
  let amount: Double
  let currencyCode: String?
  let showsAdd: Bool

  @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var currency: String = Locale.current.currencyCode!
  @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var showCents: Bool = true

  init(title: String, category: Category?, income: Bool, amount: Double, currencyCode: String?, showsAdd: Bool = false) {
    self.title = title
    self.category = category
    self.income = income
    self.amount = amount
    self.currencyCode = currencyCode
    self.showsAdd = showsAdd
  }

  private var amountText: String {
    (income ? "+" : "") + MoneyFormatter.string(amount, currencyCode: currencyCode ?? currency, showCents: showCents)
  }

  var body: some View {
    HStack(spacing: 10) {
      EmojiLogView(category: category, income: income, future: false)
        .fixedSize(horizontal: true, vertical: true)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(.body, design: .rounded))
          .lineLimit(1)

        Text(category?.wrappedName ?? Uncategorised.name)
          .font(.system(.footnote, design: .rounded))
          .foregroundColor(Color.SubtitleText)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      Text(amountText)
        .font(.system(.body, design: .rounded).weight(.medium))
        .foregroundColor(income ? Color.IncomeGreen : Color.PrimaryText)
        .lineLimit(1)
        .layoutPriority(1)

      if showsAdd {
        Image(systemName: "plus")
          .font(.system(.body, design: .rounded).weight(.semibold))
          .foregroundColor(Color.SubtitleText)
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }
}

/// What makes two transactions or templates the same for Quick Add suggestions.
private struct QuickAddKey: Hashable {
  let note: String
  let amount: Double
  let income: Bool
  let category: NSManagedObjectID?
  let currencyCode: String?

  init(transaction: Transaction) {
    note = transaction.displayTitle
    amount = transaction.amount
    income = transaction.income
    category = transaction.category?.objectID
    currencyCode = transaction.currencyCode
  }

  init(template: TemplateTransaction) {
    note = template.wrappedNote.isEmpty ? (template.income ? String(localized: "Income") : String(localized: "Expense")) : template.wrappedNote
    amount = template.amount
    income = template.income
    category = template.category?.objectID
    currencyCode = template.currencyCode
  }
}
