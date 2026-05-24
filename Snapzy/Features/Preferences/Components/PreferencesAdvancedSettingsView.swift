//
//  PreferencesAdvancedSettingsView.swift
//  Snapzy
//
//  Advanced preferences for portable app configuration.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
  @State private var needsConfigAccess = SnapzyConfigurationService.shared.needsUserSelectedConfigAccess
  @State private var isRestoreConfirmationPresented = false

  private let service = SnapzyConfigurationService.shared
  private let tomlContentType = UTType(filenameExtension: "toml") ?? .plainText

  private var canUseBackupActions: Bool {
    !needsConfigAccess
  }

  var body: some View {
    Form {
      Section(L10n.PreferencesAdvanced.backupSection) {
        if needsConfigAccess {
          AdvancedConfigAccessWarningRow {
            grantConfigAccess(openAfterGrant: false)
          }
        }

        SettingRow(
          icon: "square.and.arrow.down",
          title: L10n.PreferencesAdvanced.importTitle,
          description: L10n.PreferencesAdvanced.importDescription
        ) {
          Button(L10n.PreferencesAdvanced.importButton) {
            importConfig()
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(!canUseBackupActions)
          .help(disabledBackupActionHelp)
        }

        SettingRow(
          icon: "square.and.arrow.up",
          title: L10n.PreferencesAdvanced.exportTitle,
          description: L10n.PreferencesAdvanced.exportDescription
        ) {
          Button(L10n.PreferencesAdvanced.exportButton) {
            exportConfig()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(!canUseBackupActions)
          .help(disabledBackupActionHelp)
        }

        SettingRow(
          icon: "arrow.counterclockwise.circle",
          title: L10n.PreferencesAdvanced.restoreDefaultsTitle,
          description: L10n.PreferencesAdvanced.restoreDefaultsDescription
        ) {
          Button(L10n.PreferencesAdvanced.restoreDefaultsButton, role: .destructive) {
            guard backupActionsAreAvailable() else { return }
            isRestoreConfirmationPresented = true
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(!canUseBackupActions)
          .help(disabledBackupActionHelp)
        }

        HStack {
          Spacer()

          Button(L10n.PreferencesAdvanced.openConfigButton) {
            openConfigFile()
          }
          .buttonStyle(.link)
          .controlSize(.small)
          .disabled(!canUseBackupActions)
          .help(disabledBackupActionHelp)
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      refreshConfigAccessState()
    }
    .alert(
      L10n.PreferencesAdvanced.restoreDefaultsConfirmationTitle,
      isPresented: $isRestoreConfirmationPresented
    ) {
      Button(L10n.Common.cancel, role: .cancel) {}
      Button(L10n.PreferencesAdvanced.restoreDefaultsButton, role: .destructive) {
        restoreDefaults()
      }
    } message: {
      Text(L10n.PreferencesAdvanced.restoreDefaultsConfirmationMessage)
    }
  }

  private var disabledBackupActionHelp: String {
    needsConfigAccess ? L10n.PreferencesAdvanced.configAccessRequiredToast : ""
  }

  private func exportConfig() {
    guard backupActionsAreAvailable() else { return }

    let panel = NSSavePanel()
    panel.title = L10n.PreferencesAdvanced.exportPanelTitle
    panel.nameFieldStringValue = "config.toml"
    panel.directoryURL = service.suggestedConfigDirectoryURL
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [tomlContentType]

    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      try service.export(to: url)
      if service.isSuggestedConfigFile(url) {
        try? service.rememberConfigFileAccess(url)
      }
      refreshConfigAccessState()
      showNotice(L10n.PreferencesAdvanced.exportSucceeded, style: .success)
    } catch {
      showNotice(error.localizedDescription, fallback: L10n.PreferencesAdvanced.exportFailed, style: .error)
    }
  }

  private func importConfig() {
    guard backupActionsAreAvailable() else { return }

    let panel = NSOpenPanel()
    panel.title = L10n.PreferencesAdvanced.importPanelTitle
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [tomlContentType]

    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      let result = try service.importBackupReplacingManagedConfig(from: url)
      showImportNotice(for: result)
    } catch {
      showNotice(error.localizedDescription, fallback: L10n.PreferencesAdvanced.importFailed, style: .error)
    }
  }

  private func restoreDefaults() {
    guard backupActionsAreAvailable() else { return }

    do {
      let result = try service.restoreDefaultsReplacingManagedConfig()
      showRestoreNotice(for: result)
    } catch {
      showNotice(error.localizedDescription, fallback: L10n.PreferencesAdvanced.restoreDefaultsFailed, style: .error)
    }
  }

  private func openConfigFile() {
    guard backupActionsAreAvailable() else { return }

    guard let url = ensureSuggestedConfigExists(reportFailure: true) else { return }
    openConfigFile(at: url)
  }

  private func openConfigFile(at url: URL) {
    let access = service.beginAccessingConfigFile(url)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.promptsUserIfNeeded = false

    NSWorkspace.shared.open(url, configuration: configuration) { _, error in
      access.stop()
      DispatchQueue.main.async {
        if let error {
          self.showNotice(error.localizedDescription, fallback: L10n.PreferencesAdvanced.openConfigUnavailable, style: .error)
          return
        }

        self.showNotice(L10n.PreferencesAdvanced.openConfigSucceeded, style: .success)
      }
    }
  }

  private func grantConfigAccess(openAfterGrant: Bool) {
    do {
      guard let grantResult = try SnapzyConfigurationAccessGranting.grantSuggestedConfigAccess(service: service) else {
        return
      }

      refreshConfigAccessState()
      showGrantNotice(for: grantResult)

      if openAfterGrant {
        openConfigFile(at: grantResult.configURL)
      }
    } catch {
      showNotice(error.localizedDescription, fallback: L10n.PreferencesAdvanced.openConfigUnavailable, style: .error)
    }
  }

  private func issues(for autoImportResult: SnapzyConfigurationAutoImportResult) -> [SnapzyConfigurationIssue] {
    if let issues = autoImportResult.importResult?.issues {
      return issues
    }

    if autoImportResult.status == .failed, let errorMessage = autoImportResult.errorMessage {
      return [SnapzyConfigurationIssue(severity: .error, message: errorMessage)]
    }

    return []
  }

  @discardableResult
  private func ensureSuggestedConfigExists(reportFailure: Bool) -> URL? {
    ensureConfigExists(at: service.resolvedConfigFileURL, reportFailure: reportFailure)
  }

  @discardableResult
  private func ensureConfigExists(at url: URL, reportFailure: Bool) -> URL? {
    do {
      return try service.ensureConfigExists(at: url)
    } catch {
      if reportFailure {
        showNotice(error.localizedDescription, fallback: L10n.PreferencesAdvanced.openConfigUnavailable, style: .error)
      }
      return nil
    }
  }

  private func refreshConfigAccessState() {
    needsConfigAccess = service.needsUserSelectedConfigAccess
  }

  private func backupActionsAreAvailable() -> Bool {
    refreshConfigAccessState()

    if needsConfigAccess {
      showNotice(L10n.PreferencesAdvanced.configAccessRequiredToast, style: .warning)
      return false
    }

    return true
  }

  private func showGrantNotice(for grantResult: SnapzyConfigurationAccessGrantResult) {
    let issues = issues(for: grantResult.autoImportResult)
    let style = noticeStyle(for: issues)
    let message: String

    if let importResult = grantResult.autoImportResult.importResult {
      message = noticeSummary(for: importResult, successMessage: L10n.PreferencesAdvanced.configAccessReady)
    } else if grantResult.autoImportResult.status == .failed {
      message = issues.first?.message ?? L10n.PreferencesAdvanced.openConfigUnavailable
    } else {
      message = L10n.PreferencesAdvanced.configAccessReady
    }

    showNotice(message, style: style)
  }

  private func showImportNotice(for result: SnapzyConfigurationImportResult) {
    showNotice(
      noticeSummary(for: result, successMessage: L10n.PreferencesAdvanced.importSucceeded),
      style: noticeStyle(for: result.issues)
    )
  }

  private func showRestoreNotice(for result: SnapzyConfigurationImportResult) {
    guard !result.hasErrors else {
      showImportNotice(for: result)
      return
    }

    let style = noticeStyle(for: result.issues)
    let message = result.issues.contains(where: { $0.severity == .warning })
      ? noticeSummary(for: result, successMessage: L10n.PreferencesAdvanced.restoreDefaultsSucceeded)
      : L10n.PreferencesAdvanced.restoreDefaultsSucceeded
    showNotice(message, style: style)
  }

  private func noticeSummary(
    for result: SnapzyConfigurationImportResult,
    successMessage: String
  ) -> String {
    if result.hasErrors {
      return L10n.PreferencesAdvanced.importFailedWithErrors(
        result.issues.filter { $0.severity == .error }.count
      )
    }

    let warningCount = result.issues.filter { $0.severity == .warning }.count
    if warningCount > 0 {
      return L10n.PreferencesAdvanced.importedWithWarnings(
        result.appliedChangeCount,
        warningCount
      )
    }

    return successMessage
  }

  private func noticeStyle(for issues: [SnapzyConfigurationIssue]) -> AppToastStyle {
    if issues.contains(where: { $0.severity == .error }) {
      return .error
    }

    if issues.contains(where: { $0.severity == .warning }) {
      return .warning
    }

    return .success
  }

  private func showNotice(
    _ message: String,
    fallback: String? = nil,
    style: AppToastStyle
  ) {
    let resolvedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? fallback ?? L10n.PreferencesAdvanced.operationFinished
      : message

    AppToastManager.shared.show(
      message: resolvedMessage,
      style: style,
      duration: style == .success ? 2.4 : 4.0
    )
  }

}

private struct AdvancedConfigAccessWarningRow: View {
  let onGrant: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(.orange)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 3) {
        Text(L10n.PreferencesAdvanced.configAccessWarningTitle)
          .font(.subheadline)
          .fontWeight(.semibold)
        Text(L10n.PreferencesAdvanced.configAccessWarningDescription(
          SnapzyConfigurationService.shared.suggestedConfigDirectoryURL.path
        ))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()

      Button(L10n.PreferencesAdvanced.grantConfigAccessButton) {
        onGrant()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .onTapGesture {
      onGrant()
    }
  }
}

#Preview {
  AdvancedSettingsView()
    .frame(width: 600, height: 450)
}
