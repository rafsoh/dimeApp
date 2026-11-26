//
//  AccountsView.swift
//  dime
//
//  The accounts list in Settings and onboarding, the account name editor, and the account picker.
//

import CoreData
import SwiftUI

/// The symbol for accounts: a wallet, since accounts hold cash and savings as much as cards.
enum AccountSymbol {
    static var outline: String {
        if #available(iOS 17.0, *) {
            return "wallet.bifold"
        }
        return "banknote"
    }

    static var filled: String {
        if #available(iOS 17.0, *) {
            return "wallet.bifold.fill"
        }
        return "banknote.fill"
    }
}

enum AccountsViewMode {
    /// In Settings; in onboarding, after categories; and once, as a half sheet, for people updating from before accounts.
    case settings, welcome, announcement
}

// MARK: - Announcement

/// Introduces accounts, once, to people who used Dime before them. New installs meet accounts in onboarding instead.
enum AccountsIntro {
    private static let seenKey = "accountsIntroSeen"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.rafaelsoh.dime") ?? .standard
    }

    static var isSeen: Bool {
        defaults.bool(forKey: seenKey)
    }

    static func markSeen() {
        defaults.set(true, forKey: seenKey)
    }
}

/// The accounts list as a half sheet, with a note above it saying what's new; it can be pulled up to full height.
struct AccountsIntroSheet: View {
    @EnvironmentObject var dataController: DataController

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                AccountsView(mode: .announcement)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        } else {
            NavigationView {
                AccountsView(mode: .announcement)
            }
            .navigationViewStyle(.stack)
        }
    }
}

// MARK: - Onboarding

private struct FinishOnboardingKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Closes the welcome sheet from any page pushed inside it.
    var finishOnboarding: (() -> Void)? {
        get { self[FinishOnboardingKey.self] }
        set { self[FinishOnboardingKey.self] = newValue }
    }
}

/// Pushes the accounts step of onboarding.
struct OnboardingAccountsStep: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .navigationDestination(isPresented: $isPresented) {
                    AccountsView(mode: .welcome)
                }
        } else {
            content
                .background {
                    NavigationLink(destination: AccountsView(mode: .welcome), isActive: $isPresented) {
                        EmptyView()
                    }
                    .hidden()
                }
        }
    }
}

// MARK: - Accounts list

