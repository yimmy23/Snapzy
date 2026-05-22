//
//  ScreenshotPresetAutoApplier.swift
//  Snapzy
//
//  Applies the configured Annotate canvas preset to captured screenshots.
//

import AppKit
import Foundation

@MainActor
final class ScreenshotPresetAutoApplier {
  static let shared = ScreenshotPresetAutoApplier(
    presetStore: AnnotateCanvasPresetStore.shared,
    fileAccess: SandboxFileAccessManager.shared
  )

  private let presetStore: AnnotateCanvasPresetStore
  private let fileAccess: SandboxFileAccessManager

  init(presetStore: AnnotateCanvasPresetStore, fileAccess: SandboxFileAccessManager) {
    self.presetStore = presetStore
    self.fileAccess = fileAccess
  }

  convenience init(presetStore: AnnotateCanvasPresetStore) {
    self.init(presetStore: presetStore, fileAccess: SandboxFileAccessManager.shared)
  }

  func applyDefaultPresetIfNeeded(to url: URL) -> AnnotationSessionData? {
    let presets = presetStore.loadPresets()
    guard let defaultPresetId = presetStore.loadDefaultPresetId(validating: presets),
          let preset = presets.first(where: { $0.id == defaultPresetId }) else {
      return nil
    }

    guard FileManager.default.fileExists(atPath: url.path) else {
      DiagnosticLogger.shared.log(
        .warning,
        .annotate,
        "Screenshot preset auto-apply skipped; file missing",
        context: ["fileName": url.lastPathComponent]
      )
      return nil
    }

    let originalImageData: Data
    do {
      originalImageData = try fileAccess.withScopedAccess(to: url) {
        try Data(contentsOf: url)
      }
    } catch {
      DiagnosticLogger.shared.logError(
        .annotate,
        error,
        "Screenshot preset auto-apply skipped; original read failed",
        context: ["fileName": url.lastPathComponent]
      )
      return nil
    }

    guard let sourceImage = AnnotateState.loadImageWithCorrectScale(from: url) else {
      DiagnosticLogger.shared.log(
        .warning,
        .annotate,
        "Screenshot preset auto-apply skipped; image load failed",
        context: ["fileName": url.lastPathComponent]
      )
      return nil
    }

    let state = AnnotateState(
      image: sourceImage,
      url: url,
      canvasPresetStore: presetStore,
      appliesDefaultCanvasPresetOnNewImages: false
    )
    state.applyCanvasPreset(preset, marksUnsaved: false)

    guard state.isDefaultCanvasPresetAutoApplied else {
      DiagnosticLogger.shared.log(
        .debug,
        .annotate,
        "Screenshot preset auto-apply skipped; preset leaves image unchanged",
        context: ["fileName": url.lastPathComponent, "preset": preset.name]
      )
      return nil
    }

    guard let renderedImage = AnnotateExporter.renderFinalImage(state: state),
          let renderedData = AnnotateExporter.imageData(from: renderedImage, for: url.pathExtension) else {
      DiagnosticLogger.shared.log(
        .error,
        .annotate,
        "Screenshot preset auto-apply failed; render returned no data",
        context: ["fileName": url.lastPathComponent, "preset": preset.name]
      )
      return nil
    }

    do {
      try fileAccess.withScopedAccess(to: url.deletingLastPathComponent()) {
        try renderedData.write(to: url, options: .atomic)
      }
    } catch {
      DiagnosticLogger.shared.logError(
        .annotate,
        error,
        "Screenshot preset auto-apply failed; write failed",
        context: ["fileName": url.lastPathComponent, "preset": preset.name]
      )
      return nil
    }

    DiagnosticLogger.shared.log(
      .info,
      .annotate,
      "Screenshot preset auto-applied",
      context: ["fileName": url.lastPathComponent, "preset": preset.name]
    )

    return AnnotationSessionData(
      originalImageData: originalImageData,
      annotations: [],
      canvasEffects: state.canvasEffectsSnapshot,
      selectedCanvasPresetId: state.selectedCanvasPresetId,
      isSelectedCanvasPresetDirty: state.isSelectedCanvasPresetDirty,
      cropRect: nil
    )
  }
}
