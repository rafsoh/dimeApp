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

    @State var count = 0
    @Binding var counter: Int

    var launchAdd: Bool

    @AppStorage("confetti", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var confetti: Bool = false
    @AppStorage("firstTransactionViewLaunch", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var firstLaunch: Bool = true

    @State var animate = false

    @Namespace private var tabNamespace

    private var isZoomed: Bool {
        UIScreen.main.scale != UIScreen.main.nativeScale
    }

    // tab row height of the legacy bar: 38 "+" button + 15 padding each side
    private static let tabRowHeight: CGFloat = 68
    // height of each glass element in the floating bar (the "+" is a circle of this diameter)
    static let floatingBarHeight: CGFloat = 60
    // the floating bar is shorter than the old opaque strip, so tab content needs no extra clearance
    static let floatingExtraInset: CGFloat = max(floatingBarHeight - tabRowHeight, 0)

    static func floatingBottomMargin(_ bottomEdge: CGFloat) -> CGFloat {
        max(bottomEdge - 10, 8)
    }

    private func startAddTransaction() {
        let impactMed = UIImpactFeedbackGenerator(style: .light)
        impactMed.impactOccurred()

        addTransaction = true
    }

    private func startPulseIfNeeded() {
        if transactions.isEmpty {
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: false)) {
                self.animate.toggle()
            }
        }
    }

    private static let leftGlassTabs = ["Log", "Insights"]
    private static let rightGlassTabs = ["Budget", "Settings"]

    @available(iOS 26, *)
    private func glassTabPill(_ tabs: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                GlassTabItem(tab: tab, currentTab: $currentTab, namespace: tabNamespace)
            }
        }
        .padding(6)
        .frame(height: Self.floatingBarHeight)
        .glassEffect(.regular, in: Capsule())
    }

    // two glass pills around a centered round glass "+". Each glass view carries its own content so icons
    // stay crisp, and the selection highlight slides between tabs, across the "+" as well
    @available(iOS 26, *)
    private var glassTabBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                glassTabPill(Self.leftGlassTabs)

                glassAddButton

                glassTabPill(Self.rightGlassTabs)
            }
        }
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 20)
        .padding(.bottom, Self.floatingBottomMargin(bottomEdge))
    }

    @available(iOS 26, *)
    private var glassAddButton: some View {
        Button {
            startAddTransaction()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color.LightIcon)
                .frame(width: Self.floatingBarHeight, height: Self.floatingBarHeight)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Color.DarkBackground).interactive(), in: Circle())
        .background {
            // pulse rings shown while there are no transactions yet
            ZStack {
                Circle().fill(Color.DarkBackground.opacity(0.6))
                    .frame(width: 80, height: 80)
                    .opacity(self.animate ? 0 : 1)
                    .scaleEffect(self.animate ? 1 : 0.4)

                Circle().fill(Color.DarkBackground.opacity(0.8))
                    .frame(width: 68, height: 68)
                    .opacity(self.animate ? 0 : 1)
                    .scaleEffect(self.animate ? 1 : 0.6)
            }
            .allowsHitTesting(false)
        }
        .onAppear { startPulseIfNeeded() }
        .accessibilityLabel("Add New Transaction")
    }

    // floating glass bar on ios 26, full-width opaque strip on older systems
    @ViewBuilder private var tabBar: some View {
        if #available(iOS 26, *) {
            glassTabBar
        } else {
            tabContent
                .padding(.horizontal, 15)
                .padding(.bottom, bottomEdge - 10)
                .frame(maxWidth: .infinity)
                .background(Color.PrimaryBackground)
        }
    }

    private var tabContent: some View {
        HStack(spacing: 4) {
            TabButton(image: "Log", zoomed: isZoomed, currentTab: $currentTab)

            TabButton(image: "Insights", zoomed: isZoomed, currentTab: $currentTab)

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.DarkBackground.opacity(0.6))
                    .frame(width: 95, height: Self.tabRowHeight)
                    .opacity(self.animate ? 0 : 1)
                    .scaleEffect(self.animate ? 1 : 0.4)

                RoundedRectangle(cornerRadius: 20.5, style: .continuous).fill(Color.DarkBackground.opacity(0.8))
                    .frame(width: 80, height: 53)
                    .opacity(self.animate ? 0 : 1)
                    .scaleEffect(self.animate ? 1 : 0.6)

                Button {
                    startAddTransaction()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(MyButtonStyle())
                .padding(15)
            }
            .onAppear { startPulseIfNeeded() }
            .accessibilityLabel("Add New Transaction")

            TabButton(image: "Budget", zoomed: isZoomed, currentTab: $currentTab)

            TabButton(image: "Settings", zoomed: isZoomed, currentTab: $currentTab)
        }
    }

    var body: some View {
        tabBar
            .fullScreenCover(isPresented: $addTransaction, onDismiss: {
                if confetti {
                    if count != transactions.count {
                        counter += 1
                    }
                }

                if firstLaunch {
                    firstLaunch = false
                }

            }, content: {
                TransactionView(toEdit: nil)
            })
            .onChange(of: launchAdd) { _ in
                addTransaction = true
            }
            .onChange(of: addTransaction) { _ in
                if addTransaction {
                    count = transactions.count
                }
            }
            .onChange(of: transactions.count) { _ in
                if !transactions.isEmpty {
                    self.animate = false
                } else {
                    self.animate = true
                }
            }
            .onOpenURL { url in
                guard
                    url.host == "newExpense"

                else {
                    return
                }

                addTransaction = true
            }
    }
}

struct MyButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(Color.LightIcon)
            .frame(width: 65, height: 38)
            .background(configuration.isPressed ? Color.SubtitleText : Color.DarkBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct BouncyButton: ButtonStyle {
    var duration: Double
    var scale: Double

    public func makeBody(configuration: Self.Configuration) -> some View {
        return configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
//            .scaleEffect(configuration.isPressed ? 1.3 : 1)
            .animation(.easeOut(duration: duration), value: configuration.isPressed)
    }
}

// tab item for the ios 26 glass bar: filled icon when selected, outline otherwise, with a highlight that slides between tabs
@available(iOS 26, *)
struct GlassTabItem: View {
    let tab: String
    @Binding var currentTab: String
    var namespace: Namespace.ID

    private var isSelected: Bool { currentTab == tab }

    var body: some View {
        Button {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                    currentTab = tab
                }
            }
        } label: {
            Image(isSelected ? tab : "\(tab) Outline")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .foregroundColor(isSelected ? Color.DarkIcon : Color.GreyIcon)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.DarkBackground.opacity(0.09))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.75))
                            .matchedGeometryEffect(id: "selectedTab", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab) tab")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
        .accessibilityLabel("\(image) tab")
        .accessibilityAddTraits(
            currentTab == image
                ? [.isButton, .isSelected]
                : .isButton
        )
    }
}
