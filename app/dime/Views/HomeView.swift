//
//  HomeView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import ConfettiSwiftUI
import Foundation
import SwiftUI

class OverallToastPresenter: ObservableObject {
    @Published var showToast: Bool = false
}

enum DeletionType {
    case instant
    case prompt
}

class OverallTransactionManager: ObservableObject {
    @Published var toEdit: Transaction?
    @Published var toDelete: Transaction?
    @Published var showToast: Bool = false
    @Published var showPopup: Bool = false
    @Published var future: Bool = false
}

struct HomeView: View {
    @EnvironmentObject var appLockVM: AppLockViewModel

    @StateObject var toastPresenter = OverallToastPresenter()
    @StateObject var transactionManager = OverallTransactionManager()
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController

    @State var currentTab = "Log"

    var topEdge: CGFloat
    var bottomEdge: CGFloat

    @State var fromURL1: Bool = false
    @State var fromURL2: Bool = false
    @State var fromURL3: Bool = false
    @State var fromURL4: Bool = false

    @State var launchAdd: Bool = false
    @State var launchSearch: Bool = false

    @State var counter = 0

    @EnvironmentObject var tabBarManager: TabBarManager

    @State var showPopup = false

    @State var addTransaction = false

    // Hiding Native TabBar (pre-iOS 26 uses the custom bar; iOS 26 uses the native glass bar)
    init(topEdge: CGFloat, bottomEdge: CGFloat) {
        if #unavailable(iOS 26.0) {
            UITabBar.appearance().isHidden = true
        }
        self.topEdge = topEdge
        self.bottomEdge = bottomEdge
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if #available(iOS 26.0, *) {
                nativeTabs
            } else {
                legacyTabs
            }

            if showPopup {
                Rectangle()
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        transactionManager.showPopup = false
                    }
            }

            DeleteTransactionAlert()
                .offset(y: showPopup ? 0 : 300)
                .environmentObject(transactionManager)

            if appLockVM.isAppLockEnabled && !appLockVM.isAppUnLocked {
                AppLockView()
                    .ignoresSafeArea(.all)
                    .onOpenURL { url in

                        if url.host == "newExpense" {
                            fromURL1 = true
                        } else if url.host == "search" {
                            fromURL2 = true
                        } else if url.host == "insights" {
                            fromURL3 = true
                        } else if url.host == "budget" {
                            fromURL4 = true
                        }
                    }
            }
        }
        .hudToast(isPresented: $toastPresenter.showToast, icon: "checkmark.circle.fill", tint: Color.IncomeGreen,
                  title: "Image Saved", subtitle: "Check it out in Photos")
        .hudToast(isPresented: $transactionManager.showToast, icon: "arrow.uturn.backward.circle.fill", tint: Color.AlertRed,
                  title: "Log Deleted", subtitle: "Tap to Undo",
                  onTap: {
                      withAnimation(.easeInOut(duration: 0.5)) {
                          moc.rollback()
                      }
                      transactionManager.toDelete = nil
                  },
                  onTimeout: {
                      dataController.save()
                      transactionManager.toDelete = nil
                  })
        .onChange(of: transactionManager.showPopup) { newValue in
            withAnimation {
                showPopup = newValue
            }
        }
        .fullScreenCover(item: $transactionManager.toEdit, onDismiss: {
            transactionManager.toEdit = nil
        }) { transaction in
            TransactionView(toEdit: transaction)
        }
        .confettiCannon(counter: $counter, num: 50, openingAngle: Angle(degrees: 0), closingAngle: Angle(degrees: 360), radius: 200)
        .onAppear {
            if appLockVM.isAppLockEnabled && fromURL1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    launchAdd.toggle()
                }

                fromURL1 = false
            }

            if appLockVM.isAppLockEnabled && fromURL2 {
                if #available(iOS 26.0, *) {
                    currentTab = "Search"
                } else {
                    currentTab = "Log"
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    launchSearch.toggle()
                }

                fromURL2 = false
            }

            if appLockVM.isAppLockEnabled && fromURL3 {
                currentTab = "Insights"
            }

            if appLockVM.isAppLockEnabled && fromURL4 {
                currentTab = "Budget"
            }
        }
        .onOpenURL { url in
            if url.host == "search" {
                if #available(iOS 26.0, *) {
                    currentTab = "Search"
                } else {
                    currentTab = "Log"
                }
            } else if url.host == "insights" {
                currentTab = "Insights"
            } else if url.host == "budget" {
                currentTab = "Budget"
            }
        }
    }

    // MARK: - Tab shells

    /// iOS 15–18: page-style TabView driven by the custom tab bar.
    @ViewBuilder
    private var legacyTabs: some View {
        TabView(selection: $currentTab) {
            LogView(topEdge: topEdge, bottomEdge: bottomEdge, launchSearch: launchSearch)
                .ignoresSafeArea(.all)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag("Log")

            InsightsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag("Insights")

            BudgetView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag("Budget")

            SettingsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag("Settings")
        }
        .allowsHitTesting(showPopup ? false : true)
        .environmentObject(toastPresenter)
        .environmentObject(transactionManager)

        CustomTabBar(currentTab: $currentTab, topEdge: topEdge, bottomEdge: bottomEdge, counter: $counter, launchAdd: launchAdd)
            .offset(y: tabBarManager.hideTab ? (70 + bottomEdge) : 0)
    }

    /// iOS 26: native Liquid Glass tab bar with labels, minimising on scroll,
    /// and "New Expense" as the bar's bottom accessory.
    @available(iOS 26.0, *)
    private var nativeTabs: some View {
        TabView(selection: $currentTab) {
            Tab("Log", image: "Log", value: "Log") {
                LogView(topEdge: topEdge, bottomEdge: bottomEdge, launchSearch: launchSearch)
                    .ignoresSafeArea(.all)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tabBarHiddenInNavigation(tabBarManager.inNavigationLink)
            }

            Tab("Insights", image: "Insights", value: "Insights") {
                InsightsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tabBarHiddenInNavigation(tabBarManager.inNavigationLink)
            }

            Tab("Budget", image: "Budget", value: "Budget") {
                BudgetView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tabBarHiddenInNavigation(tabBarManager.inNavigationLink)
            }

            Tab("Settings", image: "Settings", value: "Settings") {
                SettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tabBarHiddenInNavigation(tabBarManager.inNavigationLink)
            }

            Tab(value: "Search", role: .search) {
                LogSearchView()
            }
        }
        .tint(Color.PrimaryText)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NewExpenseAccessory {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                addTransaction = true
            }
        }
        .allowsHitTesting(showPopup ? false : true)
        .environmentObject(toastPresenter)
        .environmentObject(transactionManager)
        .addTransactionFlow(isPresented: $addTransaction, counter: $counter, launchAdd: launchAdd)
    }
}

