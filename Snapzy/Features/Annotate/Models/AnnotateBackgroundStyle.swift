//
//  BackgroundStyle.swift
//  Snapzy
//
//  Background style types and presets for annotation canvas
//

import Foundation
import SwiftUI

/// Background style types
enum BackgroundStyle: Equatable, Sendable {
  case none
  case gradient(GradientPreset)
  case wallpaper(URL)
  case blurred(URL)
  case solidColor(Color)

  var supportsBlurredBackgroundEffect: Bool {
    switch self {
    case .wallpaper, .blurred, .solidColor:
      return true
    case .none, .gradient:
      return false
    }
  }

  var blurredEffectImageURL: URL? {
    switch self {
    case .wallpaper(let url), .blurred(let url):
      return url
    case .none, .gradient, .solidColor:
      return nil
    }
  }
}

/// Blur presets for applying a soft effect to the selected background layer.
enum BlurredBackgroundEffect: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
  case soft
  case frosted
  case vivid
  case dim

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .soft:
      return L10n.AnnotateUI.blurredBackgroundSoft
    case .frosted:
      return L10n.AnnotateUI.blurredBackgroundFrosted
    case .vivid:
      return L10n.AnnotateUI.blurredBackgroundVivid
    case .dim:
      return L10n.AnnotateUI.blurredBackgroundDim
    }
  }

  var blurRadius: CGFloat {
    switch self {
    case .soft:
      return 18
    case .frosted:
      return 30
    case .vivid:
      return 22
    case .dim:
      return 24
    }
  }

  var saturation: Double {
    switch self {
    case .soft:
      return 1.0
    case .frosted:
      return 0.85
    case .vivid:
      return 1.35
    case .dim:
      return 0.9
    }
  }

  var brightness: Double {
    switch self {
    case .soft:
      return 0
    case .frosted:
      return 0.06
    case .vivid:
      return 0.02
    case .dim:
      return -0.06
    }
  }

  var tintColor: Color {
    switch self {
    case .soft, .frosted:
      return .white
    case .vivid:
      return .orange
    case .dim:
      return .black
    }
  }

  var tintOpacity: Double {
    switch self {
    case .soft:
      return 0.08
    case .frosted:
      return 0.28
    case .vivid:
      return 0.10
    case .dim:
      return 0.24
    }
  }
}

/// Predefined gradient presets
enum GradientPreset: String, CaseIterable, Identifiable, Sendable {
  case pinkOrange
  case bluePurple
  case greenBlue
  case orangeRed
  case purplePink
  case blueGreen
  case yellowOrange
  case cyanBlue

  var id: String { rawValue }

  var colors: [Color] {
    switch self {
    case .pinkOrange: return [.pink, .orange]
    case .bluePurple: return [.blue, .purple]
    case .greenBlue: return [.green, .blue]
    case .orangeRed: return [.orange, .red]
    case .purplePink: return [.purple, .pink]
    case .blueGreen: return [.blue, .green]
    case .yellowOrange: return [.yellow, .orange]
    case .cyanBlue: return [.cyan, .blue]
    }
  }
}

/// Image alignment within background
enum ImageAlignment: String, CaseIterable, Sendable {
  case topLeft, top, topRight
  case left, center, right
  case bottomLeft, bottom, bottomRight
}


/// Predefined wallpaper presets (abstract gradient patterns)
enum WallpaperPreset: String, CaseIterable, Identifiable {
  case oceanBreeze
  case sunsetGlow
  case forestMist

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .oceanBreeze: return L10n.AnnotateContext.wallpaperOcean
    case .sunsetGlow: return L10n.AnnotateContext.wallpaperSunset
    case .forestMist: return L10n.AnnotateContext.wallpaperForest
    }
  }

  var colors: [Color] {
    switch self {
    case .oceanBreeze: return [Color(red: 0.1, green: 0.4, blue: 0.6), Color(red: 0.2, green: 0.6, blue: 0.8), Color(red: 0.4, green: 0.8, blue: 0.9)]
    case .sunsetGlow: return [Color(red: 0.9, green: 0.3, blue: 0.2), Color(red: 0.95, green: 0.5, blue: 0.3), Color(red: 1.0, green: 0.7, blue: 0.4)]
    case .forestMist: return [Color(red: 0.1, green: 0.3, blue: 0.2), Color(red: 0.2, green: 0.5, blue: 0.3), Color(red: 0.4, green: 0.7, blue: 0.5)]
    }
  }

  var gradient: LinearGradient {
    LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
  }
}

