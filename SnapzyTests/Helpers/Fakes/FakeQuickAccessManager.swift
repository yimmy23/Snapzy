//
//  FakeQuickAccessManager.swift
//  SnapzyTests
//
//  Records QuickAccessManaging calls for assertion.
//

import AppKit
import Foundation
@testable import Snapzy

@MainActor
final class FakeQuickAccessManager: QuickAccessManaging {
  private(set) var addedScreenshots: [URL] = []
  private(set) var addedVideos: [URL] = []
  private(set) var createdScreenshotItems: [QuickAccessItem] = []
  private(set) var createdVideoItems: [QuickAccessItem] = []

  @discardableResult
  func addScreenshot(url: URL) async -> QuickAccessItem? {
    addedScreenshots.append(url)
    let item = QuickAccessItem(url: url, thumbnail: NSImage(size: NSSize(width: 1, height: 1)))
    createdScreenshotItems.append(item)
    return item
  }

  @discardableResult
  func addVideo(url: URL) async -> QuickAccessItem? {
    addedVideos.append(url)
    let item = QuickAccessItem(
      url: url,
      thumbnail: NSImage(size: NSSize(width: 1, height: 1)),
      duration: 0
    )
    createdVideoItems.append(item)
    return item
  }
}