@available(iOS 26.0, *)
private extension View {
    /// Detail screens pushed from Budget and Settings hide the bar, as the custom bar did.
    func tabBarHiddenInNavigation(_ hidden: Bool) -> some View {
        toolbar(hidden ? .hidden : .automatic, for: .tabBar)
    }
}

/// The "+" of the iOS 26 tab bar: a labelled accessory above the bar that folds inline when the bar minimises.
@available(iOS 26.0, *)
struct NewExpenseAccessory: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text("New Expense")
            } icon: {
                Image(systemName: "plus")
                    .fontWeight(.bold)
            }
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.PrimaryText)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add New Transaction"))
    }
}

struct AppLockView: View {
    @EnvironmentObject var appLockVM: AppLockViewModel

    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "lock.fill")
                .font(.system(size: 65))
                .foregroundColor(Color.DarkIcon.opacity(0.7))

            Text("App Locked")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(Color.PrimaryText)
                .padding(.bottom, 30)

            Button {
                appLockVM.appLockValidation()
            } label: {
                HStack {
                    Image(systemName: "faceid")

                    Text("Unlock App")
                }
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(Color.PrimaryText)
                .padding(.horizontal, 40)
                .padding(.vertical, 15)
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.Outline)
                }
            }

            if appLockVM.enrollmentError {
                Text("Please re-enable Face ID access in the Settings app to unlock application.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.PrimaryBackground)
    }
}
