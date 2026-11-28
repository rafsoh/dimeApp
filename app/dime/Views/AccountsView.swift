//
//  AccountsView.swift
//  dime
//
//  The accounts list in Settings and onboarding, the account name editor, and the account picker.
//

import CoreData
import SwiftUI
import UIKit

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

// MARK: - Account icons

extension AccountIcons {
    /// Symbols newer than iOS 15, and what stands in for them there.
    private static let fallbacks = [
        "wallet.bifold": "wallet.pass",
        "giftcard": "gift",
        "chart.line.uptrend.xyaxis": "chart.bar"
    ]

    /// The symbol to draw: the saved one, or a stand-in where this iOS version lacks it, such as one picked
    /// on a newer device.
    static func displayable(_ symbol: String) -> String {
        if UIImage(systemName: symbol) != nil {
            return symbol
        }

        if let fallback = fallbacks[symbol], UIImage(systemName: fallback) != nil {
            return fallback
        }

        return "wallet.pass"
    }
}

/// An account's icon: a plain symbol in the colour of the text around it, never a coloured tile,
/// so an account can't be mistaken for a category.
struct AccountIconView: View {
    let symbol: String

    var body: some View {
        Image(systemName: AccountIcons.displayable(symbol))
            .accessibilityHidden(true)
    }
}

/// Every account icon, to pick one. The account editor shows it where the keyboard was, like the emoji
/// keyboard in the category editor.
struct AccountIconGrid: View {
    let selection: String
    let onPick: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(AccountIcons.all, id: \.self) { symbol in
                let isSelected = symbol == selection

                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onPick(symbol)
                } label: {
                    Image(systemName: AccountIcons.displayable(symbol))
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(isSelected ? Color.LightIcon : Color.PrimaryText)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(isSelected ? Color.DarkBackground : Color.PrimaryText.opacity(0.06)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// The icons as a keyboard. The account editor's icon tile takes focus with it, the way the category editor's
/// emoji tile brings up the emoji keyboard: moving between the tile and the name swaps one keyboard for the
/// other in place, so the sheet above them never moves.
struct AccountIconKeyboard: UIViewRepresentable {
    @Binding var isActive: Bool
    let selection: String
    let onPick: (String) -> Void

    /// Used until the name's keyboard has been seen, such as with a hardware keyboard.
    static let fallbackHeight: CGFloat = 270
    /// Four rows of icons.
    static let minimumHeight: CGFloat = 240

    final class Coordinator {
        var isActive: Binding<Bool>
        var hosting: UIHostingController<AccountIconKeyboardContent>?
        weak var host: AccountIconKeyboardHost?
        /// How tall the name's keyboard is, so the icons can be as tall and the sheet above them stays put.
        private var textKeyboardHeight: CGFloat?
        /// What the system adds below a custom keyboard, such as room for the home indicator. Measured the first
        /// time the icons show.
        private static var systemPadding: CGFloat?
        private var observer: NSObjectProtocol?

        init(isActive: Binding<Bool>) {
            self.isActive = isActive
            observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] notification in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                self?.keyboardWillChange(to: frame.height)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func focusChanged(_ focused: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive.wrappedValue != focused else { return }
                self.isActive.wrappedValue = focused
            }
        }

        /// Makes the icons as tall as the name's keyboard, before they show.
        func sizeIcons() {
            guard let host, let keyboard = host.iconKeyboard else { return }
            let padding = Self.systemPadding ?? host.window?.safeAreaInsets.bottom ?? 0
            let height = iconsHeight(padding: padding)

            if keyboard.frame.height != height {
                keyboard.frame.size.height = height
            }
        }

        private func iconsHeight(padding: CGFloat) -> CGFloat {
            // A hardware keyboard leaves only a short bar, which the icons can't fit in.
            guard let textKeyboardHeight, textKeyboardHeight >= 200 else {
                return AccountIconKeyboard.fallbackHeight
            }
            return max(AccountIconKeyboard.minimumHeight, (textKeyboardHeight - padding).rounded())
        }

        private func keyboardWillChange(to height: CGFloat) {
            guard height > 0, let host, let keyboard = host.iconKeyboard else { return }

            guard host.isFirstResponder else {
                textKeyboardHeight = height
                return
            }

            // The icons are showing: learn what the system added below them, and if the guess was off, correct it once.
            Self.systemPadding = height - keyboard.frame.height
            let corrected = iconsHeight(padding: height - keyboard.frame.height)

            if abs(corrected - keyboard.frame.height) > 1 {
                keyboard.frame.size.height = corrected
                host.reloadInputViews()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isActive: $isActive)
    }

    func makeUIView(context: Context) -> AccountIconKeyboardHost {
        let host = AccountIconKeyboardHost()
        let hosting = UIHostingController(rootView: AccountIconKeyboardContent(selection: selection, colorScheme: context.environment.colorScheme, onPick: onPick))
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        // Drawn on the keyboard's own background, like the emoji keyboard.
        // The system sets the width; the height is the name's keyboard's, once that's known (see Coordinator).
        let keyboard = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: Self.fallbackHeight), inputViewStyle: .keyboard)
        keyboard.allowsSelfSizing = false
        keyboard.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: keyboard.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: keyboard.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: keyboard.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: keyboard.bottomAnchor)
        ])

        host.iconKeyboard = keyboard
        host.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.focusChanged(focused)
        }
        context.coordinator.hosting = hosting
        context.coordinator.host = host
        return host
    }

    func updateUIView(_ host: AccountIconKeyboardHost, context: Context) {
        let coordinator = context.coordinator
        coordinator.isActive = $isActive
        coordinator.hosting?.rootView = AccountIconKeyboardContent(selection: selection, colorScheme: context.environment.colorScheme, onPick: onPick)

        // The keyboard has its own window, which doesn't follow the app's appearance setting.
        let style: UIUserInterfaceStyle = context.environment.colorScheme == .dark ? .dark : .light
        if host.iconKeyboard?.overrideUserInterfaceStyle != style {
            host.iconKeyboard?.overrideUserInterfaceStyle = style
        }

        if isActive, !host.isFirstResponder {
            DispatchQueue.main.async { [weak coordinator] in
                guard !host.isFirstResponder else { return }
                coordinator?.sizeIcons()

                // If the icons can't take focus, the tile goes back to unfocused, so tapping it tries again.
                if !host.becomeFirstResponder() {
                    coordinator?.focusChanged(false)
                }
            }
        } else if !isActive, host.isFirstResponder {
            DispatchQueue.main.async {
                _ = host.resignFirstResponder()
            }
        }
    }
}

