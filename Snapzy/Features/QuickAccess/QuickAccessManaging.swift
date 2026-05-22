//
//  QuickAccessManaging.swift
//  Snapzy
//
//  Protocol extracted from QuickAccessManager for DI.
//

import Foundation

@MainActor
protocol QuickAccessManaging {
  @discardableResult
  func addScreenshot(url: URL) async -> QuickAccessItem?

  @discardableResult
  func addVideo(url: URL) async -> QuickAccessItem?
}

extension QuickAccessManager: QuickAccessManaging {}
