//
//  SnapzyConfigurationServiceTests.swift
//  SnapzyTests
//
//  Tests for configuration file materialization.
//

import XCTest
@testable import Snapzy

@MainActor
final class SnapzyConfigurationServiceTests: XCTestCase {
  func testConfigFileURLAppendsConfigTomlToSelectedDirectory() {
    let directory = URL(fileURLWithPath: "/Users/example/.config/snapzy", isDirectory: true)

    let url = SnapzyConfigurationService.shared.configFileURL(inDirectory: directory)

    XCTAssertEqual(url.path, "/Users/example/.config/snapzy/config.toml")
  }

  func testSuggestedConfigDirectoryMatchingUsesCanonicalPath() {
    let expectedDirectory = SnapzyConfigurationPaths.suggestedConfigDirectoryURL

    XCTAssertTrue(SnapzyConfigurationService.shared.isSuggestedConfigDirectory(expectedDirectory))
    XCTAssertFalse(
      SnapzyConfigurationService.shared.isSuggestedConfigDirectory(
        expectedDirectory.deletingLastPathComponent()
      )
    )
  }

  func testSuggestedConfigParentDirectoryMatchingUsesCanonicalPath() {
    let expectedParentDirectory = SnapzyConfigurationPaths.suggestedConfigDirectoryURL
      .deletingLastPathComponent()

    XCTAssertTrue(SnapzyConfigurationService.shared.isSuggestedConfigParentDirectory(expectedParentDirectory))
    XCTAssertFalse(
      SnapzyConfigurationService.shared.isSuggestedConfigParentDirectory(
        expectedParentDirectory.appendingPathComponent("snapzy")
      )
    )
  }

  func testSuggestedConfigRootDirectoryMatchingUsesCanonicalPath() {
    let expectedRootDirectory = SnapzyConfigurationPaths.userHomeDirectory

    XCTAssertTrue(SnapzyConfigurationService.shared.isSuggestedConfigRootDirectory(expectedRootDirectory))
    XCTAssertFalse(
      SnapzyConfigurationService.shared.isSuggestedConfigRootDirectory(
        expectedRootDirectory.appendingPathComponent(".config", isDirectory: true)
      )
    )
  }

  func testEnsureConfigExistsCreatesParentDirectoryAndFile() throws {
    let homeDirectory = temporaryHomeDirectory()
    defer { try? FileManager.default.removeItem(at: homeDirectory) }
    let url = SnapzyConfigurationPaths.suggestedConfigURL(homeDirectory: homeDirectory)

    let returnedURL = try SnapzyConfigurationService.shared.ensureConfigExists(at: url)

    XCTAssertEqual(returnedURL.path, url.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

    let source = try String(contentsOf: url, encoding: .utf8)
    let document = try SimpleTOMLParser.parse(source)
    XCTAssertEqual(document.value(at: "schema_version")?.intValue, 1)
  }

  func testEnsureConfigExistsDoesNotOverwriteExistingFile() throws {
    let homeDirectory = temporaryHomeDirectory()
    defer { try? FileManager.default.removeItem(at: homeDirectory) }
    let url = SnapzyConfigurationPaths.suggestedConfigURL(homeDirectory: homeDirectory)
    let existingSource = """
    schema_version = 1

    [general]
    language = "system"
    """

    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try existingSource.write(to: url, atomically: true, encoding: .utf8)

    try SnapzyConfigurationService.shared.ensureConfigExists(at: url)

    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), existingSource)
  }

  func testImportBackupReplacingManagedConfigWritesSelectedTomlToManagedFile() throws {
    let directory = temporaryHomeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let backupURL = directory.appendingPathComponent("backup.toml")
    let managedURL = directory
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("snapzy", isDirectory: true)
      .appendingPathComponent("config.toml")
    let source = "schema_version = 1\n"

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try source.write(to: backupURL, atomically: true, encoding: .utf8)

    let result = try SnapzyConfigurationService.shared.importBackupReplacingManagedConfig(
      from: backupURL,
      managedConfigURL: managedURL
    )

    XCTAssertFalse(result.hasErrors)
    XCTAssertEqual(try String(contentsOf: managedURL, encoding: .utf8), source)
  }

  func testImportBackupReplacingManagedConfigDoesNotOverwriteWhenInvalid() throws {
    let directory = temporaryHomeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let backupURL = directory.appendingPathComponent("invalid.toml")
    let managedURL = directory
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("snapzy", isDirectory: true)
      .appendingPathComponent("config.toml")
    let existingSource = "schema_version = 1\n"
    let invalidSource = """
    schema_version = 99

    [capture.screenshot]
    format = "webp"
    """

    try FileManager.default.createDirectory(at: managedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try existingSource.write(to: managedURL, atomically: true, encoding: .utf8)
    try invalidSource.write(to: backupURL, atomically: true, encoding: .utf8)

    let result = try SnapzyConfigurationService.shared.importBackupReplacingManagedConfig(
      from: backupURL,
      managedConfigURL: managedURL
    )

    XCTAssertTrue(result.hasErrors)
    XCTAssertEqual(try String(contentsOf: managedURL, encoding: .utf8), existingSource)
  }

  private func temporaryHomeDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("snapzy-config-service-\(UUID().uuidString)", isDirectory: true)
  }
}
