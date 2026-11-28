//
//  NumberPad.swift
//  dime
//
//  Created by Yumi on 2023-10-29.
//

import SwiftUI
import CoreHaptics

enum AssignedDecimal {
    case none, first, second, third

    init(count: Int) {
        switch count {
        case ...0:
            self = .none
        case 1:
            self = .first
        case 2:
            self = .second
        default:
            self = .third
        }
    }

    var count: Int {
        switch self {
        case .none:
            return 0
        case .first:
            return 1
        case .second:
            return 2
        case .third:
            return 3
        }
    }
}

struct NumberPad: View {
    @Binding var price: Double
    @Binding var category: Category?
    @Binding var isEditingDecimal: Bool
    @Binding var decimalValuesAssigned: AssignedDecimal
    var showingNotePicker: Bool = false
    var fractionDigits: Int = 2
    /// The sum while the calculator's operators are showing. The keys type into it instead of the amount, always with
    /// a decimal point: shifting in cents can't express × 3.
    var expression: Binding<CalculatorExpression>? = nil
    var submit: () -> Void

    @AppStorage("numberEntryType", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var numberEntryType: Int = 1
    @AppStorage("haptics", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
        var hapticType: Int = 1

    var numPadNumbers = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: proxy.size.height * 0.04) {
                ForEach(numPadNumbers, id: \.self) { array in
                    HStack(spacing: proxy.size.width * 0.02) {
                        ForEach(array, id: \.self) { singleNumber in
                            NumberButton(number: singleNumber, size: proxy.size)
                        }
                    }
                }
                HStack(spacing: proxy.size.width * 0.02) {
                    if numberEntryType == 1 && expression == nil {
                        Button {
                            deleteLastDigit()
                        } label: {
                            Image("tag-cross")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .foregroundColor(Color.PrimaryText)
                                .keyFrame(size: proxy.size)
                                .glassBackground(in: keyShape(size: proxy.size), tint: Color.glassTint)
                        }
                        .buttonStyle(NumPadKeyStyle())
                    } else {
                        // With the calculator showing, a zero-decimal currency still needs the point for factors like × 1.1.
                        let decimalDisabled = expression == nil && fractionDigits == 0

                        Button {
                            if let expression {
                                if hapticType == 2 {
                                    hapticTap()
                                }
                                expression.wrappedValue.appendDecimalPoint(fractionDigits: fractionDigits)
                            } else {
                                isEditingDecimal = true
                            }
                        } label: {
                            Text(Locale.current.decimalSeparator ?? ".")
                                .font(.app(size: 34, weight: .regular))
                                .foregroundColor(Color.PrimaryText)
                                .keyFrame(size: proxy.size)
                                .glassBackground(in: keyShape(size: proxy.size), tint: Color.glassTint)
                                .opacity(decimalDisabled ? 0.6 : 1)
                        }
                        .disabled(decimalDisabled)
                        .buttonStyle(NumPadKeyStyle())
                    }

                    NumberButton(number: 0, size: proxy.size)

                    Button {
                        submit()
                    } label: {
                        Group {
                            if #available(iOS 17.0, *) {
                                Image(systemName: "checkmark")
                                    .font(.app(size: 28, weight: .semibold))
                                    .symbolEffect(.bounce.up.byLayer, value: price != 0)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.app(size: 28, weight: .semibold))
                            }
                        }
                        .foregroundColor(Color.LightIcon)
                        .keyFrame(size: proxy.size)
                        .glassBackground(in: keyShape(size: proxy.size), tint: Color.DarkBackground, fallback: Color.DarkBackground)
                    }
                    .buttonStyle(NumPadKeyStyle())
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(.bottom, 15)
        .keyboardAwareHeight(showToolbar: showingNotePicker)
        .onAppear(perform: prepareHaptics)
        .onChange(of: hapticType) { _ in
            prepareHaptics()
        }
    }

    // Only the number pad's own haptic setting plays through the engine, so nothing else needs one made.
    func prepareHaptics() {
        if hapticType == 2 {
            NumberPadHaptics.shared.prepare()
        }
    }

    func hapticTap() {
        NumberPadHaptics.shared.tap()
    }

