//
//  UpdateSheet.swift
//  dime
//
//  Created by Rafael Soh on 13/9/23.
//

import Foundation
import SwiftUI

struct WhatsNewFeature: Hashable {
    let icon: String
    let title: String
    let subtitle: String
}

struct WhatsNewRelease: Hashable {
    let version: String
    let features: [WhatsNewFeature]
}

enum WhatsNew {
    /// Newest first. Adding a release at the top shows its sheet once to everyone who has opened Dime before; releases
    /// with nothing to announce can be left out.
    static let releases = [
        WhatsNewRelease(version: "3.0.1", features: [
            WhatsNewFeature(icon: "dollarsign.arrow.circlepath", title: "Multiple Currencies", subtitle: "Tap the currency symbol to log in any currency. Totals are converted to your primary currency at each day's rate."),
            WhatsNewFeature(icon: "calendar", title: "Start Your Week Any Day", subtitle: "Weeks can now begin on any weekday. Pick yours in Settings."),
            WhatsNewFeature(icon: "square.and.arrow.up.fill", title: "Export a Period", subtitle: "Choose the dates to include before exporting your transactions."),
            WhatsNewFeature(icon: "rectangle.grid.2x2.fill", title: "Unlimited Categories", subtitle: "Add as many expense categories as you like, shown in the order you set."),
            WhatsNewFeature(icon: "magnifyingglass", title: "Search by Amount", subtitle: "Find a transaction by its amount, even with a currency symbol or separators."),
            WhatsNewFeature(icon: "globe", title: "Français and Русский", subtitle: "Dime is now available in French and Russian.")
        ]),
        WhatsNewRelease(version: "3.0", features: [
            WhatsNewFeature(icon: "sparkles", title: "A Fresh Look", subtitle: "Every screen has been rebuilt around Liquid Glass, with cleaner layouts throughout."),
            WhatsNewFeature(icon: "clock.arrow.circlepath", title: "Daily Backups", subtitle: "Dime backs up your data on this device every day, and offers to restore anything that goes missing."),
            WhatsNewFeature(icon: "icloud.fill", title: "Sturdier iCloud Sync", subtitle: "Fixes for missing and duplicated transactions, and a sync status in Settings."),
            WhatsNewFeature(icon: "chart.pie.fill", title: "Redesigned Budgets", subtitle: "New tiles show your pace at a glance, and budgets are set up in a single sentence."),
            WhatsNewFeature(icon: "chart.bar.xaxis", title: "Richer Insights", subtitle: "New cards, a category ring, and detailed cash flow and recurring breakdowns."),
            WhatsNewFeature(icon: "hand.draw.fill", title: "Scrub Through Time", subtitle: "Hold and drag a date slider to move quickly between days, weeks and months."),
            WhatsNewFeature(icon: "magnifyingglass", title: "Pull to Search", subtitle: "Pull down on the log to search, now with dates in your results."),
            WhatsNewFeature(icon: "apps.iphone", title: "Refreshed Widgets", subtitle: "Home and Lock Screen widgets match the new design."),
            WhatsNewFeature(icon: "square.and.arrow.down.fill", title: "Easier Imports", subtitle: "Bring in CSV files from other apps, with columns, dates and categories matched for you.")
        ])
    ]

    static var latest: WhatsNewRelease {
        releases[0]
    }

    private static let lastSeenKey = "whatsNewLastSeenRelease"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.rafaelsoh.dime") ?? .standard
    }

    /// Releases newer than the last sheet shown. Versions before 3.0 recorded no release, so anyone updating from
    /// them sees every release listed.
    static var unseenReleases: [WhatsNewRelease] {
        guard let lastSeen = defaults.string(forKey: lastSeenKey) else { return releases }
        return releases.filter { lastSeen.compare($0.version, options: .numeric) == .orderedAscending }
    }

    static func markSeen() {
        defaults.set(latest.version, forKey: lastSeenKey)
    }
}

struct WhatsNewSheet: View {
    /// Newest first. Older releases follow under their own version headings.
    var releases: [WhatsNewRelease] = [WhatsNew.latest]

    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State private var appeared = false

    var body: some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }

    var content: some View {
        ScrollView(showsIndicators: false) {
                VStack(spacing: 36) {
                    VStack(spacing: 4) {
                        Image("AppIcon1_EG")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                            .shadow(color: Color.black.opacity(0.2), radius: 14, y: 7)
                            .padding(.bottom, 16)
                            .accessibilityHidden(true)

                        Text("What's New in Dime")
                            .font(.app(.largeTitle, weight: .bold))
                            .foregroundColor(Color.PrimaryText)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        if let newest = releases.first {
                            versionText(newest)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    ForEach(releases.indices, id: \.self) { releaseIndex in
                        VStack(alignment: .leading, spacing: 24) {
                            if releaseIndex > 0 {
                                versionText(releases[releaseIndex])
                                    .accessibilityAddTraits(.isHeader)
                                    .appearing(appeared, reduceMotion: reduceMotion, order: animationOrder(release: releaseIndex, feature: 0))
                            }

                            ForEach(releases[releaseIndex].features.indices, id: \.self) { index in
                                featureRow(releases[releaseIndex].features[index])
                                    .appearing(appeared, reduceMotion: reduceMotion, order: animationOrder(release: releaseIndex, feature: index))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 48)
                .padding(.bottom, 24)
                .padding(.horizontal, 28)
        }
        .bottomBar {
            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.app(.headline))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Capsule())
            }
            .whiteGlassButtonStyle()
            .padding(.top, 12)
            .padding(.bottom, 16)
            .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheetBackground()
        .onAppear {
            appeared = true
        }
    }

    /// Rows fade in one after another down the sheet, up to the first screenful.
    private func animationOrder(release: Int, feature: Int) -> Int {
        min(releases.prefix(release).reduce(0) { $0 + $1.features.count + 1 } + feature, 10)
    }

    private func versionText(_ release: WhatsNewRelease) -> some View {
        Text("Version \(release.version)")
            .font(.app(.callout, weight: .medium))
            .foregroundColor(Color.SubtitleText)
    }

    private func featureRow(_ feature: WhatsNewFeature) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: feature.icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(Color.PrimaryText)
                .frame(width: 48, height: 48)
                .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: false)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(feature.title))
                    .font(.app(.title3, weight: .semibold))
                    .foregroundColor(Color.PrimaryText)

                Text(LocalizedStringKey(feature.subtitle))
                    .font(.app(.body))
                    .foregroundColor(Color.SubtitleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func appearing(_ appeared: Bool, reduceMotion: Bool, order: Int) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .animation(.easeOut(duration: 0.4).delay(0.15 + 0.05 * Double(order)), value: appeared)
    }
}
