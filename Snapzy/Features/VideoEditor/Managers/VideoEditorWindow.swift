//
//  VideoEditorWindow.swift
//  Snapzy
//
//  Dark mode video editor window configuration
//

import AppKit

/// Custom NSWindow for video editing with dark mode appearance
final class VideoEditorWindow: NSWindow {
  private static let activeEditorLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
  private let restingLevel: NSWindow.Level = .normal

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    configure()
  }
  
  override func layoutIfNeeded() {
    super.layoutIfNeeded()
    
    layoutTrafficLights()
  }

  private func configure() {
    applyTheme()

    // Enable full-size content view
    styleMask.insert(.fullSizeContentView)

    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    minSize = NSSize(width: 400, height: 300)
    isReleasedWhenClosed = false
    center()

    applyCornerRadius()
  }

  func applyActiveEditorLevel() {
    level = Self.activeEditorLevel
  }

  func restoreRestingLevel() {
    level = restingLevel
  }

  /// Apply current theme from ThemeManager
  func applyTheme() {
    let themeManager = ThemeManager.shared
    appearance = themeManager.nsAppearance
    backgroundColor = WindowSurfacePalette.backgroundColor(for: themeManager.preferredAppearance)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
