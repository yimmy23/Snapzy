//
//  RecordingConfigurationTests.swift
//  SnapzyTests
//
//  Tests for screen-recording toolbar and overlay configuration defaults.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class RecordingConfigurationTests: XCTestCase {

  private var defaults: UserDefaults!

  override func setUp() async throws {
    try await super.setUp()
    defaults = UserDefaultsFactory.make()
  }

  func testRecordingToolbarPreferences_defaults() {
    XCTAssertEqual(RecordingToolbarPreferences.selectedFormat(defaults: defaults), .mov)
    XCTAssertEqual(RecordingToolbarPreferences.selectedQuality(defaults: defaults), .high)
    XCTAssertTrue(RecordingToolbarPreferences.captureAudio(defaults: defaults))
    XCTAssertFalse(RecordingToolbarPreferences.captureMicrophone(defaults: defaults))
    XCTAssertEqual(RecordingToolbarPreferences.outputMode(defaults: defaults), .video)
    XCTAssertTrue(RecordingToolbarPreferences.showCursor(defaults: defaults))
    XCTAssertFalse(RecordingToolbarPreferences.highlightClicks(defaults: defaults))
    XCTAssertFalse(RecordingToolbarPreferences.showKeystrokes(defaults: defaults))
  }

  func testRecordingToolbarPreferences_usePersistedRecordingOptions() {
    defaults.set(VideoFormat.mp4.rawValue, forKey: PreferencesKeys.recordingFormat)
    defaults.set(VideoQuality.low.rawValue, forKey: PreferencesKeys.recordingQuality)
    defaults.set(false, forKey: PreferencesKeys.recordingCaptureAudio)
    defaults.set(true, forKey: PreferencesKeys.recordingCaptureMicrophone)
    defaults.set(RecordingOutputMode.gif.rawValue, forKey: PreferencesKeys.recordingOutputMode)
    defaults.set(false, forKey: PreferencesKeys.recordingShowCursor)
    defaults.set(true, forKey: PreferencesKeys.recordingHighlightClicks)
    defaults.set(true, forKey: PreferencesKeys.recordingShowKeystrokes)

    XCTAssertEqual(RecordingToolbarPreferences.selectedFormat(defaults: defaults), .mp4)
    XCTAssertEqual(RecordingToolbarPreferences.selectedQuality(defaults: defaults), .low)
    XCTAssertFalse(RecordingToolbarPreferences.captureAudio(defaults: defaults))
    XCTAssertTrue(RecordingToolbarPreferences.captureMicrophone(defaults: defaults))
    XCTAssertEqual(RecordingToolbarPreferences.outputMode(defaults: defaults), .gif)
    XCTAssertFalse(RecordingToolbarPreferences.showCursor(defaults: defaults))
    XCTAssertTrue(RecordingToolbarPreferences.highlightClicks(defaults: defaults))
    XCTAssertTrue(RecordingToolbarPreferences.showKeystrokes(defaults: defaults))
  }

  func testRecordingToolbarPreferences_invalidRawValuesFallBackToSafeDefaults() {
    defaults.set("avi", forKey: PreferencesKeys.recordingFormat)
    defaults.set("ultra", forKey: PreferencesKeys.recordingQuality)
    defaults.set("cinematic", forKey: PreferencesKeys.recordingOutputMode)

    XCTAssertEqual(RecordingToolbarPreferences.selectedFormat(defaults: defaults), .mov)
    XCTAssertEqual(RecordingToolbarPreferences.selectedQuality(defaults: defaults), .high)
    XCTAssertEqual(RecordingToolbarPreferences.outputMode(defaults: defaults), .video)
  }

  func testRecordingMouseTrackerSamplesPerSecond_clampsToSupportedRange() {
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 15), 60)
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 30), 60)
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 60), 120)
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 240), 120)
  }

  func testMouseHighlightConfiguration_defaults() {
    let config = MouseHighlightConfiguration(defaults: defaults)

    XCTAssertEqual(config.highlightSize, MouseHighlightConfiguration.defaultHighlightSize)
    XCTAssertEqual(config.holdCircleSize, MouseHighlightConfiguration.defaultHoldCircleSize)
    XCTAssertEqual(config.ringWidth, MouseHighlightConfiguration.defaultRingWidth)
    XCTAssertEqual(config.animationDuration, MouseHighlightConfiguration.defaultAnimationDuration)
    XCTAssertEqual(config.rippleCount, MouseHighlightConfiguration.defaultRippleCount)
    XCTAssertEqual(config.highlightOpacity, MouseHighlightConfiguration.defaultHighlightOpacity)
    XCTAssertTrue(config.highlightColor.isEqual(MouseHighlightConfiguration.defaultHighlightColor))
  }

  func testMouseHighlightConfiguration_usesPersistedValues() throws {
    let color = NSColor(calibratedRed: 0.9, green: 0.2, blue: 0.4, alpha: 1.0)
    let colorData = try NSKeyedArchiver.archivedData(
      withRootObject: color,
      requiringSecureCoding: true
    )
    defaults.set(CGFloat(100), forKey: PreferencesKeys.mouseHighlightSize)
    defaults.set(1.2, forKey: PreferencesKeys.mouseHighlightAnimationDuration)
    defaults.set(colorData, forKey: PreferencesKeys.mouseHighlightColor)
    defaults.set(0.8, forKey: PreferencesKeys.mouseHighlightOpacity)
    defaults.set(5, forKey: PreferencesKeys.mouseHighlightRippleCount)

    let config = MouseHighlightConfiguration(defaults: defaults)

    XCTAssertEqual(config.highlightSize, 100)
    XCTAssertEqual(config.holdCircleSize, 72)
    XCTAssertEqual(config.animationDuration, 1.2)
    XCTAssertEqual(config.rippleCount, 5)
    XCTAssertEqual(config.highlightOpacity, 0.8)
    XCTAssertTrue(config.highlightColor.isEqual(color))
  }

  func testMouseHighlightConfiguration_nonPositiveRippleCountFallsBackToDefault() {
    defaults.set(0, forKey: PreferencesKeys.mouseHighlightRippleCount)

    let config = MouseHighlightConfiguration(defaults: defaults)

    XCTAssertEqual(config.rippleCount, MouseHighlightConfiguration.defaultRippleCount)
  }

  func testKeystrokeOverlayConfiguration_defaults() {
    let config = KeystrokeOverlayConfiguration(defaults: defaults)

    XCTAssertEqual(config.fontSize, KeystrokeOverlayConfiguration.defaultFontSize)
    XCTAssertEqual(config.position, KeystrokeOverlayConfiguration.defaultPosition)
    XCTAssertEqual(config.displayDuration, KeystrokeOverlayConfiguration.defaultDisplayDuration)
    XCTAssertEqual(config.edgeOffset, KeystrokeOverlayConfiguration.defaultEdgeOffset)
  }

  func testKeystrokeOverlayConfiguration_usesPersistedValues() {
    defaults.set(CGFloat(22), forKey: PreferencesKeys.keystrokeFontSize)
    defaults.set(KeystrokeOverlayPosition.topRight.rawValue, forKey: PreferencesKeys.keystrokePosition)
    defaults.set(2.5, forKey: PreferencesKeys.keystrokeDisplayDuration)

    let config = KeystrokeOverlayConfiguration(defaults: defaults)

    XCTAssertEqual(config.fontSize, 22)
    XCTAssertEqual(config.position, .topRight)
    XCTAssertEqual(config.displayDuration, 2.5)
  }

  func testKeystrokeOverlayConfiguration_invalidPositionFallsBackToDefault() {
    defaults.set("middle", forKey: PreferencesKeys.keystrokePosition)

    let config = KeystrokeOverlayConfiguration(defaults: defaults)

    XCTAssertEqual(config.position, KeystrokeOverlayConfiguration.defaultPosition)
  }
}
