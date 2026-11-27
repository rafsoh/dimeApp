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
                    if numberEntryType == 1 {
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
                        Button {
                            isEditingDecimal = true
                        } label: {
                            Text(Locale.current.decimalSeparator ?? ".")
                                .font(.app(size: 34, weight: .regular))
                                .foregroundColor(Color.PrimaryText)
                                .keyFrame(size: proxy.size)
                                .glassBackground(in: keyShape(size: proxy.size), tint: Color.glassTint)
                                .opacity(fractionDigits == 0 ? 0.6 : 1)
                        }
                        .disabled(fractionDigits == 0)
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
        var disabled: Bool {
            price >= 100000000
        }

        Button {
            if disabled {
                return
            }

            if hapticType == 2 {
                hapticTap()
            }

            if numberEntryType == 1 {
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
    /// Tapping the currency symbol; nil leaves it untappable.
    var onCurrencyTap: (() -> Void)?

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

            Text(amount)
                .font(.app(size: largerFontSize, weight: .regular))
                .foregroundColor(Color.PrimaryText)
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .padding(.horizontal, numberEntryType == 2 ? 52 : 0)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            if numberEntryType == 2 {
                DeleteButton()
            }
        }
//        .animation(.snappy.delay(0.1), value: displayNumbers)
    }

    var symbolText: some View {
        Text(currencySymbol)
            .font(.app(size: largerFontSize, weight: .regular))
            .foregroundColor(Color.SubtitleText)
    }

    @ViewBuilder
    func DeleteButton() -> some View {
        GlassIconButton(systemName: "delete.left.fill", accessibilityLabel: "Delete last digit", foreground: Color.PrimaryText) {
            deleteLastDigit()
        }
        .disabled(price == 0 && !isEditingDecimal)
        .opacity(price == 0 && !isEditingDecimal ? 0.4 : 1)
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
