//
//  SettingsBackupsView.swift
//  dime
//

import SwiftUI

struct SettingsBackupsView: View {
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
  @ObservedObject private var backupManager = BackupManager.shared
  @State private var alert: BackupAlert?

  private enum BackupAlert: Identifiable {
    case confirmRestore(BackupSummary)
    case restored(Int)
    case waitingForICloud
    case failed

    var id: String {
      switch self {
      case let .confirmRestore(backup):
        return backup.url.lastPathComponent
      case let .restored(count):
        return "restored-\(count)"
      case .waitingForICloud:
        return "waiting"
      case .failed:
        return "failed"
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      Text("Backups")
        .font(.system(.title3, design: .rounded).weight(.semibold))
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

      ScrollView(showsIndicators: false) {
        content
      }
    }
    .modifier(SettingsSubviewModifier())
    .onAppear {
      backupManager.refreshList()
    }
    .alert(item: $alert) { alert in
      alertView(for: alert)
    }
  }

  private var content: some View {
    VStack(spacing: 10) {
      Button {
        backupManager.backUpNow { succeeded in
          if !succeeded {
            alert = .failed
          }
        }
      } label: {
        HStack {
          Text("Back Up Now")
            .font(.system(.body, design: .rounded))
            .foregroundColor(Color.PrimaryText)

          Spacer()

          if backupManager.isWorking {
            ProgressView()
          }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(backupManager.isWorking)
      .padding(.horizontal, 15)
      .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))

      Text("Dime backs up your data on this device once a day and keeps the last 14 backups. Restoring adds back anything that's missing and never removes or changes what you have now. Backups are deleted if you delete Dime.")
        .font(.system(.caption, design: .rounded).weight(.medium))
        .multilineTextAlignment(.leading)
        .foregroundColor(Color.SubtitleText)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, alignment: .leading)

      if backupManager.backups.isEmpty {
        Text("No backups yet")
          .font(.system(.body, design: .rounded))
          .foregroundColor(Color.SubtitleText)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
          .padding(.top, 10)
      } else {
        VStack(spacing: 0) {
          ForEach(backupManager.backups) { backup in
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                  .font(.system(.body, design: .rounded))
                  .foregroundColor(Color.PrimaryText)

                Text("\(backup.transactionCount) transactions")
                  .font(.system(.footnote, design: .rounded))
                  .foregroundColor(Color.SubtitleText)
              }

              Spacer()

              Button("Restore") {
                alert = .confirmRestore(backup)
              }
              .font(.system(.body, design: .rounded).weight(.medium))
              .foregroundColor(Color.IncomeGreen)
              .buttonStyle(.borderless)
              .disabled(backupManager.isWorking)
            }
            .padding(.vertical, 9)

            if backup != backupManager.backups.last {
              Divider()
            }
          }
        }
        .padding(.horizontal, 15)
        .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
        .padding(.top, 10)
      }
    }
  }

  private func alertView(for alert: BackupAlert) -> Alert {
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
    case .failed:
      return Alert(
        title: Text("Something went wrong"),
        message: Text("Dime couldn't finish. Please try again."),
        dismissButton: .default(Text("OK"))
      )
    }
  }

  private func restore(_ backup: BackupSummary) {
    backupManager.restore(backup) { result in
      switch result {
      case let .success(restored):
        alert = .restored(restored.total)
      case .failure(BackupManager.RestoreError.waitingForICloud):
        alert = .waitingForICloud
      case .failure:
        alert = .failed
      }
    }
  }
}
