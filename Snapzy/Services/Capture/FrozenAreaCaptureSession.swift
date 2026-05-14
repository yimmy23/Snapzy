//
//  FrozenAreaCaptureSession.swift
//  Snapzy
//
//  Owns frozen display snapshots used for static area selection.
//

import CoreGraphics
import Foundation

nonisolated struct FrozenDisplaySnapshot {
  let displayID: CGDirectDisplayID
  let screenFrame: CGRect
  let scaleFactor: CGFloat
  let colorSpaceName: CFString?
  let image: CGImage
}

nonisolated struct FrozenAreaCropResult {
  let image: CGImage
  let scaleFactor: CGFloat
}

nonisolated final class FrozenAreaCaptureSession {
  private var snapshots: [CGDirectDisplayID: FrozenDisplaySnapshot]

  private init(snapshots: [CGDirectDisplayID: FrozenDisplaySnapshot]) {
    self.snapshots = snapshots
  }

  static func fromSnapshot(_ snapshot: FrozenDisplaySnapshot) -> FrozenAreaCaptureSession {
    FrozenAreaCaptureSession(snapshots: [snapshot.displayID: snapshot])
  }

  static func fromSnapshots(_ snapshots: [FrozenDisplaySnapshot]) -> FrozenAreaCaptureSession {
    var snapshotsByDisplayID: [CGDirectDisplayID: FrozenDisplaySnapshot] = [:]
    for snapshot in snapshots {
      snapshotsByDisplayID[snapshot.displayID] = snapshot
    }
    return FrozenAreaCaptureSession(snapshots: snapshotsByDisplayID)
  }

  @MainActor
  static func prepare(
    captureManager: ScreenCaptureManager? = nil,
    displayIDs: Set<CGDirectDisplayID>? = nil,
    showCursor: Bool,
    excludeDesktopIcons: Bool,
    excludeDesktopWidgets: Bool,
    excludeOwnApplication: Bool,
    prefetchedContentTask: ShareableContentPrefetchTask? = nil
  ) async throws -> FrozenAreaCaptureSession {
    let captureManager = captureManager ?? .shared
    let snapshots = try await captureManager.captureDisplaySnapshots(
      displayIDs: displayIDs,
      showCursor: showCursor,
      excludeDesktopIcons: excludeDesktopIcons,
      excludeDesktopWidgets: excludeDesktopWidgets,
      excludeOwnApplication: excludeOwnApplication,
      prefetchedContentTask: prefetchedContentTask
    )
    return FrozenAreaCaptureSession(snapshots: snapshots)
  }

  var backdrops: [CGDirectDisplayID: AreaSelectionBackdrop] {
    var result: [CGDirectDisplayID: AreaSelectionBackdrop] = [:]
    for (displayID, snapshot) in snapshots {
      result[displayID] = AreaSelectionBackdrop(
        displayID: displayID,
        image: snapshot.image,
        scaleFactor: snapshot.scaleFactor
      )
    }
    return result
  }

  var displayIDs: Set<CGDirectDisplayID> {
    Set(snapshots.keys)
  }

  func containsSnapshot(for displayID: CGDirectDisplayID) -> Bool {
    snapshots[displayID] != nil
  }

  func addSnapshot(_ snapshot: FrozenDisplaySnapshot) {
    snapshots[snapshot.displayID] = snapshot
  }

  func backdrop(for displayID: CGDirectDisplayID) -> AreaSelectionBackdrop? {
    guard let snapshot = snapshots[displayID] else { return nil }
    return AreaSelectionBackdrop(
      displayID: displayID,
      image: snapshot.image,
      scaleFactor: snapshot.scaleFactor
    )
  }

  func missingSnapshotDisplayIDs(for displayIDs: Set<CGDirectDisplayID>) -> Set<CGDirectDisplayID> {
    Set(displayIDs.filter { snapshots[$0] == nil })
  }

  func cropImage(for selection: AreaSelectionResult) throws -> FrozenAreaCropResult {
    guard let snapshot = snapshots[selection.displayID] else {
      throw CaptureError.captureFailed(L10n.ScreenCapture.selectionOutsideDisplayBounds)
    }

    let relativeRect = CGRect(
      x: selection.rect.origin.x - snapshot.screenFrame.origin.x,
      y: selection.rect.origin.y - snapshot.screenFrame.origin.y,
      width: selection.rect.width,
      height: selection.rect.height
    )
    let screenBounds = CGRect(
      x: 0,
      y: 0,
      width: snapshot.screenFrame.width,
      height: snapshot.screenFrame.height
    )
    let clampedRect = relativeRect.intersection(screenBounds)
    guard !clampedRect.isEmpty else {
      throw CaptureError.captureFailed(L10n.ScreenCapture.selectionOutsideDisplayBounds)
    }

    let alignedRect = Self.pixelAlignedRect(
      clampedRect,
      scaleFactor: snapshot.scaleFactor,
      bounds: screenBounds
    )
    guard !alignedRect.isEmpty else {
      throw CaptureError.captureFailed(L10n.ScreenCapture.selectionOutsideDisplayBounds)
    }

    let flippedY = snapshot.screenFrame.height - alignedRect.origin.y - alignedRect.height
    let pixelCropRect = CGRect(
      x: (alignedRect.origin.x * snapshot.scaleFactor).rounded(),
      y: (flippedY * snapshot.scaleFactor).rounded(),
      width: CGFloat(max(1, Int((alignedRect.width * snapshot.scaleFactor).rounded()))),
      height: CGFloat(max(1, Int((alignedRect.height * snapshot.scaleFactor).rounded())))
    ).intersection(
      CGRect(
        x: 0,
        y: 0,
        width: snapshot.image.width,
        height: snapshot.image.height
      )
    )

    guard let croppedImage = snapshot.image.cropping(to: pixelCropRect), !pixelCropRect.isEmpty else {
      throw CaptureError.captureFailed(L10n.ScreenCapture.failedToCropCapturedImage)
    }

    return FrozenAreaCropResult(image: croppedImage, scaleFactor: snapshot.scaleFactor)
  }

  func cropCompositeImage(for selection: AreaSelectionResult) throws -> FrozenAreaCropResult {
    let selectionRect = selection.rect
    let requestedDisplayIDs = selection.displayIDs.isEmpty ? [selection.displayID] : selection.displayIDs
    let matchingSnapshots = snapshots.values.filter { snapshot in
      requestedDisplayIDs.contains(snapshot.displayID) && snapshot.screenFrame.intersects(selectionRect)
    }

    guard !matchingSnapshots.isEmpty else {
      throw CaptureError.captureFailed(L10n.ScreenCapture.selectionOutsideDisplayBounds)
    }

    let outputScaleFactor = matchingSnapshots.map(\.scaleFactor).max() ?? 1.0
    let outputWidth = max(1, Int((selectionRect.width * outputScaleFactor).rounded()))
    let outputHeight = max(1, Int((selectionRect.height * outputScaleFactor).rounded()))
    let colorSpace = matchingSnapshots
      .compactMap { Self.colorSpace(from: $0.colorSpaceName) }
      .first ?? CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
      data: nil,
      width: outputWidth,
      height: outputHeight,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      throw CaptureError.captureFailed(L10n.ScreenCapture.failedToCropCapturedImage)
    }

    context.clear(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
    context.interpolationQuality = .none

    for snapshot in matchingSnapshots {
      let screenBounds = CGRect(
        x: 0,
        y: 0,
        width: snapshot.screenFrame.width,
        height: snapshot.screenFrame.height
      )
      let intersection = selectionRect.intersection(snapshot.screenFrame)
      let relativeRect = CGRect(
        x: intersection.origin.x - snapshot.screenFrame.origin.x,
        y: intersection.origin.y - snapshot.screenFrame.origin.y,
        width: intersection.width,
        height: intersection.height
      )
      let alignedRect = Self.pixelAlignedRect(
        relativeRect,
        scaleFactor: snapshot.scaleFactor,
        bounds: screenBounds
      )
      guard !alignedRect.isEmpty else { continue }

      let flippedY = snapshot.screenFrame.height - alignedRect.origin.y - alignedRect.height
      let pixelCropRect = CGRect(
        x: (alignedRect.origin.x * snapshot.scaleFactor).rounded(),
        y: (flippedY * snapshot.scaleFactor).rounded(),
        width: CGFloat(max(1, Int((alignedRect.width * snapshot.scaleFactor).rounded()))),
        height: CGFloat(max(1, Int((alignedRect.height * snapshot.scaleFactor).rounded())))
      ).intersection(
        CGRect(
          x: 0,
          y: 0,
          width: snapshot.image.width,
          height: snapshot.image.height
        )
      )

      guard let croppedImage = snapshot.image.cropping(to: pixelCropRect), !pixelCropRect.isEmpty else {
        continue
      }

      let alignedScreenRect = CGRect(
        x: snapshot.screenFrame.origin.x + alignedRect.origin.x,
        y: snapshot.screenFrame.origin.y + alignedRect.origin.y,
        width: alignedRect.width,
        height: alignedRect.height
      )
      let destinationRect = CGRect(
        x: (alignedScreenRect.minX - selectionRect.minX) * outputScaleFactor,
        y: (alignedScreenRect.minY - selectionRect.minY) * outputScaleFactor,
        width: alignedScreenRect.width * outputScaleFactor,
        height: alignedScreenRect.height * outputScaleFactor
      ).integral
      context.draw(croppedImage, in: destinationRect)
    }

    guard let image = context.makeImage() else {
      throw CaptureError.captureFailed(L10n.ScreenCapture.failedToCropCapturedImage)
    }

    return FrozenAreaCropResult(image: image, scaleFactor: outputScaleFactor)
  }

  func invalidate() {
    snapshots.removeAll()
  }

  private static func pixelAlignedRect(
    _ rect: CGRect,
    scaleFactor: CGFloat,
    bounds: CGRect
  ) -> CGRect {
    guard scaleFactor > 0 else { return rect.intersection(bounds) }

    let minX = floor(rect.minX * scaleFactor) / scaleFactor
    let minY = floor(rect.minY * scaleFactor) / scaleFactor
    let maxX = ceil(rect.maxX * scaleFactor) / scaleFactor
    let maxY = ceil(rect.maxY * scaleFactor) / scaleFactor

    return CGRect(
      x: minX,
      y: minY,
      width: max(0, maxX - minX),
      height: max(0, maxY - minY)
    ).intersection(bounds)
  }

  private static func colorSpace(from name: CFString?) -> CGColorSpace? {
    guard let name else { return nil }
    return CGColorSpace(name: name)
  }
}
