//
//  CustomTabBar.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import Foundation
import SwiftUI

struct CustomTabBar: View {
    @EnvironmentObject var appLockVM: AppLockViewModel
    @Binding var currentTab: String
    var topEdge: CGFloat
    var bottomEdge: CGFloat
    @State var addTransaction: Bool = false

    @State var checkingFace: Bool = false

    @FetchRequest(sortDescriptors: []) private var transactions: FetchedResults<Transaction>

    @Binding var counter: Int

    var launchAdd: Bool

    @State var animate = false

    private var isZoomed: Bool {
        UIScreen.main.scale != UIScreen.main.nativeScale
    }

    var body: some View {
        HStack(spacing: 4) {
            TabButton(image: "Log", zoomed: isZoomed, currentTab: $currentTab)

            TabButton(image: "Insights", zoomed: isZoomed, currentTab: $currentTab)

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.DarkBackground.opacity(0.6))
                    .frame(width: 95, height: 68)
                    .opacity(self.animate ? 0 : 1)
                    .scaleEffect(self.animate ? 1 : 0.4)

                RoundedRectangle(cornerRadius: 20.5, style: .continuous).fill(Color.DarkBackground.opacity(0.8))
                    .frame(width: 80, height: 53)
                    .opacity(self.animate ? 0 : 1)
                    .scaleEffect(self.animate ? 1 : 0.6)

                Button {
                    let impactMed = UIImpactFeedbackGenerator(style: .light)
                    impactMed.impactOccurred()

                    addTransaction = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(MyButtonStyle())
                .padding(15)
            }
            .onAppear {
                if transactions.isEmpty {
                    withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: false)) {
                        self.animate.toggle()
                    }
                }
            }
            .accessibilityLabel("Add New Transaction")

            TabButton(image: "Budget", zoomed: isZoomed, currentTab: $currentTab)

            TabButton(image: "Settings", zoomed: isZoomed, currentTab: $currentTab)
        }
        .padding(.horizontal, 15)
        .padding(.bottom, bottomEdge - 10)
        .frame(maxWidth: .infinity)
        .background(Color.PrimaryBackground)
        .addTransactionFlow(isPresented: $addTransaction, counter: $counter, launchAdd: launchAdd)
        .onChange(of: transactions.count) { _ in
            if !transactions.isEmpty {
                self.animate = false
            } else {
                self.animate = true
            }
        }
    }
}

/// Presents the new-transaction screen: from a button, the `dimeapp://newExpense` link,
/// or `launchAdd` after unlocking. Fires confetti when an entry was actually added.
/// Shared by the custom tab bar and the native iOS 26 tab bar.
struct AddTransactionFlow: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var counter: Int
    var launchAdd: Bool

    @FetchRequest(sortDescriptors: []) private var transactions: FetchedResults<Transaction>
    @AppStorage("confetti", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var confetti: Bool = false
    @AppStorage("firstTransactionViewLaunch", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var firstLaunch: Bool = true
    @State private var count = 0

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented, onDismiss: {
                if confetti && count != transactions.count {
                    counter += 1
                }

                if firstLaunch {
                    firstLaunch = false
                }
            }, content: {
                TransactionView(toEdit: nil)
            })
            .onChange(of: launchAdd) { _ in
                isPresented = true
            }
            .onChange(of: isPresented) { newValue in
                if newValue {
                    count = transactions.count
                }
            }
            .onOpenURL { url in
                if url.host == "newExpense" {
                    isPresented = true
                }
            }
    }
}

extension View {
    func addTransactionFlow(isPresented: Binding<Bool>, counter: Binding<Int>, launchAdd: Bool) -> some View {
        modifier(AddTransactionFlow(isPresented: isPresented, counter: counter, launchAdd: launchAdd))
    }
}

struct MyButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(Color.LightIcon)
            .frame(width: 65, height: 38)
            .dimeGlass(
                RoundedRectangle(cornerRadius: 13, style: .continuous),
                fallback: configuration.isPressed ? Color.SubtitleText : Color.DarkBackground,
                interactive: true,
                solid: true
            )
    }
}

struct BouncyButton: ButtonStyle {
    var duration: Double
    var scale: Double

    public func makeBody(configuration: Self.Configuration) -> some View {
        return configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: duration), value: configuration.isPressed)
    }
}

struct TabButton: View {
    var image: String
    var zoomed: Bool
    @Binding var currentTab: String

    var body: some View {
        Button {
            DispatchQueue.main.async {
                currentTab = image
            }
        } label: {
            Image(image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 28, maxHeight: 28)
                .animation(.easeInOut(duration: 0.3), value: currentTab)
                .frame(maxWidth: .infinity)
                .foregroundColor(currentTab == image ? Color.DarkIcon : Color.GreyIcon)
        }
        .buttonStyle(BouncyButton(duration: 0.3, scale: 0.6))
        .accessibilityLabel(Text(LocalizedStringKey(image)))
        .accessibilityAddTraits(
            currentTab == image
                ? [.isButton, .isSelected]
                : .isButton
        )
    }
}
