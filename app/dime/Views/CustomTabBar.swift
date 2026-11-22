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
    @Binding var addTransaction: Bool

    @State var checkingFace: Bool = false

    private var isZoomed: Bool {
        UIScreen.main.scale != UIScreen.main.nativeScale
    }

    var body: some View {
        HStack(spacing: 4) {
            TabButton(image: "Log", zoomed: isZoomed, currentTab: $currentTab)

            TabButton(image: "Insights", zoomed: isZoomed, currentTab: $currentTab)

            Button {
                let impactMed = UIImpactFeedbackGenerator(style: .light)
                impactMed.impactOccurred()

                addTransaction = true

            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.LightIcon)
                    .frame(width: 65, height: 38)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassBackground(in: Capsule(), tint: Color.DarkBackground, fallback: Color.DarkBackground)
            .padding(15)
            .accessibilityLabel("Add New Transaction")

            TabButton(image: "Budget", zoomed: isZoomed, currentTab: $currentTab)

            TabButton(image: "Settings", zoomed: isZoomed, currentTab: $currentTab)
        }
        .padding(.horizontal, 15)
        .padding(.bottom, bottomEdge - 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {}
        .background {
            LinearGradient(stops: [
                .init(color: Color.PrimaryBackground.opacity(0), location: 0),
                .init(color: Color.PrimaryBackground.opacity(0.85), location: 0.45),
                .init(color: Color.PrimaryBackground, location: 1)
            ], startPoint: .top, endPoint: .bottom)
                .padding(.top, -30)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }
}

private struct AddTransactionSheet: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var counter: Int
    var launchAdd: Bool

    @FetchRequest(sortDescriptors: []) private var transactions: FetchedResults<Transaction>

    @State private var count = 0

    @AppStorage("confetti", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var confetti: Bool = false
    @AppStorage("firstTransactionViewLaunch", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var firstLaunch: Bool = true

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: {
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
                isPresented = true
            }
            .onChange(of: isPresented) { _ in
                if isPresented {
                    count = transactions.count
                }
            }
            .onOpenURL { url in
                guard
                    url.host == "newExpense"

                else {
                    return
                }

                isPresented = true
            }
    }
}

extension View {
    func addTransactionSheet(isPresented: Binding<Bool>, counter: Binding<Int>, launchAdd: Bool) -> some View {
        modifier(AddTransactionSheet(isPresented: isPresented, counter: counter, launchAdd: launchAdd))
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

struct StaticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct TabButton: View {
    var image: String
    var zoomed: Bool
    @Binding var currentTab: String

    var body: some View {
        Button {
            var transaction = SwiftUI.Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                currentTab = image
            }
        } label: {
            Image(image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 28, maxHeight: 28)
                .frame(maxWidth: .infinity)
                .foregroundColor(currentTab == image ? Color.DarkIcon : Color.GreyIcon)
        }
        .buttonStyle(StaticButtonStyle())
        .accessibilityLabel("\(image) tab")
        .accessibilityAddTraits(
            currentTab == image
                ? [.isButton, .isSelected]
                : .isButton
        )
    }
}