struct AccountsView: View {
    let mode: AccountsViewMode

    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.finishOnboarding) private var finishOnboarding

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order), SortDescriptor(\.dateCreated)]) private var accounts: FetchedResults<Account>

    /// Redraws Main's row when it's renamed, here or on another device.
    @AppStorage(MainAccount.nameKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var mainName = ""

    @State private var isReordering = false
    @State private var editing: AccountEditorSheet.Target?
    @State private var toDelete: Account?

    var body: some View {
        switch mode {
        case .settings:
            content
                .modifier(SettingsPageHeader(title: "Accounts"))
        case .welcome, .announcement:
            content
                .navigationTitle(Text("Accounts"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // A half sheet has no room for a floating button over its list, so New moves up here.
                    if mode == .announcement {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                editing = .new
                            } label: {
                                Label("New Account", systemImage: "plus")
                            }
                            .prominentToolbarButton(tint: Color.PrimaryText, isProminent: false)
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            if let finishOnboarding {
                                finishOnboarding()
                            } else {
                                dismiss()
                            }
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .prominentToolbarButton(tint: Color.IncomeGreen, isProminent: true)
                    }
                }
                .tint(Color.PrimaryText)
        }
    }

    private var content: some View {
        list
            .bottomBar {
                if mode != .announcement {
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)

                        Button {
                            editing = .new
                        } label: {
                            Label("New", systemImage: "plus")
                                .font(.app(.body, weight: .semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .lineLimit(1)
                                .foregroundColor(Color.PrimaryText)
                                .padding(.horizontal, 18)
                                .frame(height: 44)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassBackground(in: Capsule(), tint: .glassTint)
                        .accessibilityLabel("New Account")
                    }
                    .padding(.horizontal, .settingsPageInset)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.keyboard, edges: .all)
            .background(Color.PrimaryBackground)
            .sheet(item: $editing) { target in
                AccountEditorSheet(target: target)
                    .environmentObject(dataController)
            }
            .confirmationSheet(
                item: $toDelete,
                title: { "Delete '\($0.wrappedName)'?" },
                message: { _ in "Its transactions and Quick Add templates move to \(MainAccount.name). Nothing else is deleted." }
            ) { account in
                withAnimation {
                    dataController.deleteAccount(account)
                }
            }
    }

    @ViewBuilder private var list: some View {
        let list = List {
            if mode == .announcement {
                announcement
            }

            Section {
                row(name: MainAccount.name, isMain: true)
                    .moveDisabled(true)
                    .onTapGesture {
                        editing = .edit(.main)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editing = .edit(.main)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .tint(Color("Yellow"))
                    }

                ForEach(accounts) { account in
                    row(name: account.wrappedName, isMain: false)
                        .onTapGesture {
                            editing = .edit(.account(account))
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                toDelete = account
                            } label: {
                                Image(systemName: "trash.fill")
                            }
                            .tint(Color.AlertRed)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editing = .edit(.account(account))
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .tint(Color("Yellow"))
                        }
                }
                .onMove { source, destination in
                    dataController.moveAccounts(Array(accounts), fromOffsets: source, toOffset: destination)
                }
            } header: {
                header
            } footer: {
                Text("Transactions not in another account are in \(MainAccount.name). You can rename \(MainAccount.name), but not delete it.")
                    .font(.app(.footnote))
                    .foregroundColor(Color.SubtitleText)
                    .padding(.top, 4)
                    // Keeps the footer with its own section, apart from the next one's header.
                    .padding(.bottom, .settingsHeaderSpacing)
                    .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
            }

            AccountSuggestionsSection(existingNames: [MainAccount.name] + accounts.map(\.wrappedName))
        }
        .environment(\.editMode, .constant(isReordering ? EditMode.active : EditMode.inactive))
        .environment(\.defaultMinListRowHeight, .settingsRowHeight)
        .settingsListMargins()

        if #available(iOS 16.0, *) {
            list
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
        } else {
            list
        }
    }

    /// Shown only in the announcement sheet: what accounts are for, and that nothing logged so far has moved.
    private var announcement: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("New")
                    .font(.app(.caption, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundColor(Color.IncomeGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.IncomeGreen.opacity(0.14)))
                    .accessibilityHidden(true)

                Text("Keep cash, cards and savings apart")
                    .font(.app(.title3, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Everything you've logged so far is in \(MainAccount.name). Tap it to rename it, or add an account below.")
                    .font(.app(.subheadline))
                    .foregroundColor(Color.SubtitleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
            .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .combine)
        }
    }

    private var header: some View {
        HStack {
            Text("Accounts")

            Spacer()

            if accounts.count > 1 {
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
        .font(.app(.subheadline, weight: .semibold))
        .frame(height: 32)
        .foregroundColor(Color.SubtitleText)
        .textCase(.uppercase)
        .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
    }

    private func row(name: String, isMain: Bool) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.app(.body))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .lineLimit(1)
                .foregroundColor(Color.PrimaryText)

            Spacer()
        }
        .frame(minHeight: .settingsRowHeight)
        .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
        .listRowBackground(Rectangle().fill(Color.SettingsBackground))
        .listRowSeparatorTint(Color.Outline)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(isMain ? "Renames the account" : "Edits the account"))
    }
}

/// A few common accounts, one tap to add.
private struct AccountSuggestionsSection: View {
    let existingNames: [String]

    @EnvironmentObject var dataController: DataController

    static var all: [String] {
        [String(localized: "Cash"), String(localized: "Debit Card"), String(localized: "Credit Card"), String(localized: "Savings")]
    }