    public func deleteLastDigit() {
        if numberEntryType == 1 {
            price = AmountEntry.shiftingOut(of: price, fractionDigits: fractionDigits)
        } else if !isEditingDecimal {
            price = AmountEntry.removingWhole(from: price)
        } else if decimalValuesAssigned == .none {
            isEditingDecimal = false
        } else {
            price = AmountEntry.removingDecimal(from: price, assigned: decimalValuesAssigned.count)
            decimalValuesAssigned = AssignedDecimal(count: decimalValuesAssigned.count - 1)
        }
    }

    @ViewBuilder
    private func NumberButton(number: Int, size: CGSize) -> some View {
        // The sum has its own limits, checked as it's typed.
        var disabled: Bool {
            expression == nil && price >= 100000000
        }

        Button {
            if disabled {
                return
            }

            if hapticType == 2 {
                hapticTap()
            }

            if let expression {
                expression.wrappedValue.append(digit: number, fractionDigits: fractionDigits)
            } else if numberEntryType == 1 {
                price = AmountEntry.shiftingIn(number, to: price, fractionDigits: fractionDigits)
            } else if isEditingDecimal {
                guard let next = AmountEntry.appendingDecimal(number, to: price, assigned: decimalValuesAssigned.count, fractionDigits: fractionDigits) else {
                    return
                }

                price = next
                decimalValuesAssigned = AssignedDecimal(count: decimalValuesAssigned.count + 1)
            } else {
                price = AmountEntry.appendingWhole(number, to: price)
            }
        } label: {
            Text("\(number)")
                .font(.app(size: 34, weight: .regular))
                .foregroundColor(Color.PrimaryText)
                .keyFrame(size: size)
                .glassBackground(in: keyShape(size: size), tint: Color.glassTint)
                .opacity(disabled ? 0.6 : 1)
        }
        .disabled(disabled)
        .buttonStyle(NumPadKeyStyle())
    }

    private func keyShape(size: CGSize) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: size.height * NumPadKeyStyle.heightRatio * 0.4, style: .continuous)
    }
}

/// The calculator's operators, shown above the number pad: two over each of the first two columns, and = over ✓.
struct CalculatorOperatorRow: View {
    @Binding var expression: CalculatorExpression
    /// The = key, which puts the total in place of the sum, or says why it can't.
    var equals: () -> Void

    @AppStorage("haptics", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var hapticType: Int = 1

    static let height: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            // The number pad's columns: 32% wide with 2% between them.
            let spacing = proxy.size.width * 0.02
            let column = proxy.size.width * NumPadKeyStyle.widthRatio

            HStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    OperatorKey(.divide)
                    OperatorKey(.multiply)
                }
                .frame(width: column)

                HStack(spacing: spacing) {
                    OperatorKey(.subtract)
                    OperatorKey(.add)
                }
                .frame(width: column)

                Button {
                    tap()
                    equals()
                } label: {
                    Image(systemName: "equal")
                        .font(.app(size: 21, weight: .semibold))
                        .foregroundColor(expression.hasOperator ? Color.PrimaryText : Color.SubtitleText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .glassBackground(in: keyShape, tint: Color.glassTint)
                }
                .buttonStyle(NumPadKeyStyle())
                .frame(width: column)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: Self.height)
    }

    private var keyShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.height * 0.4, style: .continuous)
    }

    private func tap() {
        if hapticType == 2 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// The operator just typed is filled in, the way ✓ is, until its number comes.
    @ViewBuilder
    private func OperatorKey(_ op: CalculatorExpression.Operator) -> some View {
        let isPending = expression.pendingOperator == op

        Button {
            tap()
            expression.apply(op)
        } label: {
            Image(systemName: op.symbolName)
                .font(.app(size: 21, weight: .semibold))
                .foregroundColor(isPending ? Color.LightIcon : Color.PrimaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .glassBackground(
                    in: keyShape,
                    tint: isPending ? Color.DarkBackground : Color.glassTint,
                    fallback: isPending ? Color.DarkBackground : Color.SecondaryBackground
                )
        }
        .buttonStyle(NumPadKeyStyle())
        .accessibilityAddTraits(isPending ? .isSelected : [])
    }
}

extension CalculatorExpression.Failure {
    /// Shown under the sum and in the toast when it can't be used.
    var title: String {
        switch self {
        case .divisionByZero:
            return "Can't Divide by Zero"
        case .negative:
            return "Total Can't Be Negative"
        case .tooLarge:
            return "Total Is Too Large"
        }
    }

    var systemImage: String {
        switch self {
        case .divisionByZero:
            return "divide.circle"
        case .negative:
            return "minus.circle"
        case .tooLarge:
            return "exclamationmark.circle"
        }
    }
}

private struct NumPadKeyStyle: ButtonStyle {
    static let widthRatio: CGFloat = 0.32
    static let heightRatio: CGFloat = 0.22

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            configuration.label
        } else {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.8 : 1)
                .animation(.easeOut(duration: 0.3), value: configuration.isPressed)
                .opacity(configuration.isPressed ? 0.5 : 1)
        }
    }
}

