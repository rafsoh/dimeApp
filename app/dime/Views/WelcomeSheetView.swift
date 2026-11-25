//
//  WelcomeSheetView.swift
//  dime
//
//  Created by Rafael Soh on 22/8/22.
//

import Foundation
import SwiftUI

struct WelcomeSheetFeatureRow: Hashable {
    let icon: String
    let header: String
    let subtitle: String
}

struct WelcomeSheetView: View {
    @Environment(\.dismiss) var dismiss

    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.dateCreated)
    ]) private var categories: FetchedResults<Category>

    @State var firstPage = true
    @State var visibleLines: Int = 0

    let timer = Timer.publish(every: 0.16, on: .main, in: .common).autoconnect()

    let welcomeFeatures = [
        WelcomeSheetFeatureRow(icon: "list.bullet.rectangle.fill", header: "welcome_header_1", subtitle: "welcome_subtitle_1"),
        WelcomeSheetFeatureRow(icon: "chart.bar.xaxis", header: "welcome_header_2", subtitle: "welcome_subtitle_2"),
        WelcomeSheetFeatureRow(icon: "archivebox.fill", header: "welcome_header_3", subtitle: "welcome_subtitle_3")
    ]

    var body: some View {
        VStack {
            if firstPage {
                VStack(spacing: 44) {
                    Spacer(minLength: 0)

                    VStack(spacing: 4) {
                        Image("AppIcon1_EG")
                            .resizable()
                            .frame(width: 92, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                            .shadow(color: Color.black.opacity(0.25), radius: 16, y: 8)
                            .padding(.bottom, 18)

                        Text("dime_name")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundColor(Color.PrimaryText)

                        Text("Version \(UIApplication.appVersion ?? "") (\(UIApplication.buildNumber ?? ""))")
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .foregroundColor(Color.SubtitleText)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(welcomeFeatures.indices, id: \.self) { rowIndex in
                            if rowIndex < visibleLines {
                                HStack(alignment: .top, spacing: 15) {
                                    Image(systemName: welcomeFeatures[rowIndex].icon)
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundColor(Color.PrimaryText)
                                        .frame(width: 48, height: 48)
                                        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: false)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(LocalizedStringKey(welcomeFeatures[rowIndex].header))
                                            .font(.system(.title3, design: .rounded).weight(.semibold))
                                            .foregroundColor(Color.PrimaryText)

                                        Text(LocalizedStringKey(welcomeFeatures[rowIndex].subtitle))
                                            .font(.system(.body, design: .rounded))
                                            .fixedSize(horizontal: false, vertical: true)
                                            .foregroundColor(Color.SubtitleText)
                                    }
                                }
                                .transition(AnyTransition.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                    }
                    .padding(.horizontal, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 230, alignment: .top)
                    .onReceive(timer) { _ in
                        withAnimation(.easeInOut(duration: 0.4)) {
                            if visibleLines < 3 {
                                visibleLines += 1
                            } else {
                                timer.upstream.connect().cancel()
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    Button {
                        withAnimation {
                            firstPage = false
                        }
                    } label: {
                        Text("Get Started")
                            .font(.system(.headline, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .contentShape(Capsule())
                    }
                    .whiteGlassButtonStyle()
                }
                .padding(.horizontal, 28)
                .padding(.top, 30)
                .padding(.bottom, 16)
            } else {
                CategoryView(mode: .welcome)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    // Categories, then accounts, close the sheet from inside its navigation stack.
                    .environment(\.finishOnboarding, { dismiss() })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.PrimaryBackground)
    }
}
