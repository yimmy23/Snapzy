//
//  AboutSettingsView.swift
//  Snapzy
//
//  About tab with app info and sponsor CTA.
//

import AppKit
import Sparkle
import SwiftUI

struct AboutSettingsView: View {
  private var updater: SPUUpdater {
    UpdaterManager.shared.updater
  }

  private var appVersion: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "\(version) (\(build))"
  }

  var body: some View {
    VStack {
      Spacer()
      heroSection
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var heroSection: some View {
    VStack(spacing: Spacing.md) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

      VStack(spacing: Spacing.xs) {
        Text(verbatim: "Snapzy")
          .font(.system(size: 28, weight: .bold, design: .rounded))

        Text(L10n.PreferencesAbout.appSubtitle)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      HStack(spacing: Spacing.sm) {
        Text(L10n.PreferencesAbout.version(appVersion))
          .font(.caption)
          .foregroundColor(.secondary)

        if let lastCheck = updater.lastUpdateCheckDate {
          Text("•")
            .foregroundColor(.secondary.opacity(0.5))
          Text(L10n.PreferencesAbout.checkedLabel)
            .font(.caption)
            .foregroundColor(.secondary)
          Text(lastCheck, style: .relative)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.xs)
      .background(Color.primary.opacity(0.05))
      .clipShape(Capsule())

      HStack(spacing: Spacing.sm) {
        Button(action: { updater.checkForUpdates() }) {
          HStack(spacing: Spacing.sm) {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text(L10n.PreferencesAbout.checkForUpdates)
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)

        Button(action: { CrashReportService.presentAlert() }) {
          HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
            Text(L10n.PreferencesAbout.reportProblem)
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
      }

      sponsorSection

      HStack(spacing: Spacing.md) {
        Link(destination: URL(string: "https://snapzy.app")!) {
          Image(systemName: "globe")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(L10n.PreferencesAbout.website)

        Link(destination: URL(string: "https://github.com/duongductrong")!) {
          Image(systemName: "person.crop.circle")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(L10n.PreferencesAbout.github)

        Link(destination: URL(string: "https://github.com/duongductrong/Snapzy/issues")!) {
          Image(systemName: "ant.fill")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(L10n.PreferencesAbout.reportBug)
      }
      .padding(.top, Spacing.xs)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.md)
  }

  private var sponsorSection: some View {
    VStack(alignment: .center, spacing: Spacing.sm) {
      Text(L10n.PreferencesAbout.supportTitle)
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.secondary)

      VStack(spacing: 0) {
        let links = SponsorLinks.all
        ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
          SponsorRowView(link: link)

          if index < links.count - 1 {
            Divider()
              .padding(.horizontal, Spacing.md)
          }
        }
      }
      .background(Color.primary.opacity(0.03))
      .clipShape(RoundedRectangle(cornerRadius: Size.radiusLg))
      .overlay(
        RoundedRectangle(cornerRadius: Size.radiusLg)
          .stroke(Color.primary.opacity(0.08), lineWidth: 1)
      )

      Text(L10n.PreferencesAbout.supportDescription)
        .font(.system(size: 10.5))
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
        .frame(maxWidth: 360)
    }
    .frame(maxWidth: 420)
  }
}

struct SponsorRowView: View {
  let link: SponsorLink
  @State private var isHovering = false

  var body: some View {
    Button {
      NSWorkspace.shared.open(link.url)
    } label: {
      HStack(spacing: Spacing.md) {
        // Icon with a nice colored gradient background
        ZStack {
          LinearGradient(
            colors: [link.color.opacity(0.8), link.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )

          Image(systemName: link.systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .shadow(color: link.color.opacity(0.15), radius: 2, x: 0, y: 1)

        // Title and description
        VStack(alignment: .leading, spacing: 2) {
          Text(link.title)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.primary)

          Text(link.subtitle)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }

        Spacer()

        // Action button styled text
        Text(link.actionTitle)
          .font(.system(size: 11, weight: .semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(isHovering ? Color.accentColor : Color.primary.opacity(0.06))
          .foregroundColor(isHovering ? .white : .primary)
          .clipShape(Capsule())
          .animation(.easeInOut(duration: 0.12), value: isHovering)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, 10)
      .contentShape(Rectangle()) // Entire row is clickable
      .background(isHovering ? Color.primary.opacity(0.04) : Color.clear)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovering = hovering
    }
  }
}

#Preview {
  AboutSettingsView()
    .frame(width: 700, height: 550)
}
