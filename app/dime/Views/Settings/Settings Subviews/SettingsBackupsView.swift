//
//  SettingsBackupsView.swift
//  dime
//

import SwiftUI

struct SettingsBackupsView: View {
  @ObservedObject private var backupManager = BackupManager.shared
  @State private var alert: BackupAlert?

  private enum BackupAlert: Identifiable {
    case confirmRestore(BackupSummary)
    case restored(Int)
    case waitingForICloud
    case currencyChangeInProgress
    case failed

    var id: String {
      switch self {
      case let .confirmRestore(backup):
        return backup.url.lastPathComponent
      case let .restored(count):
        return "restored-\(count)"
      case .waitingForICloud:
        return "waiting"
      case .currencyChangeInProgress:
        return "currency"
      case .failed:
        return "failed"
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      Button {
        backupManager.backUpNow { succeeded in
          if !succeeded {
            alert = .failed
          }
        }
      } label: {
        HStack {
          Text("Back Up Now")
            .font(.app(.body))
            .foregroundColor(Color.PrimaryText)

          Spacer()

          if backupManager.isWorking {
            ProgressView()
          }
        }
        .frame(minHeight: .settingsRowHeight)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(backupManager.isWorking)
      .settingsSectionRows()

      SettingsSectionFooter("Dime backs up your data on this device once a day and keeps the last 14 backups. Restoring adds back anything that's missing and never removes or changes what you have now. Backups are deleted if you delete Dime.")

      if !backupManager.backups.isEmpty {
        VStack(spacing: 0) {
          ForEach(backupManager.backups) { backup in
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                  .font(.app(.body))
                  .foregroundColor(Color.PrimaryText)

                Text("\(backup.transactionCount) transactions")
                  .font(.app(.footnote))
                  .foregroundColor(Color.SubtitleText)
              }

              Spacer()

              Button("Restore") {
                alert = .confirmRestore(backup)
              }
              .font(.app(.body, weight: .medium))
              .foregroundColor(Color.IncomeGreen)
              .buttonStyle(.borderless)
              .disabled(backupManager.isWorking)
            }
            .padding(.vertical, 8)
            .frame(minHeight: .settingsRowHeight)

            if backup != backupManager.backups.last {
              Divider()
            }
          }
        }
        .settingsSectionRows()
        .padding(.top, .settingsHeaderSpacing)
      }
    }
    .modifier(SettingsSubviewModifier(title: "Backups"))
    .onAppear {
      backupManager.refreshList()
    }
    .alert(item: $alert) { alert in
      switch alert {
      case let .confirmRestore(backup):
        return Alert(
          title: Text("Restore this backup?"),
          message: Text("Anything missing from Dime will be added back from the backup made \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)). Nothing you have now will be removed or changed."),
          primaryButton: .default(Text("Restore")) {
            restore(backup)
          },
          secondaryButton: .cancel()
        )
      case let .restored(count):
        return Alert(
          title: count == 0 ? Text("Nothing was missing") : Text("Restore complete"),
          message: count == 0 ? Text("Everything in this backup is already in Dime.") : Text("Items added back: \(count)."),
          dismissButton: .default(Text("OK"))
        )
      case .waitingForICloud:
        return Alert(
          title: Text("Waiting for iCloud"),
          message: Text("You can restore once iCloud finishes syncing, so nothing gets added twice."),
          dismissButton: .default(Text("OK"))
        )
      case .currencyChangeInProgress:
        return Alert(
          title: Text("Can't restore yet"),
          message: Text("Dime is still finishing your last currency change. Try again in a moment."),
          dismissButton: .default(Text("OK"))
        )
      case .failed:
        return Alert(
          title: Text("Something went wrong"),
          message: Text("Dime couldn't finish. Please try again."),
          dismissButton: .default(Text("OK"))
        )
      }
    }
  }

  private func restore(_ backup: BackupSummary) {
    backupManager.restore(backup) { result in
      switch result {
      case let .success(restored):
        alert = .restored(restored.total)
      case .failure(BackupManager.RestoreError.waitingForICloud):
        alert = .waitingForICloud
      case .failure(BackupManager.RestoreError.currencyChangeInProgress):
        alert = .currencyChangeInProgress
      case .failure:
        alert = .failed
      }
    }
  }
}
