//
//  SnapzyConfigurationAccessGranting.swift
//  Snapzy
//
//  Shared macOS folder-grant flow for the user-managed TOML configuration file.
//

import AppKit
import Foundation

struct SnapzyConfigurationAccessGrantResult {
  let configURL: URL
  let autoImportResult: SnapzyConfigurationAutoImportResult
}

enum SnapzyConfigurationAccessGrantError: LocalizedError {
  case unexpectedDirectory(expectedPath: String)

  var errorDescription: String? {
    switch self {
    case .unexpectedDirectory(let expectedPath):
      return L10n.PreferencesAdvanced.configDirectoryMismatch(expectedPath)
    }
  }
}

@MainActor
enum SnapzyConfigurationAccessGranting {
  static func grantSuggestedConfigAccess(
    title: String? = nil,
    message: String? = nil,
    prompt: String? = nil
  ) throws -> SnapzyConfigurationAccessGrantResult? {
    try grantSuggestedConfigAccess(
      service: .shared,
      title: title,
      message: message,
      prompt: prompt
    )
  }

  static func grantSuggestedConfigAccess(
    service: SnapzyConfigurationService,
    title: String? = nil,
    message: String? = nil,
    prompt: String? = nil
  ) throws -> SnapzyConfigurationAccessGrantResult? {
    try? FileManager.default.createDirectory(
      at: service.suggestedConfigDirectoryURL,
      withIntermediateDirectories: true
    )

    let panel = NSOpenPanel()
    panel.title = title ?? L10n.PreferencesAdvanced.configDirectoryPanelTitle
    panel.message = message ?? L10n.PreferencesAdvanced.configDirectoryPanelMessage(
      service.suggestedConfigDirectoryURL.path
    )
    panel.prompt = prompt ?? L10n.PreferencesAdvanced.configDirectoryPanelPrompt
    panel.directoryURL = initialDirectoryURL(for: service)
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.showsHiddenFiles = true

    guard panel.runModal() == .OK, let selectedURL = panel.url?.standardizedFileURL else {
      return nil
    }

    let didStartAccessingSelection = selectedURL.startAccessingSecurityScopedResource()
    defer {
      if didStartAccessingSelection {
        selectedURL.stopAccessingSecurityScopedResource()
      }
    }

    let configDirectoryURL = try resolvedConfigDirectory(from: selectedURL, service: service)
    try FileManager.default.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try service.rememberConfigDirectoryAccess(configDirectoryURL)
    let configURL = try service.ensureConfigExists(at: service.configFileURL(inDirectory: configDirectoryURL))
    let autoImportResult = SnapzyConfigurationAutoImporter.applyIfNeeded(from: configURL)

    return SnapzyConfigurationAccessGrantResult(
      configURL: configURL,
      autoImportResult: autoImportResult
    )
  }

  private static func initialDirectoryURL(for service: SnapzyConfigurationService) -> URL {
    let fileManager = FileManager.default
    let suggestedDirectory = service.suggestedConfigDirectoryURL
    if fileManager.fileExists(atPath: suggestedDirectory.path) {
      return suggestedDirectory
    }

    let parentDirectory = service.suggestedConfigParentDirectoryURL
    if fileManager.fileExists(atPath: parentDirectory.path) {
      return parentDirectory
    }

    return service.suggestedConfigRootDirectoryURL
  }

  private static func resolvedConfigDirectory(
    from selectedURL: URL,
    service: SnapzyConfigurationService
  ) throws -> URL {
    if service.isSuggestedConfigDirectory(selectedURL) {
      return selectedURL
    }

    if service.isSuggestedConfigParentDirectory(selectedURL) {
      return service.suggestedConfigDirectoryURL
    }

    if service.isSuggestedConfigRootDirectory(selectedURL) {
      return service.suggestedConfigDirectoryURL
    }

    throw SnapzyConfigurationAccessGrantError.unexpectedDirectory(
      expectedPath: service.suggestedConfigDirectoryURL.path
    )
  }
}
