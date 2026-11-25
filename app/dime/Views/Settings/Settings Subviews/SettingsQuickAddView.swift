//
//  SettingsQuickAddView.swift
//  dime
//
//  Quick Add templates: up to four transactions the Quick Add widget logs with one tap.
//

import CoreData
import SwiftUI

struct SettingsQuickAddView: View {
  @EnvironmentObject private var dataController: DataController

  @FetchRequest(sortDescriptors: [SortDescriptor(\.order)]) private var templates: FetchedResults<TemplateTransaction>

  @FetchRequest private var recentTransactions: FetchedResults<Transaction>

  /// The template the editor is open for; `.new` adds one.
  @State private var editing: EditorItem?

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
    VStack(spacing: 0) {
      SettingsSectionHeader("Templates") {
        Text("\(templates.count)/\(TemplateTransaction.quickAddLimit)")
          .font(.system(.subheadline, design: .rounded).weight(.semibold))
          .foregroundColor(Color.SubtitleText)
          .accessibilityLabel(Text("\(templates.count) of \(TemplateTransaction.quickAddLimit) templates"))
      }

      VStack(spacing: 0) {
        ForEach(templates) { template in
          Button {
            editing = EditorItem(target: .existing(template))
          } label: {
            QuickAddRow(title: template.displayTitle, category: template.category, income: template.income, amount: template.amount, currencyCode: template.currencyCode)
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button(role: .destructive) {
              withAnimation {
                dataController.deleteQuickAddTemplate(template)
              }
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }

          Divider()
        }

        Button {
          editing = EditorItem(target: .new)
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "plus")
              .font(.system(.body, design: .rounded).weight(.semibold))
              .frame(width: 30, height: 30)

            (canAdd ? Text("New Template") : Text("You can have up to 4 templates"))
              .font(.system(.body, design: .rounded).weight(.medium))

            Spacer()
          }
          .foregroundColor(canAdd ? Color.PrimaryText : Color.SubtitleText)
          .frame(minHeight: .settingsRowHeight)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
      }
      .settingsSectionRows()

      SettingsSectionFooter("Log a template with one tap from the Quick Add widget, without opening Dime. Each one becomes its own transaction, so editing or deleting a template never changes what you've logged.")

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
}

/// A template or transaction as it appears on the Quick Add page: its category tile, name and amount.
private struct QuickAddRow: View {
  let title: String
  let category: Category?
  let income: Bool
  let amount: Double
  let currencyCode: String?
  let accessory: String

  @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var currency: String = Locale.current.currencyCode!
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
          .font(.system(.body, design: .rounded).weight(.medium))
          .foregroundColor(Color.PrimaryText)
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

      Image(systemName: accessory)
        .font(.system(.subheadline, design: .rounded).weight(accessory == "chevron.forward" ? .regular : .semibold))
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
