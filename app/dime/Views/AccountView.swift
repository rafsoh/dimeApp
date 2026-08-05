//
//  AccountView.swift
//  dime
//

import Combine
import Popovers
import SwiftUI

enum AccountViewMode {
    case settings, transaction
}

struct AccountView: View {
    var mode: AccountViewMode

    @State var newAccount = false
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""
    @State var positive = false

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)]) private var accounts: FetchedResults<Account>

    var disabled: Bool {
        accounts.count >= 24
    }

    var body: some View {
        VStack(spacing: 5) {
            AccountListView(
                mode: mode,
                showToast: $showToast,
                toastTitle: $toastTitle,
                toastImage: $toastImage,
                positive: $positive
            )

            HStack {
                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                    Text("New")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .lineLimit(1)
                }
                .foregroundColor(Color.PrimaryText)
                .padding(6)
                .padding(.horizontal, 4.5)
                .background(Color.SecondaryBackground, in: Capsule())
                .opacity(disabled ? 0.5 : 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    if disabled {
                        showToast = true
                        toastImage = "exclamationmark.triangle.fill"
                        toastTitle = "Limit Exceeded"
                        positive = false
                    } else {
                        newAccount = true
                    }
                }
            }
            .padding(25)
        }
        .sheet(isPresented: $newAccount) {
            if #available(iOS 16.0, *) {
                NewAccountAlert(bottomSpacers: false)
                    .presentationDetents([.height(270)])
            } else {
                NewAccountAlert(bottomSpacers: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.keyboard, edges: .all)
        .background(Color.PrimaryBackground)
    }
}

struct AccountListView: View {
    var mode: AccountViewMode

    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var moc
    @Environment(\.colorScheme) var systemColorScheme
    @EnvironmentObject var dataController: DataController

    @AppStorage("bottomEdge", store: UserDefaults(suiteName: "group.com.vishwajeet.dime")) var bottomEdge: Double = 15