    var suggestions: [String] {
        Self.all.filter { suggestion in
            !existingNames.contains { $0.compare(suggestion, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        }
    }

    var body: some View {
        if !suggestions.isEmpty {
            Section {
                ForEach(suggestions, id: \.self) { name in
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.app(.body))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "plus")
                            .font(.app(.body, weight: .semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundColor(Color.SubtitleText)
                    }
                    .foregroundColor(Color.PrimaryText)
                    .frame(minHeight: .settingsRowHeight)
                    .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
                    .listRowBackground(Rectangle().fill(Color.SettingsBackground))
                    .listRowSeparatorTint(Color.Outline)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard dataController.accountNameCheck(name) == .none else { return }

                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation {
                            _ = dataController.addAccount(named: name)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Add \(name)"))
                    .accessibilityAddTraits(.isButton)
                }
            } header: {
                Text("Suggested")
                    .font(.app(.subheadline, weight: .semibold))
                    .frame(height: 32)
                    .foregroundColor(Color.SubtitleText)
                    .textCase(.uppercase)
                    .listRowInsets(EdgeInsets(top: 0, leading: .settingsRowInset, bottom: 0, trailing: .settingsRowInset))
            }
        }
    }
}

// MARK: - Editor

/// Names a new account, or renames one. Main can be renamed but not deleted.
struct AccountEditorSheet: View {
    enum Target: Identifiable {
        case new
        case edit(AccountChoice)

        var id: String {
            switch self {
            case .new:
                return "new"
            case let .edit(choice):
                return choice.key
            }
        }
    }

    let target: Target
    /// Called with the account a new one created, so a picker can select it.
    var onCreate: ((AccountChoice) -> Void)?

    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var toastTitle = ""
    @State private var showToast = false

    init(target: Target, onCreate: ((AccountChoice) -> Void)? = nil) {
        self.target = target
        self.onCreate = onCreate

        if case let .edit(choice) = target {
            _name = State(initialValue: choice.name)
        } else {
            _name = State(initialValue: "")
        }
    }

    var editingChoice: AccountChoice? {
        if case let .edit(choice) = target {
            return choice
        }
        return nil
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.height(170)])
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                    dismiss()
                }

                Spacer()
            }
            .frame(height: 44)
            .overlay {
                if showToast {
                    GlassToast(title: toastTitle, systemImage: "character.cursor.ibeam", color: Color.AlertRed)
                } else {
                    CategoryEditorTitle(title: editingChoice == nil ? "New Account" : "Edit Account")
                }
            }

            Spacer(minLength: 20)

            HStack(spacing: 10) {
                NormalTextField(text: $name, placeholder: String(localized: "Account Name"), autofocus: true, action: save)
                    .foregroundColor(Color.PrimaryText)
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .glassField(in: Capsule(), isFocused: true)

                CategoryConfirmButton(systemImage: editingChoice == nil ? "plus" : "checkmark", accessibilityLabel: editingChoice == nil ? "Add Account" : "Save", action: save)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheetBackground()
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
    }

    func save() {
        // Renaming Main back to nothing restores its default name.
        if editingChoice == .main, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dataController.renameAccount(.main, to: "")
            dismiss()
            return
        }

        switch dataController.accountNameCheck(name, editing: editingChoice) {
        case .missingName:
            toastTitle = String(localized: "Missing Name")
            showToast = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .duplicateName:
            toastTitle = String(localized: "Duplicate Name")
            showToast = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .none:
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            if let editingChoice {
                dataController.renameAccount(editingChoice, to: name)
            } else {
                let account = dataController.addAccount(named: name)
                onCreate?(.account(account))
            }

            dismiss()
        }
    }
}

// MARK: - Picker