private extension View {
    func keyFrame(size: CGSize) -> some View {
        frame(width: size.width * NumPadKeyStyle.widthRatio, height: size.height * NumPadKeyStyle.heightRatio)
            .contentShape(Rectangle())
    }
}

func splitDouble(_ num: Double) -> [String] {
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    var str = formatter.string(from: NSNumber(value: num))!

    if floor(num) == num {
        str = String(format: "%.0f", num)
    }

    return str.map { String($0) }.filter { $0 != "." }
}

struct NumberPadTextView: View {
    @Binding var price: Double
    @Binding var isEditingDecimal: Bool
    @Binding var decimalValuesAssigned: AssignedDecimal
    var fractionDigits: Int = 2
    /// Nil shows the main currency.
    var currencyCode: String?
    /// The sum while the calculator's operators are showing, shown in place of the amount.
    var expression: Binding<CalculatorExpression>? = nil
    /// The calculator button left of the amount, when the Calculator setting is on.
    var calculatorButton: CalculatorButton? = nil
    /// Tapping the currency symbol; nil leaves it untappable.
    var onCurrencyTap: (() -> Void)?

    struct CalculatorButton {
        var isShowingOperators: Bool
        var action: () -> Void
    }

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode ?? "USD"
    var currencySymbol: String {
        guard let currencyCode else {
            return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
        }

        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currencyCode) ?? currencyCode
    }
//
//    var displayNumbers: [String] {
//        return splitDouble(price)
//    }

    @AppStorage("numberEntryType", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var numberEntryType: Int = 1

    public var amount: String {
        AmountEntry.display(price, entryType: numberEntryType, isEditingDecimal: isEditingDecimal, assigned: decimalValuesAssigned.count, fractionDigits: fractionDigits)
            .replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var largerFontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall:
            return 46
        case .small:
            return 47
        case .medium:
            return 48
        case .large:
            return 50
        case .xLarge:
            return 56
        case .xxLarge:
            return 58
        case .xxxLarge:
            return 62
        default:
            return 50
        }
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            if let onCurrencyTap {
                Button {
                    FeatureTip.currencySymbol.markUsed()
                    onCurrencyTap()
                } label: {
                    symbolText
                }
                .buttonStyle(.plain)
                .featureTip(.currencySymbol)
                .accessibilityLabel(Text("Currency, \(currencyCode ?? currency)"))
                .accessibilityHint(Text("Changes the currency of this transaction"))
            } else {
                symbolText
            }

            if let expression {
                expressionText(expression.wrappedValue)
                    .font(.app(size: largerFontSize, weight: .regular))
                    .accessibilityLabel(Text(verbatim: expression.wrappedValue.isEmpty ? "0" : expression.wrappedValue.text(decimalSeparator: decimalSeparator)))
            } else {
                Text(amount)
                    .font(.app(size: largerFontSize, weight: .regular))
                    .foregroundColor(Color.PrimaryText)
            }
        }
        // A sum runs longer than an amount, so it may shrink further before it's cut off.
        .minimumScaleFactor(expression == nil ? 0.5 : 0.3)
        .lineLimit(1)
        .padding(.horizontal, showsSideButtons ? 52 : 0)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            if numberEntryType == 2 || expression != nil {
                DeleteButton()
            }
        }
        .overlay(alignment: .leading) {
            if let calculatorButton {
                CalculatorToggle(calculatorButton)
            }
        }
