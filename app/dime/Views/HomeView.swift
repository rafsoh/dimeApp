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
    @Published var showPopup: Bool = false
    @Published var future: Bool = false
}

struct HomeView: View {
    @EnvironmentObject var appLockVM: AppLockViewModel

    @StateObject var toastPresenter = OverallToastPresenter()
    @StateObject var transactionManager = OverallTransactionManager()
    @EnvironmentObject var dataController: DataController

    @State var currentTab = "Log"

    @AppStorage("firstWeekday", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var firstWeekday: Int = 1
    @AppStorage("firstDayOfMonth", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var firstDayOfMonth: Int = 1

    @AppStorage(AppFont.storageKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var appFont: Int = 0

    // Tabs cache date ranges in @State, so rebuild them when the time frame settings change.
    var timeFrameID: String {
        "\(firstWeekday)-\(firstDayOfMonth)"
    }

    var topEdge: CGFloat
    var bottomEdge: CGFloat

    @State var fromURL1: Bool = false
    @State var fromURL2: Bool = false
    @State var fromURL3: Bool = false
    @State var fromURL4: Bool = false
    @State var fromURL5: Bool = false

    @State var launchAdd: Bool = false
    @State var launchSearch: Bool = false

    @State var counter = 0

    @EnvironmentObject var tabBarManager: TabBarManager

    @State private var tabBarTop: CGFloat?

    @State private var addTransaction = false
    @State private var usesVerticalBar = false

    private static let addTab = "Add"

    private var tabSelection: Binding<String> {
        Binding {
            currentTab
        } set: { tab in
            if tab == Self.addTab {
                addTransaction = true
            } else {
                currentTab = tab
            }
        }
    }

    // Hiding Native TabBar...
    init(topEdge: CGFloat, bottomEdge: CGFloat) {
        UITabBar.appearance().isHidden = true
        self.topEdge = topEdge
        self.bottomEdge = bottomEdge
    }

    private func tabContent<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .readsVerticalBar($usesVerticalBar)
            .instantTabSwitching()
    }

    private func legacyTab<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        tabContent(content)
            .tabItem {
                Label(LocalizedStringKey(name), image: name)
            }
            .tag(name)
    }

    private var logTab: some View {
        LogView(topEdge: topEdge, launchSearch: launchSearch)
            .id(timeFrameID)
            .ignoresSafeArea(.all, edges: .vertical)
    }

    private var insightsTab: some View {
        InsightsView()
            .id(timeFrameID)
    }

    private var budgetTab: some View {
        BudgetView()
            .id(timeFrameID)
    }

    @ViewBuilder
    private var tabView: some View {
        if #available(iOS 27.1, *) {
            TabView(selection: tabSelection) {
                Tab("Log", image: "Log", value: "Log") { tabContent { logTab } }
                Tab("Insights", image: "Insights", value: "Insights") { tabContent { insightsTab } }
                Tab("Budget", image: "Budget", value: "Budget") { tabContent { budgetTab } }
                Tab("Settings", image: "Settings", value: "Settings") { tabContent { SettingsView() } }

                // The prominent role sets the add button apart from the tabs in the Duo's vertical bar.
                if usesVerticalBar {
                    Tab("Add New Transaction", systemImage: "plus", value: Self.addTab, role: .prominent) {
                        Color.PrimaryBackground
                    }
                }
            }
        } else {
            TabView(selection: tabSelection) {
                legacyTab("Log") { logTab }
                legacyTab("Insights") { insightsTab }
                legacyTab("Budget") { budgetTab }
                legacyTab("Settings") { SettingsView() }
            }
        }
    }

    private func updateTabBarTop(_ top: CGFloat) {
        if !tabBarManager.hideTab {
            tabBarTop = top
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Views read the font when they draw, so rebuild everything below the tab selection when it changes.
            tabView
                .id(appFont)
                .background {
                    DeleteTransactionAlert()
                }
                .environmentObject(toastPresenter)
                .environmentObject(transactionManager)
                .environment(\.tabBarTop, usesVerticalBar || tabBarManager.hideTab ? nil : tabBarTop)
                .environment(\.usesVerticalBar, usesVerticalBar)
                .addTransactionSheet(isPresented: $addTransaction, counter: $counter, launchAdd: launchAdd)

            if !usesVerticalBar {
                CustomTabBar(currentTab: $currentTab, topEdge: topEdge, bottomEdge: bottomEdge, addTransaction: $addTransaction)
                    .id(appFont)
                    .background {
                        GeometryReader { proxy in
                            let top = proxy.frame(in: .global).minY
                            Color.clear
                                .onAppear { updateTabBarTop(top) }
                                .onChange(of: top) { updateTabBarTop($0) }
                        }
                    }
                    .offset(y: tabBarManager.hideTab ? (70 + bottomEdge) : 0)
            }

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
                        } else if url.host == "quickAdd" {
                            fromURL5 = true
                        }
                    }
            }
        }
        .toast(isPresenting: $toastPresenter.showToast, duration: 4, tapToDismiss: true, offsetY: 12, alert: {
            AlertToast(displayMode: .hud, type: .systemImage("checkmark.circle.fill", Color.IncomeGreen), title: "Image Saved", subTitle: "Check it out in Photos")
        })
        .sheet(item: $transactionManager.toEdit, onDismiss: {
            transactionManager.toEdit = nil
        }) { transaction in
            TransactionView(toEdit: transaction)
        }
        .confettiCannon(counter: $counter, num: 50, openingAngle: Angle(degrees: 0), closingAngle: Angle(degrees: 360), radius: 200)
        .onAppear {
            #if DEBUG
            // TEMPORARY (font PR screenshots): `-screenshotTab Insights` opens that tab. Remove before merging.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-screenshotTab"), index + 1 < arguments.count {
                currentTab = arguments[index + 1]
            }
            #endif

            if appLockVM.isAppLockEnabled && fromURL1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    launchAdd.toggle()
                }

                fromURL1 = false
            }

            if appLockVM.isAppLockEnabled && fromURL2 {
                currentTab = "Log"

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

            if appLockVM.isAppLockEnabled && fromURL5 {
                currentTab = "Settings"
                fromURL5 = false
            }
        }
        .onOpenURL { url in
            if url.host == "search" {
                currentTab = "Log"
            } else if url.host == "insights" {
                currentTab = "Insights"
            } else if url.host == "budget" {
                currentTab = "Budget"
            } else if url.host == "quickAdd" {
                currentTab = "Settings"
            }
        }
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
                .font(.app(size: 28, weight: .semibold))
                .foregroundColor(Color.PrimaryText)
                .padding(.bottom, 30)

            Button {
                appLockVM.appLockValidation()
            } label: {
                HStack {
                    Image(systemName: "faceid")

                    Text("Unlock App")
                }
                .font(.app(size: 20, weight: .medium))
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
                    .font(.app(size: 15, weight: .regular))
                    .foregroundColor(Color.SubtitleText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.PrimaryBackground)
    }
}
