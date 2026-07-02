//
//  AreaSelectionBackdrop.swift
//  Snapzy
//
//  Shared models for area selection backdrops and results.
//

import CoreGraphics
import Foundation

typealias AreaSelectionResultCompletion = (AreaSelectionResult?) -> Void

nonisolated enum AreaSelectionInteractionMode {
  case manualRegion
  case applicationWindow
}

nonisolated struct AreaSelectionBackdrop {
  let displayID: CGDirectDisplayID
  let image: CGImage
  let scaleFactor: CGFloat
}

nonisolated struct WindowCaptureTarget: Equatable, Sendable {
  let windowID: CGWindowID
  let frame: CGRect
  let displayID: CGDirectDisplayID
  let title: String?
  let bundleIdentifier: String?
  let ownerPID: Int32?
}

nonisolated enum AreaSelectionTarget: Equatable {
  case rect(CGRect)
  case window(WindowCaptureTarget)

  var rect: CGRect {
    switch self {
    case .rect(let rect):
      rect
    case .window(let target):
      target.frame
    }
  }

  var windowTarget: WindowCaptureTarget? {
    switch self {
    case .rect:
      nil
    case .window(let target):
      target
    }
  }
}

nonisolated struct AreaSelectionApplicationConfiguration {
  let prefetchedContentTask: ShareableContentPrefetchTask?
  let excludeOwnApplication: Bool
}

nonisolated struct AreaSelectionResult {
  let target: AreaSelectionTarget
  let displayID: CGDirectDisplayID
  let mode: SelectionMode
  let displayIDs: Set<CGDirectDisplayID>

  init(
    target: AreaSelectionTarget,
    displayID: CGDirectDisplayID,
    mode: SelectionMode,
    displayIDs: Set<CGDirectDisplayID>? = nil
  ) {
    self.target = target
    self.displayID = displayID
    self.mode = mode
    self.displayIDs = displayIDs ?? [displayID]
  }

  var rect: CGRect {
    target.rect
  }

  var spansMultipleDisplays: Bool {
    displayIDs.count > 1
  }
}