//        .animation(.snappy.delay(0.1), value: displayNumbers)
    }

    var decimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }

    /// Room on both sides for the delete and calculator buttons, so the amount stays centred.
    var showsSideButtons: Bool {
        numberEntryType == 2 || expression != nil || calculatorButton != nil
    }

    /// The sum with its operators drawn as symbols, in grey, between the numbers.
    func expressionText(_ expression: CalculatorExpression) -> Text {
        guard !expression.isEmpty else {
            return Text(verbatim: "0").foregroundColor(Color.PrimaryText)
        }

        return expression.tokens.reduce(Text(verbatim: "")) { text, token in
            switch token {
            case .number(let number):
                return text + Text(verbatim: number.replacingOccurrences(of: ".", with: decimalSeparator)).foregroundColor(Color.PrimaryText)
            case .op(let op):
                return text + Text(verbatim: " ") + Text(Image(systemName: op.symbolName)).foregroundColor(Color.SubtitleText) + Text(verbatim: " ")
            }
        }
    }

    func CalculatorToggle(_ button: CalculatorButton) -> some View {
        GlassIconButton(
            systemName: "plus.forwardslash.minus",
            accessibilityLabel: "Calculator",
            foreground: button.isShowingOperators ? Color.LightIcon : Color.PrimaryText,
            tint: button.isShowingOperators ? Color.DarkBackground : Color.glassTint,
            fallback: button.isShowingOperators ? Color.DarkBackground : Color.SecondaryBackground,
            action: button.action
        )
        .accessibilityAddTraits(button.isShowingOperators ? .isSelected : [])
    }

    var symbolText: some View {
        Text(currencySymbol)
            .font(.app(size: largerFontSize, weight: .regular))
            .foregroundColor(Color.SubtitleText)
    }

    @ViewBuilder
    func DeleteButton() -> some View {
        let isEmpty = expression.map { $0.wrappedValue.isEmpty } ?? (price == 0 && !isEditingDecimal)

        GlassIconButton(systemName: "delete.left.fill", accessibilityLabel: "Delete last digit", foreground: Color.PrimaryText) {
            if let expression {
                expression.wrappedValue.deleteLast()
            } else {
                deleteLastDigit()
            }
        }
        // Holding it clears the whole sum.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                guard let expression, !expression.wrappedValue.isEmpty else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                expression.wrappedValue.clear()
            }
        )
        .disabled(isEmpty)
        .opacity(isEmpty ? 0.4 : 1)
    }

    public func deleteLastDigit() {
        if numberEntryType == 1 {
            price = AmountEntry.shiftingOut(of: price, fractionDigits: fractionDigits)
        } else if !isEditingDecimal {
            price = AmountEntry.removingWhole(from: price)
        } else if decimalValuesAssigned == .none {
            isEditingDecimal = false
        } else {
            price = AmountEntry.removingDecimal(from: price, assigned: decimalValuesAssigned.count)
            decimalValuesAssigned = AssignedDecimal(count: decimalValuesAssigned.count - 1)
        }
    }
}

/// The number pad's haptic engine, made, started and played on a queue of its own.
///
/// Making a CHHapticEngine opens an audio session with a synchronous call to the audio server, and starting
/// one waits on it too. When the server was slow to answer, that held the main thread for about 10 seconds
/// as the entry sheet opened (DIME-IOS-X). One engine is kept for the app rather than one per number pad.
final class NumberPadHaptics {
    static let shared = NumberPadHaptics()

    private let queue = DispatchQueue(label: "com.rafaelsoh.dime.numberPadHaptics", qos: .userInitiated)
    // Only touched on `queue`.
    private var engine: CHHapticEngine?
    private var pattern: CHHapticPattern?
    private var unsupported = false

    private init() {}

    func prepare() {
        queue.async {
            _ = self.readyEngine()
        }
    }

    func tap() {
        queue.async {
            guard let engine = self.readyEngine(), let pattern = self.pattern else { return }

            do {
                let player = try engine.makePlayer(with: pattern)
                try engine.start()
                try player.start(atTime: CHHapticTimeImmediate)
            } catch {
                print("Failed to play pattern: \(error.localizedDescription).")
            }
        }
    }

    // Call on `queue`.
    private func readyEngine() -> CHHapticEngine? {
        if let engine {
            return engine
        }

        guard !unsupported else { return nil }

        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            unsupported = true
            return nil
        }

        do {
            let engine = try CHHapticEngine()
            // Stopped between taps so it doesn't hold the audio session; each tap starts it again.
            engine.notifyWhenPlayersFinished { _ in
                .stopEngine
            }
            // A reset (the audio server restarting) stops the engine. The next tap starts it again.
            engine.resetHandler = {}

            pattern = try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticTransient, parameters: [], relativeTime: 0, duration: 1)
            ], parameters: [])

            self.engine = engine
            return engine
        } catch {
            print("There was an error creating the engine: \(error.localizedDescription)")
            return nil
        }
    }
}
