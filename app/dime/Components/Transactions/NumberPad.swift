//
//  NumberPad.swift
//  dime
//
//  Created by Yumi on 2023-10-29.
//

import SwiftUI
import CoreHaptics

enum AssignedDecimal {
    case none, first, second
}

struct NumberPad: View {
    @Binding var price: Double
    @Binding var category: Category?
    @Binding var isEditingDecimal: Bool
    @Binding var decimalValuesAssigned: AssignedDecimal
    var showingNotePicker: Bool = false
    /// Currency being entered, when it differs from the home currency.
    var entryCurrency: String? = nil
    var submit: () -> Void

    @AppStorage("numberEntryType", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var numberEntryType: Int = 1
    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode ?? "USD"

    /// Minor-unit digits of the active currency (2 for EUR, 0 for JPY, 3 for KWD).
    var fractionDigits: Int {
        ExchangeRates.fractionDigits(for: entryCurrency ?? currency)
    }
    @AppStorage("haptics", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
        var hapticType: Int = 1

    var numPadNumbers = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    @State private var engine: CHHapticEngine?

    @ScaledMetric(relativeTo: .title) private var keyFontSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var keyIconSize: CGFloat = 32

    var body: some View {
        VStack(spacing: 10) {
            // borderless keys on one glass panel (flat panel before iOS 26)
            VStack(spacing: 0) {
                ForEach(numPadNumbers, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { number in
                            digitKey(number)
                        }
                    }
                }

                HStack(spacing: 0) {
                    if numberEntryType == 1 {
                        PadKey {
                            typeDigit(0)
                            typeDigit(0)
                        } label: {
                            Text("00")
                                .font(.system(size: keyFontSize * 0.85, weight: .regular, design: .rounded))
                        }
                        .disabled(isAtLimit)
                        .accessibilityLabel(Text("Double zero"))
                    } else {
                        PadKey {
                            if fractionDigits > 0 {
                                isEditingDecimal = true
                            }
                        } label: {
                            Text(".")
                                .font(.system(size: keyFontSize, weight: .regular, design: .rounded))
                        }
                        .accessibilityLabel(Text("Decimal point"))
                    }

                    digitKey(0)

                    PadKey {
                        deleteLastDigit()
                    } label: {
                        Image(systemName: "delete.left")
                            .font(.system(size: keyIconSize * 0.75, weight: .medium, design: .rounded))
                    }
                    .accessibilityLabel(Text("Delete digit"))
                }
            }
            .padding(6)
            .dimeGlass(
                RoundedRectangle(cornerRadius: 28, style: .continuous),
                fallback: Color.SecondaryBackground.opacity(0.6)
            )

            Button {
                submit()
            } label: {
                HStack(spacing: 8) {
                    if #available(iOS 17.0, *) {
                        Image(systemName: "checkmark")
                            .symbolEffect(.bounce.up.byLayer, value: price != 0 && category != nil)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text("Save")
                }
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(Color.LightIcon)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .dimeGlass(
                    RoundedRectangle(cornerRadius: 20, style: .continuous),
                    fallback: Color.DarkBackground,
                    interactive: true,
                    solid: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Save transaction"))
        }
        .padding(.bottom, 15)
        .keyboardAwareHeight(showToolbar: showingNotePicker)
        .onAppear(perform: prepareHaptics)
    }

    func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("There was an error creating the engine: \(error.localizedDescription)")
        }
    }

    func hapticTap() {
        // make sure that the device supports haptics
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        let hapticDict = [
            CHHapticPattern.Key.pattern: [
                [CHHapticPattern.Key.event: [
                    CHHapticPattern.Key.eventType: CHHapticEvent.EventType.hapticTransient,
                    CHHapticPattern.Key.time: CHHapticTimeImmediate,
                    CHHapticPattern.Key.eventDuration: 1.0]
                ]
            ]
        ]

        do {
            let pattern = try CHHapticPattern(dictionary: hapticDict)

            let player = try engine?.makePlayer(with: pattern)

            engine?.notifyWhenPlayersFinished { _ in
                return .stopEngine
            }

            try engine?.start()
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play pattern: \(error.localizedDescription).")
        }
    }

    public func deleteLastDigit() {
        if numberEntryType == 1 {
            price = removingLastDigit(price, fractionDigits: fractionDigits)
        } else if !isEditingDecimal {
            price = Double(Int(price / 10))
        } else {
            switch decimalValuesAssigned {
                case .none:
                    isEditingDecimal = false
                    return
                case .first:
                    price = Double(Int(price))
                    decimalValuesAssigned = .none
                case .second:
                    price = Double(Int(price * 10)) / 10
                    decimalValuesAssigned = .first
            }
        }
    }

    private var isAtLimit: Bool {
        price >= 100000000
    }

    private func typeDigit(_ number: Int) {
        if isAtLimit {
            return
        }

        if hapticType == 2 {
            hapticTap()
        }

        if numberEntryType == 1 {
            price = appendingDigit(number, to: price, fractionDigits: fractionDigits)
        } else {
            if isEditingDecimal {
                switch decimalValuesAssigned {
                    case .none:
                        price += Double(number) / 10
                        decimalValuesAssigned = .first
                    case .first:
                        price += Double(number) / 100
                        decimalValuesAssigned = .second
                    case .second:
                        return
                }
            } else {
                price *= 10
                price += Double(number)
            }
        }
    }

    private func digitKey(_ number: Int) -> some View {
        PadKey {
            typeDigit(number)
        } label: {
            Text("\(number)")
                .font(.system(size: keyFontSize, weight: .regular, design: .rounded))
        }
        .disabled(isAtLimit)
    }
}

/// A borderless number-pad key: fills its cell, shows a soft highlight while pressed.
struct PadKey<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            label()
                .minimumScaleFactor(0.5)
                .foregroundColor(Color.PrimaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PadKeyStyle())
    }
}

