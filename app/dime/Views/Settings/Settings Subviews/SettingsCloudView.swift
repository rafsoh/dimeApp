//
//  SettingsCloudView.swift
//  dime
//
//  Created by Rafael Soh on 5/11/23.
//

import Foundation
import SwiftUI

struct SettingsCloudView: View {
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
  @EnvironmentObject var dataController: DataController
  @AppStorage(DataController.iCloudSyncEnabledKey, store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
  private var iCloudStorage: Bool = true
  @Namespace var animation

  var body: some View {
    VStack(spacing: 10) {
      Text("iCloud Sync")
        .font(.system(.title3, design: .rounded).weight(.semibold))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        //                .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundColor(Color.PrimaryText)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
          Button {
            self.presentationMode.wrappedValue.dismiss()
          } label: {
            SettingsBackButton()
          }
        }
        .padding(.bottom, 20)

      VStack(spacing: 0) {
        HStack {
          Text("Enable Sync")
            .font(.system(.body, design: .rounded))
            .foregroundColor(Color.PrimaryText)

          Spacer()

          ZStack(alignment: iCloudStorage ? .trailing : .leading) {
            Capsule()
              .frame(width: 42, height: 28)
              .foregroundColor(iCloudStorage ? .green : .gray.opacity(0.8))

            Circle()
              .foregroundColor(Color.white)
              .padding(2)
              .frame(width: 28, height: 28)
              .matchedGeometryEffect(id: "toggle", in: animation)
          }
          .onTapGesture {
            iCloudStorage.toggle()
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
      }
      .padding(.horizontal, 15)
      .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))

      Text("Close and reload app for change to take effect.")
        .font(.system(.caption, design: .rounded).weight(.medium))
        .multilineTextAlignment(.leading)
        .foregroundColor(Color.SubtitleText)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, alignment: .leading)

      if iCloudStorage && dataController.isCloudKitSyncEnabled {
        SyncStatusSection(status: dataController.syncStatus)
          .padding(.top, 10)
      }
    }
    .modifier(SettingsSubviewModifier())

  }
}

struct SyncStatusSection: View {
  @ObservedObject var status: CloudSyncStatus

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbolName)
        .font(.system(.body, design: .rounded).weight(.semibold))
        .foregroundColor(symbolColor)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(.body, design: .rounded))
          .foregroundColor(Color.PrimaryText)

        if case let .problem(problem) = status.summary {
          Text(problem.message)
            .font(.system(.caption, design: .rounded).weight(.medium))
            .foregroundColor(Color.SubtitleText)

          if let detail = problem.detail {
            Text(detail)
              .font(.system(.caption2, design: .monospaced))
              .foregroundColor(Color.SubtitleText)
          }
        }

        if let lastSynced = status.lastSynced {
          Text("Last synced \(lastSynced.formatted(.relative(presentation: .named)))")
            .font(.system(.caption, design: .rounded).weight(.medium))
            .foregroundColor(Color.SubtitleText)
        } else if status.summary == .waiting {
          Text("Checking iCloud…")
            .font(.system(.caption, design: .rounded).weight(.medium))
            .foregroundColor(Color.SubtitleText)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 9)
    .padding(.horizontal, 15)
    .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
    .accessibilityElement(children: .combine)
  }

  private var title: LocalizedStringKey {
    switch status.summary {
    case .off:
      return "Off"
    case .waiting:
      return "Waiting to sync"
    case .syncing:
      return "Syncing…"
    case .upToDate:
      return "Up to date"
    case .problem:
      return "Not Syncing"
    }
  }

  private var symbolName: String {
    switch status.summary {
    case .off:
      return "icloud.slash.fill"
    case .waiting:
      return "icloud.fill"
    case .syncing:
      return "arrow.triangle.2.circlepath.icloud.fill"
    case .upToDate:
      return "checkmark.icloud.fill"
    case .problem:
      return "exclamationmark.icloud.fill"
    }
  }

  private var symbolColor: Color {
    switch status.summary {
    case .upToDate:
      return Color.IncomeGreen
    case .problem:
      return Color.AlertRed
    case .off, .waiting, .syncing:
      return Color.SubtitleText
    }
  }
}