/// A text field whose keyboard is the icons. It has no size, draws nothing and takes no text.
///
/// It's a text field rather than a plain view with an input view: the sheet only rises above the keyboard of
/// a text field, and with a plain view the icons covered the sheet.
final class AccountIconKeyboardHost: UITextField, UITextFieldDelegate {
    var iconKeyboard: UIView? {
        didSet {
            inputView = iconKeyboard
        }
    }

    var onFocusChange: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        borderStyle = .none
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear
        autocorrectionType = .no
        spellCheckingType = .no
        autocapitalizationType = .none
        // No undo, redo and paste bar above the icons on iPad.
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func caretRect(for _: UITextPosition) -> CGRect {
        .zero
    }

    override func selectionRects(for _: UITextRange) -> [UITextSelectionRect] {
        []
    }

    override func canPerformAction(_: Selector, withSender _: Any?) -> Bool {
        false
    }

    // Typing on a hardware keyboard goes nowhere.
    func textField(_: UITextField, shouldChangeCharactersIn _: NSRange, replacementString _: String) -> Bool {
        false
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        false
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onFocusChange?(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onFocusChange?(false)
        }
        return resigned
    }
}

struct AccountIconKeyboardContent: View {
    let selection: String
    let colorScheme: ColorScheme
    let onPick: (String) -> Void

    var body: some View {
        AccountIconGrid(selection: selection, onPick: onPick)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, colorScheme)
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
    @ObservedObject var dataController = DataController.shared

