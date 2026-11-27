//
//  SettingsQuickAddView.swift
//  dime
//
//  Quick Add templates: up to four transactions the Quick Add widget logs with one tap.
//

import CoreData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsQuickAddView: View {
  @ObservedObject private var dataController = DataController.shared

  @FetchRequest(sortDescriptors: [SortDescriptor(\.order)]) private var templates: FetchedResults<TemplateTransaction>

  @FetchRequest private var recentTransactions: FetchedResults<Transaction>

  /// The template the editor is open for; `.new` adds one.
  @State private var editing: EditorItem?
  /// The template being dragged to a new spot.
  @State private var dragging: TemplateTransaction?

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
    // A Quick Add template is an expense or income, so transfers can't become one.
    request.predicate = TransferPredicate.excluding(NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as NSDate))
    request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
    request.fetchLimit = 60
    _recentTransactions = FetchRequest(fetchRequest: request)
  }

  var body: some View {
    VStack(spacing: 0) {
      SettingsSectionHeader("Templates") {
        Text("\(templates.count)/\(TemplateTransaction.quickAddLimit)")
          .font(.app(.subheadline, weight: .semibold))
          .foregroundColor(Color.SubtitleText)
          .accessibilityLabel(Text("\(templates.count) of \(TemplateTransaction.quickAddLimit) templates"))
      }

      // The templates laid out as the medium Quick Add widget shows them.
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
        ForEach(Array(templates.enumerated()), id: \.element.objectID) { index, template in
          Button {
            editing = EditorItem(target: .existing(template))
          } label: {
            QuickAddTile(template: template)
          }
          .buttonStyle(.plain)
          .opacity(dragging == template ? 0.4 : 1)
          .contextMenu {
            Button(role: .destructive) {
              withAnimation {
                dataController.deleteQuickAddTemplate(template)
              }
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
          .onDrag {
            dragging = template
            return NSItemProvider(object: template.objectID.uriRepresentation().absoluteString as NSString)
          }
          .onDrop(of: [UTType.text], delegate: QuickAddDropDelegate(target: template, templates: Array(templates), dragging: $dragging, dataController: dataController))
          .accessibilityAction(named: Text("Move Earlier")) {
            move(index, by: -1)
          }
          .accessibilityAction(named: Text("Move Later")) {
            move(index, by: 1)
          }
        }

        ForEach(min(templates.count, TemplateTransaction.quickAddLimit) ..< TemplateTransaction.quickAddLimit, id: \.self) { _ in
          Button {
            editing = EditorItem(target: .new)
          } label: {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .strokeBorder(Color.SubtitleText.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
              .overlay {
                Image(systemName: "plus")
                  .font(.app(.body, weight: .semibold))
                  .foregroundColor(Color.SubtitleText)
              }
              .frame(height: QuickAddTile.height)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("New Template"))
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity)
      .settingsSectionBackground()

      SettingsSectionFooter("Tap a template to edit it, or hold and drag it to a new spot. The Quick Add widget logs each one with one tap, without opening Dime, and editing or deleting a template never changes what you've logged.")

      if canAdd && !suggestions.isEmpty {
        SettingsSectionHeader("Add From Recent")
          .padding(.top, .settingsHeaderSpacing)

        VStack(spacing: 0) {
          ForEach(suggestions) { transaction in
            Button {
              withAnimation {
                _ = dataController.addQuickAddTemplate(from: transaction)
              }
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
              QuickAddRow(title: transaction.displayTitle, category: transaction.category, income: transaction.income, amount: transaction.amount, currencyCode: transaction.currencyCode, accessory: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Adds a template"))

            if transaction != suggestions.last {
              Divider()
            }
          }
        }
        .settingsSectionRows()
      }
    }
    .animation(.easeInOut(duration: 0.2), value: templates.count)
    .modifier(SettingsSubviewModifier(title: "Quick Add"))
    .sheet(item: $editing) { item in
      TransactionView(template: item.target)
    }
  }

  /// Moves a template one spot earlier or later, for VoiceOver.
  private func move(_ index: Int, by offset: Int) {
    let destination = index + offset
    guard templates.indices.contains(destination) else { return }

    withAnimation {
      dataController.moveQuickAddTemplates(fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? destination + 1 : destination)
    }
  }
}

/// A template as the Quick Add widget shows it: tinted with its category, with its emoji, name and amount.
private struct QuickAddTile: View {
  static let height: CGFloat = 64

  let template: TemplateTransaction

  @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var currency: String = Locale.current.currencyCode ?? "USD"
  @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var showCents: Bool = true

  init(template: TemplateTransaction) {
    self.template = template
  }

  private var amountText: String {
    (template.income ? "+" : "") + MoneyFormatter.string(template.amount, currencyCode: template.currencyCode ?? currency, showCents: showCents)
  }

  var body: some View {
    HStack(spacing: 8) {
      Group {
        if template.category == nil {
          Image(systemName: Uncategorised.symbol(income: template.income))
            .font(.app(.subheadline, weight: .bold))
            .foregroundColor(Color(hex: Uncategorised.colour))
        } else {
          Text(template.wrappedEmoji)
            .font(.system(.title3))
        }
      }
      .frame(width: 28)

      VStack(alignment: .leading, spacing: 0) {
        Text(template.displayTitle)
          .font(.app(.subheadline, weight: .semibold))
          .foregroundColor(Color.PrimaryText)
          .lineLimit(1)

        Text(amountText)
          .font(.app(.footnote, weight: .medium))
          .foregroundColor(template.income ? Color.IncomeGreen : Color.SubtitleText)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
    .background(Color(hex: template.wrappedColour).opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .dynamicTypeSize(...DynamicTypeSize.xLarge)
    .accessibilityElement(children: .combine)
    .accessibilityHint(Text("Edits the template"))
  }
}

/// Moves the dragged template into the spot it's dragged over, so the grid reorders as the finger moves.
private struct QuickAddDropDelegate: DropDelegate {
  let target: TemplateTransaction
  let templates: [TemplateTransaction]
  @Binding var dragging: TemplateTransaction?
  let dataController: DataController

  func dropEntered(info _: DropInfo) {
    guard let dragging, dragging != target,
          let from = templates.firstIndex(of: dragging),
          let to = templates.firstIndex(of: target)
    else {
      return
    }

    withAnimation(.easeInOut(duration: 0.2)) {
      dataController.moveQuickAddTemplates(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }
  }

  func dropUpdated(info _: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }

  func performDrop(info _: DropInfo) -> Bool {
    dragging = nil
    return true
  }
}

/// A transaction as it appears on the Quick Add page: its category tile, name and amount.
private struct QuickAddRow: View {
  let title: String
  let category: Category?
  let income: Bool
  let amount: Double
  let currencyCode: String?
  let accessory: String

  @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var currency: String = Locale.current.currencyCode ?? "USD"
  @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var showCents: Bool = true

  init(title: String, category: Category?, income: Bool, amount: Double, currencyCode: String?, accessory: String = "chevron.forward") {
    self.title = title
    self.category = category
    self.income = income
    self.amount = amount
    self.currencyCode = currencyCode
    self.accessory = accessory
  }

  private var amountText: String {
    (income ? "+" : "") + MoneyFormatter.string(amount, currencyCode: currencyCode ?? currency, showCents: showCents)
  }

  var body: some View {
    HStack(spacing: 12) {
      EmojiLogView(category: category, income: income, future: false)
        .fixedSize(horizontal: true, vertical: true)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.app(.body, weight: .medium))
          .foregroundColor(Color.PrimaryText)
          .lineLimit(1)

        Text(category?.wrappedName ?? Uncategorised.name)
          .font(.app(.footnote))
          .foregroundColor(Color.SubtitleText)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      Text(amountText)
        .font(.app(.body, weight: .medium))
        .foregroundColor(income ? Color.IncomeGreen : Color.PrimaryText)
        .lineLimit(1)
        .layoutPriority(1)

      Image(systemName: accessory)
        .font(.app(.subheadline).weight(accessory == "chevron.forward" ? .regular : .semibold))
        .foregroundColor(accessory == "chevron.forward" ? .DarkIcon.opacity(0.6) : Color.SubtitleText)
    }
    .padding(.vertical, 8)
    .frame(minHeight: .settingsRowHeight)
    .contentShape(Rectangle())
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
