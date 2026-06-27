//
//  PersistedAnnotationSessionConversion.swift
//  Snapzy
//
//  Conversion helpers for annotation session sidecars.
//

import CoreGraphics
import Foundation
import SwiftUI

struct PersistedArrowGeometry: Codable, Equatable {
  var start: CGPoint
  var end: CGPoint
  var style: String
  var controlPoint: CGPoint?

  init(geometry: ArrowGeometry) {
    start = geometry.start
    end = geometry.end
    style = geometry.style.rawValue
    controlPoint = geometry.resolvedControlPoint
  }

  var arrowGeometry: ArrowGeometry {
    ArrowGeometry(
      start: start,
      end: end,
      style: ArrowStyle(rawValue: style) ?? .straight,
      controlPoint: controlPoint
    )
  }
}

struct PersistedAnnotationProperties: Codable, Equatable {
  var strokeColor: RGBAColor
  var fillColor: RGBAColor
  var strokeWidth: CGFloat
  var cornerRadius: CGFloat
  var fontSize: CGFloat
  var fontName: String
  var opacity: CGFloat
  var rotationDegrees: CGFloat
  var watermarkStyle: String
  var spotlightOpacity: CGFloat?

  init(properties: AnnotationProperties) {
    strokeColor = RGBAColor(color: properties.strokeColor) ?? RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
    fillColor = RGBAColor(color: properties.fillColor) ?? RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
    strokeWidth = properties.strokeWidth
    cornerRadius = properties.cornerRadius
    fontSize = properties.fontSize
    fontName = properties.fontName
    opacity = properties.opacity
    rotationDegrees = properties.rotationDegrees
    watermarkStyle = properties.watermarkStyle.rawValue
    spotlightOpacity = properties.spotlightOpacity
  }

  var annotationProperties: AnnotationProperties {
    AnnotationProperties(
      strokeColor: strokeColor.color,
      fillColor: fillColor.color,
      strokeWidth: strokeWidth,
      cornerRadius: cornerRadius,
      fontSize: fontSize,
      fontName: fontName,
      opacity: opacity,
      rotationDegrees: rotationDegrees,
      watermarkStyle: WatermarkStyle(rawValue: watermarkStyle) ?? .single,
      spotlightOpacity: spotlightOpacity ?? 0.5
    )
  }
}

extension PersistedAnnotationSession {
  @MainActor
  init(
    sessionData: AnnotationSessionData,
    sourceFilePath: String,
    sourceFilePathHash: String,
    sourceSignature: PersistedFileSignature,
    createdAt: Date,
    updatedAt: Date = Date()
  ) {
    let embeddedAssetFileNames = Dictionary(uniqueKeysWithValues: sessionData.embeddedImageAssetsData.keys.map {
      ($0.uuidString, "\($0.uuidString).bin")
    })

    self.init(
      schemaVersion: Self.currentSchemaVersion,
      sourceFilePath: sourceFilePath,
      sourceFilePathHash: sourceFilePathHash,
      sourceSignature: sourceSignature,
      originalFileName: "original.bin",
      cutoutFileName: sessionData.cutoutImageData == nil ? nil : "cutout.png",
      embeddedAssetFileNames: embeddedAssetFileNames,
      annotations: sessionData.annotations.map(PersistedAnnotationItem.init),
      canvasEffects: PersistedCanvasEffects(effects: sessionData.canvasEffects),
      selectedCanvasPresetId: sessionData.selectedCanvasPresetId,
      isSelectedCanvasPresetDirty: sessionData.isSelectedCanvasPresetDirty,
      cropRect: sessionData.cropRect,
      isCutoutApplied: sessionData.isCutoutApplied,
      didCutoutAutoApplyCrop: sessionData.didCutoutAutoApplyCrop,
      cutoutAutoAppliedCropRect: sessionData.cutoutAutoAppliedCropRect,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }

  @MainActor
  func sessionData(
    originalImageData: Data,
    cutoutImageData: Data?,
    embeddedImageAssetsData: [UUID: Data]
  ) -> AnnotationSessionData {
    AnnotationSessionData(
      originalImageData: originalImageData,
      annotations: annotations.compactMap(\.annotationItem),
      canvasEffects: canvasEffects.annotationCanvasEffects,
      selectedCanvasPresetId: selectedCanvasPresetId,
      isSelectedCanvasPresetDirty: isSelectedCanvasPresetDirty,
      cropRect: cropRect,
      isCutoutApplied: isCutoutApplied,
      cutoutImageData: cutoutImageData,
      didCutoutAutoApplyCrop: didCutoutAutoApplyCrop,
      cutoutAutoAppliedCropRect: cutoutAutoAppliedCropRect,
      embeddedImageAssetsData: embeddedImageAssetsData
    )
  }
}