struct PadKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.PrimaryText.opacity(configuration.isPressed ? 0.08 : 0))
                    .padding(3)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Cash-register entry: typing shifts digits in from the right, so with 2 minor digits "599" is 5.99
/// and with 0 minor digits (JPY) it is 599. Works in integer minor units to avoid float drift.
func appendingDigit(_ digit: Int, to price: Double, fractionDigits: Int) -> Double {
    let factor = pow(10, Double(fractionDigits))
    let units = (price * factor).rounded() * 10 + Double(digit)
    return units / factor
}

func removingLastDigit(_ price: Double, fractionDigits: Int) -> Double {
    let factor = pow(10, Double(fractionDigits))
    let units = ((price * factor).rounded() / 10).rounded(.down)
    return units / factor
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

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    /// Currency the amount is being entered in, when it differs from the home currency.
    var entryCurrency: String? = nil

    var currencySymbol: String {
        let code = entryCurrency ?? currency
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: code) ?? code
    }

    @AppStorage("numberEntryType", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var numberEntryType: Int = 1

    var fractionDigits: Int {
        ExchangeRates.fractionDigits(for: entryCurrency ?? currency)
    }

    public var amount: String {
        if numberEntryType == 1 {
            return String(format: "%.\(fractionDigits)f", price)
        }
        if isEditingDecimal {
            switch decimalValuesAssigned {
                case .none:
                    return String(format: "%.0f", price) + "."
                case .first:
                    return String(format: "%.1f", price)
                case .second:
                    return String(format: "%.2f", price)
            }
        }
        return String(format: "%.0f", price)
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
            return dynamicTypeSize.isAccessibilitySize ? 68 : 50
        }
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Group {
                Text(currencySymbol + " ")
                    .font(.system(.largeTitle, design: .rounded))
                    .foregroundColor(Color.SubtitleText)

                + Text(amount)
                    .font(.system(size: largerFontSize, weight: .regular, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
            }
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    public func deleteLastDigit() {
        if numberEntryType == 1 {
            price = removingLastDigit(price, fractionDigits: fractionDigits)
        } else if !isEditingDecimal {
            price = Double(Int(price / 10))
        } else {
            switch decimalValuesAssigned {
                case .none:
                    isEditingDecimal = false
                    return
                case .first:
                    price = Double(Int(price))
                    decimalValuesAssigned = .none
                case .second:
                    price = Double(Int(price * 10)) / 10
                    decimalValuesAssigned = .first
            }
        }
    }
}