/// Orientation for fixed aspect ratio presets.
enum AspectRatioOrientation: String, CaseIterable, Identifiable, Sendable {
  case horizontal
  case vertical

  var id: String { rawValue }

  var systemImageName: String {
    switch self {
    case .horizontal:
      return "rectangle"
    case .vertical:
      return "rectangle.portrait"
    }
  }
}

/// Aspect ratio options for export.
enum AspectRatioOption: String, CaseIterable, Identifiable, Sendable {
  case auto = "Auto"
  case free = "Free"
  case square = "1:1"
  case ratio4x3 = "4:3"
  case ratio3x2 = "3:2"
  case ratio16x9 = "16:9"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .auto:
      return L10n.Common.original
    case .free:
      return L10n.Common.free
    case .square, .ratio4x3, .ratio16x9, .ratio3x2:
      return rawValue
    }
  }

  var supportsOrientation: Bool {
    switch self {
    case .ratio4x3, .ratio16x9, .ratio3x2:
      return true
    case .auto, .free, .square:
      return false
    }
  }

  func effectiveDisplayName(orientation: AspectRatioOrientation) -> String {
    guard orientation == .vertical else {
      return displayName
    }

    switch self {
    case .ratio4x3:
      return "3:4"
    case .ratio3x2:
      return "2:3"
    case .ratio16x9:
      return "9:16"
    case .auto, .free, .square:
      return displayName
    }
  }

  func targetRatio(
    for foregroundSize: CGSize,
    orientation: AspectRatioOrientation = .horizontal
  ) -> CGFloat? {
    let baseRatio: CGFloat?
    switch self {
    case .auto:
      guard foregroundSize.width > 0, foregroundSize.height > 0 else { return nil }
      baseRatio = foregroundSize.width / foregroundSize.height
    case .free:
      baseRatio = nil
    case .square:
      baseRatio = 1
    case .ratio4x3:
      baseRatio = 4.0 / 3.0
    case .ratio16x9:
      baseRatio = 16.0 / 9.0
    case .ratio3x2:
      baseRatio = 3.0 / 2.0
    }

    guard let baseRatio else { return nil }
    if supportsOrientation, orientation == .vertical {
      return 1 / baseRatio
    }
    return baseRatio
  }

  func canvasSize(
    for foregroundSize: CGSize,
    padding: CGFloat,
    alignmentSpace: CGFloat,
    orientation: AspectRatioOrientation = .horizontal
  ) -> CGSize {
    let normalizedWidth = max(foregroundSize.width, 1)
    let normalizedHeight = max(foregroundSize.height, 1)
    let minimumWidth = normalizedWidth + max(padding, 0) * 2 + max(alignmentSpace, 0)
    let minimumHeight = normalizedHeight + max(padding, 0) * 2 + max(alignmentSpace, 0)

    guard let targetRatio = targetRatio(
      for: CGSize(width: normalizedWidth, height: normalizedHeight),
      orientation: orientation
    ),
          targetRatio > 0 else {
      return CGSize(width: minimumWidth, height: minimumHeight)
    }

    let minimumRatio = minimumWidth / minimumHeight
    if minimumRatio < targetRatio {
      return CGSize(width: minimumHeight * targetRatio, height: minimumHeight)
    }

    return CGSize(width: minimumWidth, height: minimumWidth / targetRatio)
  }
}
