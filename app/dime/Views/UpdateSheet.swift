//
//  UpdateSheet.swift
//  dime
//
//  Created by Rafael Soh on 13/9/23.
//

import Foundation
import SwiftUI

enum WhatsNew {
    /// The release `WhatsNewSheet.features` describes. Raising it shows the sheet once more to everyone who has opened
    /// Dime before; patch releases can leave it alone.
    static let release = "3.0"

    private static let lastSeenKey = "whatsNewLastSeenRelease"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.rafaelsoh.dime") ?? .standard
    }

    /// True until this release's sheet has been shown. Versions before 3.0 recorded no release, so anyone updating
    /// from them sees it too.
    static var hasUnseenRelease: Bool {
        guard let lastSeen = defaults.string(forKey: lastSeenKey) else { return true }
        return lastSeen.compare(release, options: .numeric) == .orderedAscending
    }

    static func markSeen() {
        defaults.set(release, forKey: lastSeenKey)
    }
}

private struct WhatsNewFeature: Hashable {
    let icon: String
    let title: String
    let subtitle: String
}

struct WhatsNewSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State private var appeared = false

    private let features = [
        WhatsNewFeature(icon: "sparkles", title: "A Fresh Look", subtitle: "Every screen has been rebuilt around Liquid Glass, with cleaner layouts throughout."),
        WhatsNewFeature(icon: "clock.arrow.circlepath", title: "Daily Backups", subtitle: "Dime backs up your data on this device every day, and offers to restore anything that goes missing."),
        WhatsNewFeature(icon: "icloud.fill", title: "Sturdier iCloud Sync", subtitle: "Fixes for missing and duplicated transactions, and a sync status in Settings."),
        WhatsNewFeature(icon: "chart.pie.fill", title: "Redesigned Budgets", subtitle: "New tiles show your pace at a glance, and budgets are set up in a single sentence."),
        WhatsNewFeature(icon: "chart.bar.xaxis", title: "Richer Insights", subtitle: "New cards, a category ring, and detailed cash flow and recurring breakdowns."),
        WhatsNewFeature(icon: "hand.draw.fill", title: "Scrub Through Time", subtitle: "Hold and drag a date slider to move quickly between days, weeks and months."),
        WhatsNewFeature(icon: "magnifyingglass", title: "Pull to Search", subtitle: "Pull down on the log to search, now with dates in your results."),
        WhatsNewFeature(icon: "apps.iphone", title: "Refreshed Widgets", subtitle: "Home and Lock Screen widgets match the new design."),
        WhatsNewFeature(icon: "square.and.arrow.down.fill", title: "Easier Imports", subtitle: "Bring in CSV files from other apps, with columns, dates and categories matched for you.")
    ]

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
        VStack(spacing: 0) {
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
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundColor(Color.PrimaryText)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        Text("Version \(WhatsNew.release)")
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .foregroundColor(Color.SubtitleText)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(features.indices, id: \.self) { index in
                            featureRow(features[index])
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared || reduceMotion ? 0 : 14)
                                .animation(.easeOut(duration: 0.4).delay(0.15 + 0.05 * Double(index)), value: appeared)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 48)
                .padding(.bottom, 24)
            }

            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Capsule())
            }
            .whiteGlassButtonStyle()
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sheetBackground()
        .onAppear {
            appeared = true
        }
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
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.PrimaryText)

                Text(LocalizedStringKey(feature.subtitle))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