    @State private var offset: CGFloat = 0
    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)]) private var accounts: FetchedResults<Account>
    @State var isEditing = false

    @State private var deleteMode = false
    @State private var toDelete: Account?
    @State private var toEdit: Account?

    @Binding var showToast: Bool
    @Binding var toastTitle: String
    @Binding var toastImage: String
    @Binding var positive: Bool

    var toastColor: Color {
        positive ? Color.IncomeGreen : Color.AlertRed
    }

    var body: some View {
        VStack(spacing: 5) {
            if showToast {
                HStack(spacing: 6.5) {
                    Image(systemName: toastImage)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(toastColor)

                    Text(toastTitle)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .lineLimit(1)
                        .foregroundColor(toastColor)
                }
                .padding(8)
                .background(toastColor.opacity(0.23), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                .frame(maxWidth: 250)
                .frame(height: 35)
                .padding(20)
            } else {
                HStack(spacing: 8) {
                    if mode == .settings {
                        Circle()
                            .fill(Color.SecondaryBackground)
                            .frame(width: 33, height: 33)
                            .overlay {
                                Image(systemName: "chevron.left")
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                    .foregroundColor(Color.SubtitleText)
                                    .offset(y: 0.8)
                            }
                            .onTapGesture {
                                self.presentationMode.wrappedValue.dismiss()
                            }
                    } else {
                        Circle()
                            .fill(Color.SecondaryBackground)
                            .frame(width: 33, height: 33)
                            .overlay {
                                Image(systemName: "chevron.down")
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                    .foregroundColor(Color.SubtitleText)
                                    .offset(y: 0.8)
                            }
                            .onTapGesture {
                                dismiss()
                            }
                    }

                    Spacer()

                    if accounts.count > 1 {
                        if isEditing {
                            Circle()
                                .fill(Color.IncomeGreen.opacity(0.23))
                                .frame(width: 33, height: 33)
                                .overlay {
                                    Image(systemName: "checkmark")
                                        .font(.system(.callout, design: .rounded).weight(.semibold))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        .foregroundColor(Color.IncomeGreen)
                                }
                                .onTapGesture {
                                    withAnimation {
                                        isEditing.toggle()
                                    }
                                }
                        } else {
                            Circle()
                                .fill(Color.SecondaryBackground)
                                .frame(width: 33, height: 33)
                                .overlay {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(.system(.callout, design: .rounded).weight(.semibold))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        .foregroundColor(Color.SubtitleText)
                                }
                                .onTapGesture {
                                    withAnimation {
                                        isEditing.toggle()
                                    }
                                }
                        }
                    }
                }
                .frame(height: 35)
                .frame(maxWidth: .infinity)
                .overlay {
                    Text("Accounts")
                        .font(.system(.title3, design: .rounded).weight(mode == .settings ? .semibold : .medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                .padding(20)
            }

            VStack {
                if #available(iOS 16.0, *) {
                    List {
                        Section(header: Text("ACCOUNTS").foregroundColor(Color.SubtitleText)) {
                            accountRows
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .environment(\.editMode, .constant(self.isEditing ? EditMode.active : EditMode.inactive))
                } else {
                    List {
                        Section(header: Text("ACCOUNTS").foregroundColor(Color.SubtitleText)) {
                            accountRows
                        }
                    }
                    .environment(\.editMode, .constant(self.isEditing ? EditMode.active : EditMode.inactive))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.PrimaryBackground)
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: toDelete) { _ in
            if toDelete != nil {
                deleteMode = true
            }
        }
        .fullScreenCover(isPresented: $deleteMode, onDismiss: {
            toDelete = nil
        }) {
            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        deleteMode = false
                    }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text("Delete '\(toDelete?.wrappedName ?? "")'?")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.PrimaryText)

                    Text("This action cannot be undone. Existing transactions will keep their history without this account.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.SubtitleText)
                        .padding(.bottom, 15)

                    Button {
                        withAnimation {
                            if let gonnaDelete = toDelete {
                                moc.delete(gonnaDelete)
                            }
                            dataController.save()
                        }
                        toDelete = nil
                        deleteMode = false
                    } label: {
                        Text("Delete")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(height: 45)
                            .frame(maxWidth: .infinity)
                            .background(Color.AlertRed, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .padding(.bottom, 8)

                    Button {
                        withAnimation(.easeOut(duration: 0.7)) {
                            deleteMode = false
                            offset = 0
                        }
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.PrimaryText.opacity(0.9))
                            .frame(height: 45)
                            .frame(maxWidth: .infinity)
                            .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 13).fill(Color.PrimaryBackground).shadow(color: systemColorScheme == .dark ? Color.clear : Color.gray.opacity(0.25), radius: 6))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(systemColorScheme == .dark ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
                .offset(y: offset)
                .padding(.horizontal, 17)
                .padding(.bottom, bottomEdge == 0 ? 13 : bottomEdge)
            }
            .edgesIgnoringSafeArea(.all)
            .background(BackgroundBlurView())
        }
        .sheet(item: $toEdit, onDismiss: {
            toEdit = nil
        }) { account in
            if #available(iOS 16.0, *) {
                EditAccountAlert(
                    toEdit: account,
                    showRootToast: $showToast,
                    rootToastTitle: $toastTitle,
                    rootToastImage: $toastImage,
                    positive: $positive,
                    bottomSpacers: false
                )
                .presentationDetents([.height(270)])
            } else {
                EditAccountAlert(
                    toEdit: account,
                    showRootToast: $showToast,
                    rootToastTitle: $toastTitle,
                    rootToastImage: $toastImage,
                    positive: $positive,
                    bottomSpacers: true
                )
            }
        }
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
    }

    @ViewBuilder
    private var accountRows: some View {
        if accounts.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(.largeTitle, design: .rounded).weight(.light))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundColor(Color.SubtitleText)

                Text("no_accounts")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.SubtitleText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 37)
            .listRowBackground(Color.SettingsBackground)
        } else {
            ForEach(accounts) { account in
                HStack(spacing: 10) {
                    Text(account.wrappedEmoji)
                        .font(.system(.subheadline, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    Text(account.wrappedName)
                        .font(.system(.body, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .lineLimit(1)
                        .foregroundColor(toDelete == account ? Color.AlertRed : Color.PrimaryText)

                    Spacer()

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: account.wrappedColour))
                        .frame(width: 20, height: 20)
                }
                .padding(.vertical, 5)
                .listRowBackground(Color.SettingsBackground)
                .listRowSeparatorTint(Color.Outline)
                .contentShape(Rectangle())
                .onTapGesture {
                    toEdit = account
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
                        toEdit = account
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .tint(Color("Yellow"))
                }
            }
            .onMove(perform: moveItem)
        }
    }

    private func moveItem(at sets: IndexSet, destination: Int) {
        let itemToMove = sets.first!

        if itemToMove < destination {
            var startIndex = itemToMove + 1
            let endIndex = destination - 1
            var startOrder = accounts[itemToMove].order
            while startIndex <= endIndex {
                accounts[startIndex].order = startOrder
                startOrder = startOrder + 1
                startIndex = startIndex + 1
            }
            accounts[itemToMove].order = startOrder
        } else if destination < itemToMove {
            var startIndex = destination
            let endIndex = itemToMove - 1
            var startOrder = accounts[destination].order + 1
            let newOrder = accounts[destination].order
            while startIndex <= endIndex {
                accounts[startIndex].order = startOrder
                startOrder = startOrder + 1
                startIndex = startIndex + 1
            }
            accounts[itemToMove].order = newOrder
        }

        dataController.save()
    }
}

struct NewAccountAlert: View {
    let bottomSpacers: Bool

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var moc
    @Environment(\.colorScheme) var systemColorScheme
    @EnvironmentObject var dataController: DataController

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)]) private var accounts: FetchedResults<Account>
    @State private var availableColours: [String] = Color.colorArray

    @State private var newName = ""
    @State private var newEmoji = ""
    @State private var showingColourPicker = false
    @State private var selectedColour: String = "#FFFFFF"

    @FocusState var focusedField: FocusedField?

    enum FocusedField: Hashable {
        case emoji, name
    }

    @State var outcome = CategoryError.none
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""
    @State var positive = false

    var toastColor: Color {
        positive ? Color.IncomeGreen : Color.AlertRed
    }

    @State var showNativePicker: Bool = false
    @State var customSelectedColor = Color.white

    var body: some View {
        VStack {
            VStack {
                VStack {
                    if showToast {
                        HStack(spacing: 5) {
                            Image(systemName: toastImage)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .foregroundColor(toastColor)

                            Text(toastTitle)
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .lineLimit(1)
                                .foregroundColor(toastColor)
                        }
                        .padding(6)
                        .background(toastColor.opacity(0.23), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                        .frame(maxWidth: 200)
                    } else {
                        Text("New Account")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .padding(.top, 4)
                    }
                }
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(Color.SecondaryBackground, in: Circle())
                            .contentShape(Circle())
                    }
                }

                Spacer()

                ZStack {
                    EmojiTextField(text: $newEmoji)
                        .focused($focusedField, equals: .emoji)
                        .onReceive(Just(newEmoji), perform: { _ in
                            if String(self.newEmoji.onlyEmoji().suffix(1)) != self.newEmoji.onlyEmoji().prefix(1) {
                                self.newEmoji = String(self.newEmoji.onlyEmoji().suffix(1))
                            } else {
                                self.newEmoji = String(self.newEmoji.onlyEmoji().prefix(1))
                            }
                        })
                        .font(.system(size: 160))
                        .padding(8)
                        .frame(width: 80, height: 80, alignment: .center)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder((focusedField == .emoji && !showingColourPicker) ? Color.SubtitleText : Color.clear, lineWidth: 2.2)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.SecondaryBackground))
                        }

                    if newEmoji == "" {
                        Image("emoji-happy")
                            .resizable()
                            .foregroundColor(Color.PrimaryText)
                            .frame(width: 35, height: 35, alignment: .center)
                            .allowsHitTesting(false)
                    }
                }

                Spacer()

                HStack {
                    Button {
                        showingColourPicker = true
                    } label: {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(hex: selectedColour))
                            .padding(8)
                            .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .frame(width: 50, height: 50)
                            .overlay {
                                if showingColourPicker {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(Color.SubtitleText, lineWidth: 2.2)
                                }
                            }
                    }
                    .popover(present: $showingColourPicker, attributes: {
                        $0.position = .absolute(
                            originAnchor: .topLeft,
                            popoverAnchor: .bottomLeft
                        )
                        $0.rubberBandingMode = .none
                        $0.sourceFrameInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0)
                        $0.presentation.animation = .easeInOut(duration: 0.2)
                        $0.dismissal.animation = .easeInOut(duration: 0.3)
                    }) {
                        ColourPickerView(selectedColor: $selectedColour, showMenu: $showingColourPicker, showNativePicker: $showNativePicker)
                            .environment(\.managedObjectContext, self.moc)
                    } background: {
                        Color.PrimaryBackground.opacity(0.3)
                    }

                    NormalTextField(text: $newName, placeholder: "Account Name", action: verification)
                        .focused($focusedField, equals: .name)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 5)
                        .foregroundColor(Color.PrimaryText)
                        .frame(height: 50)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder((focusedField == .name && !showingColourPicker) ? Color.SubtitleText : Color.clear, lineWidth: 2.2)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.SecondaryBackground))
                        }

                    Button {
                        verification()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(Color.LightIcon)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .frame(width: 50, height: 50)
                            .background(Color.DarkBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
            .padding(13)
            .frame(maxHeight: bottomSpacers ? 350 : .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.PrimaryBackground)
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .onChange(of: customSelectedColor) { _ in
            selectedColour = customSelectedColor.toHex() ?? "#FFFFFF"
        }
        .colorPickerSheet(isPresented: $showNativePicker, selection: $customSelectedColor, supportsAlpha: false, title: "")
        .onAppear {
            accounts.forEach { account in
                if availableColours.contains(account.wrappedColour) {
                    availableColours.remove(at: availableColours.firstIndex(of: account.wrappedColour) ?? 0)
                }
            }

            if availableColours.isEmpty {
                selectedColour = "#FFFFFF"
            } else {
                selectedColour = availableColours[0]
            }
        }
    }

    func verification() {
        let results = dataController.accountCheck(name: newName, emoji: newEmoji)
        outcome = results.error

        if outcome != .none {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            switch outcome {
            case .incomplete:
                toastTitle = "Incomplete Entry"
                toastImage = "questionmark.app"
            case .missingEmoji:
                toastTitle = "Missing Emoji"
                toastImage = "person.fill"
                focusedField = .emoji
            case .missingName:
                toastTitle = "Missing Name"
                toastImage = "character.cursor.ibeam"
                focusedField = .name
            case .duplicate:
                toastTitle = "Duplicate Found"
                toastImage = "externaldrive"
            case .duplicateEmoji:
                toastTitle = "Duplicate Emoji"
                toastImage = "person.fill"
                focusedField = .emoji
            case .duplicateName:
                toastTitle = "Duplicate Name"
                toastImage = "character.cursor.ibeam"
                focusedField = .name
            default:
                return
            }

            positive = false
            showToast = true
        } else {
            toastTitle = "Added \(newName)"

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            let account = Account(context: moc)
            account.name = newName.trimmingCharacters(in: .whitespaces).capitalized
            account.emoji = newEmoji
            account.dateCreated = Date.now
            account.id = UUID()
            account.colour = selectedColour
            account.order = results.order

            dataController.save()

            newName = ""
            newEmoji = ""

            availableColours = Color.colorArray
            accounts.forEach { account in
                if availableColours.contains(account.wrappedColour) {
                    availableColours.remove(at: availableColours.firstIndex(of: account.wrappedColour) ?? 0)
                }
            }

            if availableColours.isEmpty {
                selectedColour = "#FFFFFF"
            } else {
                selectedColour = availableColours[0]
            }

            focusedField = .emoji
            toastImage = "checkmark.circle.fill"
            positive = true
            showToast = true
        }
    }
}

