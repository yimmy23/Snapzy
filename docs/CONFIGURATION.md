# TOML Configuration

Snapzy can export and import user-editable TOML configuration for backup,
dotfiles, and machine-to-machine setup. If the file changes while Snapzy is
closed, Snapzy automatically applies the valid TOML on the next launch.

Default path:

```text
~/.config/snapzy/config.toml
```

Settings -> Advanced -> Backup requires config folder access before Import,
Export, Restore defaults, or Open config.toml can be used. Granting access lets
Snapzy create `config.toml` with the current preferences if it is missing.
Snapzy does not live-watch `config.toml`. Direct edits are picked up on the next
app launch; explicit import validates a selected `.toml` backup, replaces the
managed `~/.config/snapzy/config.toml`, then applies it immediately.

If `~/.config` or `~/.config/snapzy` does not exist yet, the grant flow starts
from the nearest existing parent and creates the missing folder after the user
confirms access. Snapzy stores the bookmark for `~/.config/snapzy`.

For existing users upgrading from a version without TOML config support, Snapzy
opens the normal onboarding window directly on the config access step once
after launch. Granting access stores the folder bookmark, creates `config.toml`
if needed, and applies an existing valid file immediately. Users can skip the
step and grant access later from Settings -> Advanced.

## Scope

The TOML file covers portable app preferences:

- General settings: language, appearance, sounds, login item, export folder path.
- Capture settings: naming templates, screenshot format, cursor/app inclusion,
  scrolling hints, OCR notification, object cutout auto-crop.
- After-capture actions for screenshot and recording.
- Recording settings: format, quality, FPS, audio, microphone device id, cursor,
  click highlights, keystroke overlay, live annotation shortcuts.
- Quick Access: visibility, position, countdown behavior, action order,
  enabled actions, card slots.
- History: retention, maximum count, floating panel layout and filter.
- Cloud metadata: provider, bucket, region, endpoint, custom domain, expiration,
  and upload window position.
- Annotate preferences.
- Global, overlay, Annotate tool, and Annotate action shortcuts.

The export intentionally excludes secrets and machine-private state:

- Cloud access key and secret key are not exported. They remain in Keychain.
- Cloud credential archive transfer stays in the existing encrypted cloud
  import/export flow.
- Cloud configured/password-protection state is not exported because it depends
  on local Keychain items.
- Capture history, temp files, annotation sidecars, upload history, caches, and
  app diagnostics are not part of `config.toml`.
- File-access security-scoped bookmarks are not portable. Imported folder paths
  may still need to be confirmed in Settings on the destination Mac.

## Schema

Current schema version:

```toml
schema_version = 1
snapzy_min_version = "1.20.0"
```

Unknown keys are ignored. Known keys are validated by type and allowed value.
If import finds any error, Snapzy applies none of the changes. Warnings do not
block import.

## Example

```toml
schema_version = 1
snapzy_min_version = "1.20.0"

[general]
language = "system"
appearance = "system"
play_sounds = true
start_at_login = false
export_location = "~/Desktop"

[capture]
hide_desktop_icons = false
hide_desktop_widgets = false

[capture.naming]
screenshot_template = "Screenshot {yyyy}-{MM}-{dd} at {HH}.{mm}.{ss}"
recording_template = "Recording {yyyy}-{MM}-{dd} at {HH}.{mm}.{ss}"

[capture.screenshot]
format = "png"
include_snapzy = false
show_cursor = false

[capture.after.screenshot]
save = true
quick_access = true
copy_file = false
open_annotate = false
upload_to_cloud = false

[recording]
format = "mov"
quality = "high"
fps = 30
capture_system_audio = false
capture_microphone = false
show_cursor = true
highlight_clicks = false
show_keystrokes = false

[quick_access]
enabled = true
position = "topTrailing"
auto_dismiss = true
auto_dismiss_delay = 8.0
actions_order = ["copy", "saveOrOpen", "edit", "uploadToCloud", "pinToScreen", "dismiss", "delete"]
enabled_actions = ["copy", "delete", "dismiss", "edit", "pinToScreen", "saveOrOpen", "uploadToCloud"]

[history]
enabled = true
retention_days = 30
max_count = 500

[shortcuts.global.fullscreen]
key = "3"
modifiers = ["command", "shift"]
enabled = true
```

