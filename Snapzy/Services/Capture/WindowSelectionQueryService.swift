//
//  WindowSelectionQueryService.swift
//  Snapzy
//
//  Builds ordered window candidates for screenshot application mode.
//

import AppKit
import Foundation
import ScreenCaptureKit

struct WindowSelectionCandidate: Equatable, Sendable {
  let target: WindowCaptureTarget
  let ownerName: String
  let windowLayer: Int

  func contains(_ point: CGPoint) -> Bool {
    target.frame.contains(point)
  }
}

struct WindowSelectionSnapshot: Sendable {
  let orderedCandidates: [WindowSelectionCandidate]

  func hitTest(at point: CGPoint) -> WindowSelectionCandidate? {
    orderedCandidates.first { $0.contains(point) }
  }
}

@MainActor
enum WindowSelectionQueryService {
  struct RawWindowInfo: Sendable {
    let windowID: CGWindowID
    let layer: Int?
    let quartzBounds: CGRect?
    let alpha: Double
    let ownerPID: Int32?
    let ownerName: String?
    let title: String?
  }

  static func prepareSnapshot(
    prefetchedContentTask: ShareableContentPrefetchTask?,
    excludeOwnApplication: Bool
  ) async -> WindowSelectionSnapshot? {
    do {
      let content = try await loadShareableContent(prefetchedContentTask: prefetchedContentTask)
      let shareableWindowsByID = Dictionary(
        uniqueKeysWithValues: content.windows.filter { $0.isOnScreen }.map { ($0.windowID, $0) }
      )
      let ownBundleIdentifier = Bundle.main.bundleIdentifier

      let rawWindowInfoList = await Task.detached {
        guard
          let rawWindowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
          ) as? [[String: Any]]
        else {
          return [RawWindowInfo]()
        }

        return rawWindowInfo.compactMap { windowInfo -> RawWindowInfo? in
          guard let number = windowInfo[kCGWindowNumber as String] as? NSNumber else { return nil }
          let windowID = CGWindowID(number.uint32Value)
          
          let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue
          
          var quartzBounds: CGRect? = nil
          if let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary {
            quartzBounds = CGRect(dictionaryRepresentation: boundsDictionary)?.standardized
          }
          
          let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
          let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
          let ownerName = windowInfo[kCGWindowOwnerName as String] as? String
          let title = windowInfo[kCGWindowName as String] as? String

          return RawWindowInfo(
            windowID: windowID,
            layer: layer,
            quartzBounds: quartzBounds,
            alpha: alpha,
            ownerPID: ownerPID,
            ownerName: ownerName,
            title: title
          )
        }
      }.value

      var seenWindowIDs = Set<CGWindowID>()
      var orderedCandidates: [WindowSelectionCandidate] = []

      for info in rawWindowInfoList {
        let windowID = info.windowID
        guard seenWindowIDs.insert(windowID).inserted else { continue }
        let shareableWindow = shareableWindowsByID[windowID]
        
        let windowLayer = info.layer ?? shareableWindow?.windowLayer ?? 0
        guard windowLayer == 0 else { continue }
        
        guard let quartzBounds = info.quartzBounds else { continue }
        let frame = appKitGlobalRect(fromQuartzGlobalRect: quartzBounds).integral
        guard frame.width > 32, frame.height > 32 else { continue }
        guard let displayID = displayID(for: frame) else { continue }
        guard info.alpha > 0 else { continue }

        let bundleIdentifier = shareableWindow?.owningApplication?.bundleIdentifier
          ?? info.ownerPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        
        if excludeOwnApplication, bundleIdentifier == ownBundleIdentifier {
          continue
        }

        let title = (shareableWindow?.title?.isEmpty == false) ? shareableWindow?.title : (info.title?.isEmpty == false ? info.title : nil)
        let ownerNameVal = (shareableWindow?.owningApplication?.applicationName.isEmpty == false
          ? shareableWindow?.owningApplication?.applicationName
          : nil) ?? info.ownerName ?? ""

        orderedCandidates.append(
          WindowSelectionCandidate(
            target: WindowCaptureTarget(
              windowID: windowID,
              frame: frame,
              displayID: displayID,
              title: title,
              bundleIdentifier: bundleIdentifier,
              ownerPID: info.ownerPID
            ),
            ownerName: ownerNameVal,
            windowLayer: windowLayer
          )
        )
      }

      return WindowSelectionSnapshot(orderedCandidates: orderedCandidates)
    } catch {
      DiagnosticLogger.shared.logError(
        .capture,
        error,
        "Failed to prepare application mode window candidates"
      )
      return nil
    }
  }

  static func resolveWindow(
    windowID: CGWindowID,
    prefetchedContentTask: ShareableContentPrefetchTask?
  ) async -> SCWindow? {
    do {
      let content = try await loadShareableContent(prefetchedContentTask: prefetchedContentTask)
      if let prefetchedMatch = content.windows.first(where: { $0.windowID == windowID && $0.isOnScreen }) {
        return prefetchedMatch
      }

      let refreshedContent = try await SCShareableContent.current
      return refreshedContent.windows.first { $0.windowID == windowID && $0.isOnScreen }
    } catch {
      DiagnosticLogger.shared.logError(
        .capture,
        error,
        "Failed to resolve shareable window \(windowID)"
      )
      return nil
    }
  }

  private static func loadShareableContent(
    prefetchedContentTask: ShareableContentPrefetchTask?
  ) async throws -> SCShareableContent {
    if let prefetchedContentTask {
      return try await prefetchedContentTask.value
    }
    return try await SCShareableContent.current
  }

  private static func displayID(for frame: CGRect) -> CGDirectDisplayID? {
    let midpoint = CGPoint(x: frame.midX, y: frame.midY)
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) {
      return screen.displayID
    }

    var bestDisplayID: CGDirectDisplayID?
    var bestIntersectionArea: CGFloat = 0
    for screen in NSScreen.screens {
      let intersection = screen.frame.intersection(frame)
      let area = intersection.width * intersection.height
      if area > bestIntersectionArea {
        bestIntersectionArea = area
        bestDisplayID = screen.displayID
      }
    }
    return bestDisplayID
  }

  private static func appKitGlobalRect(fromQuartzGlobalRect rect: CGRect) -> CGRect {
    let mainScreenHeight = NSScreen.screens.first(where: { $0.displayID == CGMainDisplayID() })?.frame.height
      ?? CGDisplayBounds(CGMainDisplayID()).height

    return CGRect(
      x: rect.origin.x,
      y: mainScreenHeight - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }
}
