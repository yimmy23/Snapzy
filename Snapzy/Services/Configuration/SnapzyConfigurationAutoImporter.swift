//
//  SnapzyConfigurationAutoImporter.swift
//  Snapzy
//
//  Applies user-edited TOML configuration on app launch when the file changes.
//

import CryptoKit
import Foundation

enum SnapzyConfigurationAutoImportStatus: Equatable {
  case applied
  case failed
  case skippedMissingFile
  case skippedPermissionRequired
  case skippedUnchanged
}

struct SnapzyConfigurationAutoImportResult {
  let status: SnapzyConfigurationAutoImportStatus
  let fileURL: URL
  let importResult: SnapzyConfigurationImportResult?
  let errorMessage: String?

  var appliedChangeCount: Int {
    importResult?.appliedChangeCount ?? 0
  }

  var warningCount: Int {
    importResult?.issues.filter { $0.severity == .warning }.count ?? 0
  }

  var errorCount: Int {
    importResult?.issues.filter { $0.severity == .error }.count ?? 0
  }
}

@MainActor
enum SnapzyConfigurationAutoImporter {
  static func applyIfNeededOnLaunch(
    defaults: UserDefaults = .standard
  ) -> SnapzyConfigurationAutoImportResult {
    applyIfNeededOnLaunch(service: .shared, defaults: defaults)
  }

  static func applyIfNeededOnLaunch(
    service: SnapzyConfigurationService,
    defaults: UserDefaults = .standard
  ) -> SnapzyConfigurationAutoImportResult {
    if service.needsUserSelectedConfigAccess {
      return SnapzyConfigurationAutoImportResult(
        status: .skippedPermissionRequired,
        fileURL: service.resolvedConfigFileURL,
        importResult: nil,
        errorMessage: nil
      )
    }

    let access = service.beginAccessingConfigFile()
    defer { access.stop() }

    return applyIfNeeded(from: access.url, defaults: defaults)
  }

  static func applyIfNeeded(
    from fileURL: URL,
    defaults: UserDefaults = .standard
  ) -> SnapzyConfigurationAutoImportResult {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return SnapzyConfigurationAutoImportResult(
        status: .skippedMissingFile,
        fileURL: fileURL,
        importResult: nil,
        errorMessage: nil
      )
    }

    let source: String
    do {
      source = try String(contentsOf: fileURL, encoding: .utf8)
    } catch {
      return SnapzyConfigurationAutoImportResult(
        status: .failed,
        fileURL: fileURL,
        importResult: nil,
        errorMessage: error.localizedDescription
      )
    }

    let signature = contentSignature(for: source)
    if defaults.string(forKey: PreferencesKeys.configurationLastAppliedSignature) == signature {
      return SnapzyConfigurationAutoImportResult(
        status: .skippedUnchanged,
        fileURL: fileURL,
        importResult: nil,
        errorMessage: nil
      )
    }

    let importResult = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)
    if importResult.hasErrors {
      return SnapzyConfigurationAutoImportResult(
        status: .failed,
        fileURL: fileURL,
        importResult: importResult,
        errorMessage: nil
      )
    }

    defaults.set(signature, forKey: PreferencesKeys.configurationLastAppliedSignature)
    return SnapzyConfigurationAutoImportResult(
      status: .applied,
      fileURL: fileURL,
      importResult: importResult,
      errorMessage: nil
    )
  }

  static func markCurrentFileApplied(_ source: String, defaults: UserDefaults = .standard) {
    defaults.set(contentSignature(for: source), forKey: PreferencesKeys.configurationLastAppliedSignature)
  }

  private static func contentSignature(for source: String) -> String {
    let digest = SHA256.hash(data: Data(source.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