struct EditAccountAlert: View {
    let toEdit: Account
    @Binding var showRootToast: Bool
    @Binding var rootToastTitle: String
    @Binding var rootToastImage: String
    @Binding var positive: Bool
    let bottomSpacers: Bool

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController

    @State private var newName = ""
    @State private var newEmoji = ""
    @State private var showingColourPicker = false
    @State private var selectedColour: String = "#FFFFFF"

    @FocusState var focusedField: FocusedField?

    enum FocusedField: Hashable {
        case emoji, name
    }

    @State var outcome = CategoryError.none
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""

    var toastColor: Color {
        Color.AlertRed
    }

    @State var showNativePicker: Bool = false
    @State var customSelectedColor = Color.white

    var body: some View {
        VStack {
            VStack {
                VStack {
                    if showToast {
                        HStack(spacing: 5) {
                            Image(systemName: toastImage)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .foregroundColor(toastColor)

                            Text(toastTitle)
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .lineLimit(1)
                                .foregroundColor(toastColor)
                        }
                        .padding(6)
                        .background(toastColor.opacity(0.23), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                        .frame(maxWidth: 200)
                    } else {
                        Text("Edit Account")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .padding(.top, 4)
                    }
                }
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(Color.SecondaryBackground, in: Circle())
                            .contentShape(Circle())
                    }
                }

                Spacer()

                ZStack {
                    EmojiTextField(text: $newEmoji)
                        .focused($focusedField, equals: .emoji)
                        .onReceive(Just(newEmoji), perform: { _ in
                            if String(self.newEmoji.onlyEmoji().suffix(1)) != self.newEmoji.onlyEmoji().prefix(1) {
                                self.newEmoji = String(self.newEmoji.onlyEmoji().suffix(1))
                            } else {
                                self.newEmoji = String(self.newEmoji.onlyEmoji().prefix(1))
                            }
                        })
                        .font(.system(size: 160))
                        .padding(8)
                        .frame(width: 80, height: 80, alignment: .center)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder((focusedField == .emoji && !showingColourPicker) ? Color.SubtitleText : Color.clear, lineWidth: 2.2)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.SecondaryBackground))
                        }
                }

                Spacer()

                HStack {
                    Button {
                        showingColourPicker = true
                    } label: {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(hex: selectedColour))
                            .padding(8)
                            .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .frame(width: 50, height: 50)
                            .overlay {
                                if showingColourPicker {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(Color.SubtitleText, lineWidth: 2.2)
                                }
                            }
                    }
                    .popover(present: $showingColourPicker, attributes: {
                        $0.position = .absolute(
                            originAnchor: .topLeft,
                            popoverAnchor: .bottomLeft
                        )
                        $0.rubberBandingMode = .none
                        $0.sourceFrameInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0)
                        $0.presentation.animation = .easeInOut(duration: 0.2)
                        $0.dismissal.animation = .easeInOut(duration: 0.3)
                    }) {
                        ColourPickerView(selectedColor: $selectedColour, showMenu: $showingColourPicker, showNativePicker: $showNativePicker, toEdit: nil)
                            .environment(\.managedObjectContext, self.moc)
                    } background: {
                        Color.PrimaryBackground.opacity(0.3)
                    }

                    NormalTextField(text: $newName, placeholder: "Account Name", action: verification)
                        .focused($focusedField, equals: .name)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 5)
                        .foregroundColor(Color.PrimaryText)
                        .frame(height: 50)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder((focusedField == .name && !showingColourPicker) ? Color.SubtitleText : Color.clear, lineWidth: 2.2)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.SecondaryBackground))
                        }

                    Button {
                        verification()
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundColor(Color.LightIcon)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .frame(width: 50, height: 50)
                            .background(Color.DarkBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
            .padding(13)
            .frame(maxHeight: bottomSpacers ? 350 : .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.PrimaryBackground)
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .onChange(of: customSelectedColor) { _ in
            selectedColour = customSelectedColor.toHex() ?? "#FFFFFF"
        }
        .colorPickerSheet(isPresented: $showNativePicker, selection: $customSelectedColor, supportsAlpha: false, title: "")
        .onAppear {
            newName = toEdit.wrappedName
            newEmoji = toEdit.wrappedEmoji
            selectedColour = toEdit.wrappedColour
        }
    }

    func verification() {
        let results = dataController.accountCheckEdit(name: newName, emoji: newEmoji, toEdit: toEdit)
        outcome = results.error

        if outcome != .none {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            switch outcome {
            case .incomplete:
                toastTitle = "Incomplete Entry"
                toastImage = "questionmark.app"
            case .missingEmoji:
                toastTitle = "Missing Emoji"
                toastImage = "person.fill"
                focusedField = .emoji
            case .missingName:
                toastTitle = "Missing Name"
                toastImage = "character.cursor.ibeam"
                focusedField = .name
            case .duplicate:
                toastTitle = "Duplicate Found"
                toastImage = "externaldrive"
            case .duplicateEmoji:
                toastTitle = "Duplicate Emoji"
                toastImage = "person.fill"
                focusedField = .emoji
            case .duplicateName:
                toastTitle = "Duplicate Name"
                toastImage = "character.cursor.ibeam"
                focusedField = .name
            default:
                return
            }

            showToast = true
        } else {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            toEdit.name = newName.trimmingCharacters(in: .whitespaces).capitalized
            toEdit.emoji = newEmoji
            toEdit.colour = selectedColour

            dataController.save()

            rootToastTitle = "Successfully Edited"
            rootToastImage = "checkmark.circle.fill"
            positive = true
            showRootToast = true
            dismiss()
        }
    }
}