## Manual Testing

Use these commands to reset only the TOML config access state while keeping the
app in an existing-user state. This simulates an upgrade from a version that did
not have `config.toml` support yet.

```bash
osascript -e 'quit app "Snapzy"' 2>/dev/null || true

PLIST="$HOME/Library/Containers/com.trongduong.snapzy/Data/Library/Preferences/com.trongduong.snapzy"

defaults write "$PLIST" onboardingCompleted -bool true
defaults write "$PLIST" sponsorPromptSeen -bool true
defaults delete "$PLIST" configuration.accessOnboardingPrompted 2>/dev/null || true
defaults delete "$PLIST" configuration.directoryBookmark 2>/dev/null || true
defaults delete "$PLIST" configuration.fileBookmark 2>/dev/null || true
defaults delete "$PLIST" configuration.lastAppliedSignature 2>/dev/null || true

killall cfprefsd 2>/dev/null || true
```

To test the missing-folder path, remove the user-managed config folder before
launching Snapzy:

```bash
rm -rf "$HOME/.config/snapzy"
open -a Snapzy
```

Expected result: Snapzy opens the onboarding window directly on the config
access step. The user only needs to grant access. Snapzy creates
`~/.config/snapzy/config.toml` automatically and no manual export/import step is
required.

To test applying an existing direct edit after grant, prepare a config file
first:

```bash
mkdir -p "$HOME/.config/snapzy"
cp "$HOME/Desktop/config.toml" "$HOME/.config/snapzy/config.toml"
open -a Snapzy
```

Expected result: after the user grants access, Snapzy stores the folder
bookmark and applies the existing valid `config.toml` immediately.

To test the Settings -> Advanced warning without showing the launch step, mark
the config access onboarding step as already shown, then remove the stored
folder/file bookmarks:

```bash
osascript -e 'quit app "Snapzy"' 2>/dev/null || true

PLIST="$HOME/Library/Containers/com.trongduong.snapzy/Data/Library/Preferences/com.trongduong.snapzy"

defaults write "$PLIST" onboardingCompleted -bool true
defaults write "$PLIST" sponsorPromptSeen -bool true
defaults write "$PLIST" configuration.accessOnboardingPrompted -bool true
defaults delete "$PLIST" configuration.directoryBookmark 2>/dev/null || true
defaults delete "$PLIST" configuration.fileBookmark 2>/dev/null || true

killall cfprefsd 2>/dev/null || true
open -a Snapzy
```

Expected result: Settings -> Advanced -> Backup shows a config access warning.
Import, Export, Restore defaults, and Open config.toml are disabled until access
is granted.
Clicking the warning row or the Grant Access button opens the same folder grant
flow. Completed backup actions show a toast instead of a persistent Last Result
log section.

## Implementation Notes

- `SnapzyConfigurationService` is the facade used by Settings.
- `SnapzyConfigurationAccessGranting` owns the shared macOS folder picker flow
  used by onboarding and Settings -> Advanced. A successful grant prepares the
  default folder and file so the user does not need to export/import manually.
- Settings import replaces the managed `config.toml` after validation succeeds,
  then applies the same contents so the backup file and app state stay aligned.
- Restore defaults replaces the managed `config.toml` with a generated default
  TOML document and applies it after confirmation.
- `SnapzyConfigurationAutoImporter` runs during app launch, hashes the current
  file contents, and imports only when `config.toml` changed since the last
  successful launch-time apply.
- `SnapzyConfigurationExporter` and its shortcut extension build deterministic
  TOML so exported files are diff-friendly.
- `SnapzyConfigurationImporter` parses, validates, then applies mutations only
  after validation succeeds.
- `SimpleTOMLParser` is intentionally focused on Snapzy's schema surface:
  strings, booleans, integers, doubles, arrays, dotted keys, and nested tables.
