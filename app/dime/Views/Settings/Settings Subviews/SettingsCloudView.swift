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
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        Toggle(isOn: $iCloudStorage) {
          Text("Enable Sync")
            .font(.system(.body, design: .rounded))
            .foregroundColor(Color.PrimaryText)
        }
        .tint(.green)
        .frame(minHeight: .settingsRowHeight)
      }
      .settingsSectionRows()

      SettingsSectionFooter("Close and reload app for change to take effect.")

      if iCloudStorage && dataController.isCloudKitSyncEnabled {
        SyncStatusSection(status: dataController.syncStatus)
          .padding(.top, .settingsHeaderSpacing)
      }
    }
    .modifier(SettingsSubviewModifier(title: "iCloud Sync"))

  }
}

struct SyncStatusSection: View {
  @ObservedObject var status: CloudSyncStatus

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: symbolName)
        .font(.system(.body, design: .rounded).weight(.semibold))
        .foregroundColor(symbolColor)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(.body, design: .rounded))
          .foregroundColor(Color.PrimaryText)

        if case let .problem(problem) = status.summary {
          Text(problem.message)
            .font(.system(.footnote, design: .rounded).weight(.medium))
            .foregroundColor(Color.SubtitleText)

          if let detail = problem.detail {
            Text(detail)
              .font(.system(.caption2, design: .monospaced))
              .foregroundColor(Color.SubtitleText)
          }
        }

        if let lastSynced = status.lastSynced {
          Text("Last synced \(lastSynced.formatted(.relative(presentation: .named)))")
            .font(.system(.footnote, design: .rounded).weight(.medium))
            .foregroundColor(Color.SubtitleText)
        } else if status.summary == .waiting {
          Text("Checking iCloud…")
            .font(.system(.footnote, design: .rounded).weight(.medium))
            .foregroundColor(Color.SubtitleText)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, .settingsRowInset)
    .frame(minHeight: .settingsRowHeight)
    .settingsSectionBackground()
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