    var body: some View {
        if #available(iOS 16.0, *) {
            AccountsView(mode: .announcement)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            AccountsView(mode: .announcement)
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

    @ObservedObject var dataController = DataController.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.finishOnboarding) private var finishOnboarding

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order), SortDescriptor(\.dateCreated)]) private var accounts: FetchedResults<Account>

    /// Redraws Main's row when it's renamed or given another icon, here or on another device.
    @AppStorage(MainAccount.nameKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var mainName = ""
    @AppStorage(MainAccount.symbolKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var mainSymbol = ""

    @State private var isReordering = false
    @State private var editing: AccountEditorSheet.Target?
    @State private var toDelete: Account?

    var body: some View {
        switch mode {
        case .settings:
            content
                .modifier(SettingsPageHeader(title: "Accounts"))
        case .announcement:
            // A sheet of its own, headed like the app's other sheets: close, the title centred, and New, which
            // a half sheet has no room to float over its list.
            content
                .tabHeader {
                    HStack {
                        GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                            dismiss()
                        }
                        .hiddenInSideBar()

                        Spacer()

                        GlassIconButton(systemName: "plus", accessibilityLabel: "New Account") {
                            editing = .new
                        }
                        .hiddenInSideBar()
                    }
                    .frame(height: 44)
                    .overlay {
                        CategoryEditorTitle(title: "Accounts")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                .sideBarSheet {
                    SideBarCloseItem { dismiss() }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editing = .new
                        } label: {
                            Label("New Account", systemImage: "plus")
                        }
                    }
                }
        case .welcome:
            content
                .navigationTitle(Text("Accounts"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
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
                message: { account in
                    // Transfers with Main would be from Main to Main once this account's side moves there.
                    if dataController.transfersWithMain(of: account).isEmpty {
                        return "Its transactions and Quick Add templates move to \(MainAccount.name). Nothing else is deleted."
                    }
                    return "Its transactions and Quick Add templates move to \(MainAccount.name). Its transfers with \(MainAccount.name) are deleted, since both sides would be \(MainAccount.name)."
                }
            ) { account in
                withAnimation {
                    dataController.deleteAccount(account)
                }
            }
            #if DEBUG
            .onAppear {
                // Screenshots, removed with the other accounts launch arguments: `-accountEditor new|typed|edit|icons`
                // opens the account editor for a new account, a new one with a name typed, Card, or Card with its icons.
                let arguments = ProcessInfo.processInfo.arguments
                guard let index = arguments.firstIndex(of: "-accountEditor"), index + 1 < arguments.count else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    switch arguments[index + 1] {
                    case "new", "typed":
                        editing = .new
                    default:
                        if let card = accounts.first(where: { $0.wrappedName == "Card" }) ?? accounts.first {
                            editing = .edit(.account(card))
                        }
                    }
                }
            }
            #endif
    }

    @ViewBuilder private var list: some View {
        let list = List {
            if mode == .announcement {
                announcement
            }

            Section {
                row(name: MainAccount.name, symbol: MainAccount.symbol, isMain: true)
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
                    row(name: account.wrappedName, symbol: account.wrappedSymbol, isMain: false)
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

    private func row(name: String, symbol: String, isMain: Bool) -> some View {
        HStack(spacing: 12) {
            AccountIconView(symbol: symbol)
                .font(.app(.body, weight: .medium))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(Color.SubtitleText)
                .frame(width: 26)

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

    @ObservedObject var dataController = DataController.shared

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
                    HStack(spacing: 12) {
                        AccountIconView(symbol: AccountIcons.guess(for: name))
                            .font(.app(.body, weight: .medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundColor(Color.SubtitleText)
                            .frame(width: 26)

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

    @ObservedObject var dataController = DataController.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    /// The icon picked here. Until one is, a new account's icon follows its name.
    @State private var pickedSymbol: String?
    @State private var showingIcons = false
    @State private var toastTitle = ""
    @State private var showToast = false

    init(target: Target, onCreate: ((AccountChoice) -> Void)? = nil) {
        self.target = target
        self.onCreate = onCreate

        if case let .edit(choice) = target {
            _name = State(initialValue: choice.name)
            _pickedSymbol = State(initialValue: choice.symbol)
        } else {
            _name = State(initialValue: "")
        }
    }

    var symbol: String {
        pickedSymbol ?? AccountIcons.guess(for: name)
    }

    var editingChoice: AccountChoice? {
        if case let .edit(choice) = target {
            return choice
        }
        return nil
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            // The icons are a keyboard of their own, so the sheet keeps one height above whichever is showing.
            content(fixedHeight: false)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.hidden)
        } else {
            content(fixedHeight: true)
        }
    }

    /// Laid out like the category editor: the title, the icon where a category has its emoji, then the name
    /// and the confirm button.
    private func content(fixedHeight: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                GlassIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                    dismiss()
                }
                .hiddenInSideBar()

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

            Spacer(minLength: 16)

            iconTile

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                NormalTextField(text: $name, placeholder: String(localized: "Account Name"), autofocus: true, action: save)
                    .foregroundColor(Color.PrimaryText)
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .glassField(in: Capsule(), isFocused: !showingIcons)

                CategoryConfirmButton(systemImage: editingChoice == nil ? "plus" : "checkmark", accessibilityLabel: editingChoice == nil ? "Add Account" : "Save", action: save)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxHeight: fixedHeight ? 350 : .infinity, alignment: .top)
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
        #if DEBUG
        .onAppear {
            // `-accountEditor typed` types a name, and `-accountEditor icons` shows the icons (see AccountsView).
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-accountEditor"), index + 1 < arguments.count else { return }

            switch arguments[index + 1] {
            case "typed":
                name = "Visa Platinum"
            case "icons":
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showIcons()
                }
            default:
                break
            }
        }
        #endif
        .sideBarSheet {
            SideBarCloseItem { dismiss() }
        }
    }

    /// The account's icon, where a category has its emoji. Tapping it swaps the keyboard for every icon.
    private var iconTile: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        return Button {
            showIcons()
        } label: {
            AccountIconView(symbol: symbol)
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(Color.PrimaryText)
                .frame(width: 96, height: 96)
                .glassField(in: shape, isFocused: showingIcons)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Icon"))
        .background {
            // Takes focus from the name, which swaps the keyboard for the icons; tapping the name swaps back.
            AccountIconKeyboard(isActive: $showingIcons, selection: symbol) { picked in
                withAnimation(.easeOut(duration: 0.15)) {
                    pickedSymbol = picked
                }
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private func showIcons() {
        showingIcons = true
    }

    func save() {
        // Renaming Main back to nothing restores its default name.
        if editingChoice == .main, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dataController.renameAccount(.main, to: "", symbol: symbol)
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
                dataController.renameAccount(editingChoice, to: name, symbol: symbol)
            } else {
                let account = dataController.addAccount(named: name, symbol: symbol)
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

    @ObservedObject var dataController = DataController.shared
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order), SortDescriptor(\.dateCreated)]) private var accounts: FetchedResults<Account>
    @AppStorage(MainAccount.nameKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var mainName = ""
    @AppStorage(MainAccount.symbolKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) private var mainSymbol = ""

    @State private var showNewAccount = false

    /// Picks one account; with `allowsAll`, nil stands for every account.
    init(title: LocalizedStringKey, selection: Binding<AccountChoice?>, allowsAll: Bool = false) {
        self.title = title
        self.selection = selection
        self.allowsAll = allowsAll
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
                    row(Text("All Accounts"), symbol: "rectangle.stack", isSelected: isAllSelected) {
                        selectAll()
                    }
                }

                ForEach(choices) { choice in
                    row(Text(choice.name), symbol: choice.symbol, isSelected: isSelected(choice)) {
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
                .hiddenInSideBar()

                Spacer()

                GlassIconButton(systemName: "plus", accessibilityLabel: "New Account") {
                    showNewAccount = true
                }
                .hiddenInSideBar()
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
        .sideBarSheet {
            SideBarCloseItem { dismiss() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewAccount = true
                } label: {
                    Label("New Account", systemImage: "plus")
                }
            }
        }
    }

    private func row(_ name: Text, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return Button(action: action) {
            HStack(spacing: 12) {
                AccountIconView(symbol: symbol)
                    .font(.app(.body, weight: .semibold))
                    .foregroundColor(Color.SubtitleText)
                    .frame(width: 24)

                name
                    .font(.app(.body, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(Color.PrimaryText)

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
    /// Left out for a side of a transfer that hasn't been picked.
    var symbol: String?
    var isError = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    AccountIconView(symbol: symbol)
                        .font(.app(.subheadline, weight: .semibold))
                }

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