/// Picks one account, or with `scope` any number of them.
struct AccountPickerSheet: View {
    let title: LocalizedStringKey
    private var selection: Binding<AccountChoice?>?
    private var scope: Binding<AccountScope>?
    /// Adds an All Accounts row, which picks nil.
    private var allowsAll = false
    /// An account that can't be picked, such as where a transfer comes from when picking where it goes.
    private var unavailable: AccountChoice?

    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order), SortDescriptor(\.dateCreated)]) private var accounts: FetchedResults<Account>
    @AppStorage(MainAccount.nameKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var mainName = ""

    @State private var showNewAccount = false

    /// Picks one account; with `allowsAll`, nil stands for every account.
    init(title: LocalizedStringKey, selection: Binding<AccountChoice?>, allowsAll: Bool = false, unavailable: AccountChoice? = nil) {
        self.title = title
        self.selection = selection
        self.allowsAll = allowsAll
        self.unavailable = unavailable
    }

    /// Picks which accounts something counts.
    init(title: LocalizedStringKey, scope: Binding<AccountScope>) {
        self.title = title
        self.scope = scope
        allowsAll = true
    }

    var choices: [AccountChoice] {
        [.main] + accounts.map(AccountChoice.account)
    }

    private var rowCount: Int {
        choices.count + (allowsAll ? 1 : 0)
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
    private var detents: Set<PresentationDetent> {
        // Header, rows and margins.
        let height = 84 + CGFloat(rowCount) * 60 + 28
        return height <= UIScreen.main.bounds.height * 0.7 ? [.height(height), .large] : [.medium, .large]
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                if allowsAll {
                    row(Text("All Accounts"), isSelected: isAllSelected, isDisabled: false) {
                        selectAll()
                    }
                }

                ForEach(choices) { choice in
                    row(Text(choice.name), isSelected: isSelected(choice), isDisabled: choice == unavailable) {
                        select(choice)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .tabHeader {
            HStack {
                // Picks apply as they're made, so closing is all there is to do.
                GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                    dismiss()
                }

                Spacer()

                GlassIconButton(systemName: "plus", accessibilityLabel: "New Account") {
                    showNewAccount = true
                }
            }
            .frame(height: 44)
            .overlay {
                CategoryEditorTitle(title: title)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheetBackground()
        .sheet(isPresented: $showNewAccount) {
            AccountEditorSheet(target: .new) { created in
                // Picking a new account in a single pick closes the picker too.
                if let selection {
                    selection.wrappedValue = created
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        dismiss()
                    }
                } else if let scope, let keys = scope.wrappedValue.keys {
                    scope.wrappedValue = AccountScope(keys: keys.union([created.key]))
                }
            }
            .environmentObject(dataController)
        }
    }

    private func row(_ name: Text, isSelected: Bool, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return Button(action: action) {
            HStack(spacing: 12) {
                name
                    .font(.app(.body, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(isDisabled ? Color.SubtitleText.opacity(0.6) : Color.PrimaryText)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.app(.body, weight: .bold))
                        .foregroundColor(Color.PrimaryText)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .glassBackground(in: shape, tint: isSelected ? Color.PrimaryText.opacity(0.16) : Color.glassTint, fallback: isSelected ? Color.PrimaryText.opacity(0.12) : Color.SecondaryBackground)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var isAllSelected: Bool {
        if let scope {
            return scope.wrappedValue.isAll
        }
        if let selection {
            return selection.wrappedValue == nil
        }
        return false
    }

    private func isSelected(_ choice: AccountChoice) -> Bool {
        if let scope {
            return !scope.wrappedValue.isAll && scope.wrappedValue.includes(choice)
        }
        if let selection {
            return selection.wrappedValue == choice
        }
        return false
    }

    private func selectAll() {
        UISelectionFeedbackGenerator().selectionChanged()

        withAnimation(.easeOut(duration: 0.15)) {
            if let scope {
                scope.wrappedValue = .all
            } else if let selection {
                selection.wrappedValue = nil
                dismiss()
            }
        }
    }

    private func select(_ choice: AccountChoice) {
        UISelectionFeedbackGenerator().selectionChanged()

        withAnimation(.easeOut(duration: 0.15)) {
            if let scope {
                var keys = scope.wrappedValue.keys ?? []
                if keys.contains(choice.key) {
                    keys.remove(choice.key)
                } else {
                    keys.insert(choice.key)
                }

                // Every account picked, or none, is the same as all of them.
                let everyKey = Set(choices.map(\.key))
                scope.wrappedValue = keys.isEmpty || everyKey.isSubset(of: keys) ? .all : AccountScope(keys: keys)
            } else if let selection {
                selection.wrappedValue = choice
                dismiss()
            }
        }
    }
}

// MARK: - Token

/// An account on the entry page's date and category line.
struct AccountToken: View {
    let name: String
    var isError = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(name)
                    .font(.app(.body, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isError ? Color.AlertRed : Color.SubtitleText)
            .padding(.vertical, 11)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Account") + Text(", ") + Text(name))
        .accessibilityAddTraits(.isButton)
    }
}

struct SettingsAccountsView: View {
    var body: some View {
        AccountsView(mode: .settings)
            .background(Color.PrimaryBackground)
    }
}
