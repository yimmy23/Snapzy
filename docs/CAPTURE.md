# Capture, Recording, and Editing Flows

This doc follows the runtime path from trigger to saved asset, Quick Access, editors, and cloud actions.

User-facing copy in these flows is localized through `Snapzy/Shared/Localization/L10n.swift` and `Snapzy/Resources/Localization/{Shared,Features}/*.xcstrings`. Privacy permission copy lives in `InfoPlist.strings`. For localization ownership and rules, read [`LOCALIZATION.md`](LOCALIZATION.md).

## Flow Index

```mermaid
flowchart TD
    A["Trigger from menu bar or global shortcut"] --> B{"Mode"}

    B --> C["Fullscreen / Area screenshot"]
    B --> D["Scrolling capture"]
    B --> E["Capture Text (OCR / QR)"]
    B --> F["Object cutout"]
    B --> G["Record screen"]

    C --> H["ScreenCaptureManager"]
    D --> I["ScrollingCaptureCoordinator"]
    E --> J["captureAreaAsImage -> QRCodeService + OCRService"]
    F --> K["captureAreaAsImage -> ForegroundCutoutService"]
    G --> L["RecordingCoordinator -> ScreenRecordingManager"]

    H --> M["TempCaptureManager + PostCaptureActionHandler"]
    I --> M
    K --> M
    L --> M

    J --> N["Clipboard plain-text result"]

    M --> O["Quick Access"]
    M --> P["Clipboard copy"]
    M --> Q["Annotate auto-open"]

    O --> R["Annotate"]
    O --> S["Video Editor"]
    O --> T["Manual cloud upload"]
```

## Screenshot, OCR, and Cutout

```mermaid
flowchart TD
    A["ScreenCaptureViewModel"] --> B["Ensure export folder permission"]
    B --> C["Prefetch SCShareableContent when ScreenCaptureKit path needs it"]
    C --> D{"Capture mode"}

    D -->|Fullscreen| E["captureFullscreen()"]
    D -->|Area| F["FrozenAreaCaptureSession.prepare()"]
    D -->|Area + inline annotate| F1["FrozenAreaCaptureSession.prepare(all displays) -> InlineAreaAnnotateCoordinator"]
    D -->|OCR / QR| G["AreaSelectionController.startSelection()"]
    D -->|Cutout| H["AreaSelectionController.startSelection()"]

    E --> I["ScreenCaptureManager.captureAllDisplays()"]
    F --> J["AreaSelectionController.startSelection(backdrops:, applicationConfiguration:)"]
    J --> K{"Interaction mode"}
    F1 --> K0["Select region, annotate directly, finish with Command-S/Enter"]
    K -->|Manual region| K1["FrozenAreaCaptureSession.cropImage()"]
    K -->|Application window| K2["ScreenCaptureManager.captureWindow()"]
    G --> L["ScreenCaptureManager.captureAreaAsImage()"]
    H --> M["ScreenCaptureManager.captureAreaAsImage()"]

    I --> N["TempCaptureManager.resolveSaveDirectory(.screenshot)"]
    K1 --> N
    K0 --> N
    K2 --> N
    N --> O["saveImage()/saveProcessedImage()"]
    O --> P["PostCaptureActionHandler"]

    L --> Q0["Show OCR effect"]
    Q0 --> Q["QRCodeService.detect() + OCRService.recognizeText()"]
    Q --> R["Copy recognized text / QR payloads to NSPasteboard as plain text"]

    H --> S["ForegroundCutoutService.extractForegroundResult()"]
    S --> T{"Auto-crop suggested and enabled?"}
    T -->|Yes| U["Crop transparent canvas to suggested rect"]
    T -->|No| V["Keep full transparent canvas"]
    U --> W["saveProcessedImage()"]
    V --> W
    W --> P
```

### Notes

- Fullscreen runs through `ScreenCaptureManager.captureAllDisplays()` and saves one screenshot per connected display. The hot path uses `CGDisplayCreateImage` in parallel when cursor and desktop icon/widget exclusions are off; it falls back to ScreenCaptureKit for correctness when those options are enabled.
- Multi-display fullscreen post-capture is batch-aware: Quick Access and history receive every file, clipboard receives file URLs for multi-file batches, and auto-open Annotate opens only the first saved screenshot.
- Area screenshot freezes the active display first via `FrozenAreaCaptureSession`, then either crops from that cached snapshot or switches into exact window capture for application mode.
- Area screenshot freezes the active display first, then lazily prepares idle/hovered displays when possible. Area-selection overlay windows are excluded from screen capture, so lazy snapshots do not bake in the dim overlay or create a double-darkened backdrop. During an active cross-display drag, a newly crossed display stays live and is captured after mouse-up once the overlay has been hidden, avoiding a mid-drag freeze jump while preserving fast initial activation. Manual selection is tracked in global screen coordinates and rendered per display, so one selection rectangle can span multiple monitors.
- For screenshot sessions, the target display overlay now owns direct keyboard handling for `Escape` and the application-mode toggle key, so cancel still works when Snapzy starts from a background custom shortcut without depending on Accessibility-backed global key monitoring.
- `Cmd+Shift+4` area capture now has two interaction modes inside the same overlay session: manual region by default, and application window mode toggled with the configurable `Application Capture` key from Preferences → Shortcuts. The default key is `A`.
- Area + inline annotate is a separate screenshot flow with the default shortcut `Cmd+Shift+7`. Users can enable/disable or configure it from Preferences → Shortcuts. It freezes all available displays, lets the user select, move, and resize one region across the desktop coordinate space, supports both the move handle and Space-drag for moving the selected region, reuses Annotate tool models/rendering on that region, and saves the rendered image through the normal screenshot post-capture pipeline after Command-S, Enter, or Done.
- In application window mode, `AreaSelectionController` builds a front-to-back candidate list from `CGWindowListCopyWindowInfo` plus `SCShareableContent`, highlights the hovered window above the dimming overlay, and captures the selected app window on click without requiring a drag rectangle.
- Exact window capture is handled by `ScreenCaptureManager.captureWindow()`. macOS 14+ uses ScreenCaptureKit window metrics directly, then trims fully transparent capture fringe so shadow framing does not leave uneven empty canvas; macOS 13+ stays supported with the same ScreenCaptureKit path plus a safe area-capture fallback if exact capture fails.
- The frozen/manual and application-window paths both preserve existing desktop icon/widget exclusion, cursor, own-app exclusion, temp-save, Quick Access, clipboard, and annotate routing behavior.
- When own-app exclusion hides visible normal Snapzy windows for screenshot, OCR, cutout, scrolling capture, or pre-recording setup, those windows are ordered out temporarily and restored after the capture/session finishes or is cancelled.
- OCR is the only capture path that does not create a file; it captures a `CGImage`, optionally shows a lightweight OCR effect while Vision work runs, then copies text/QR payloads to the pasteboard as plain text.
- The OCR effect is controlled by `PreferencesKeys.ocrScanningOverlayEnabled` from Capture → Screenshot → OCR and is enabled by default.
- QR detection runs as local Vision work alongside OCR where possible, with capture/processing duration logged for latency checks.
- QR payload handling is passive by design: Snapzy does not open decoded URLs, perform network requests, load WebViews, execute processes, or write QR payloads as file URL pasteboard items.
- Object cutout is macOS 14+ only. JPEG is overridden to PNG because transparency must be preserved.
- Capture toasts, alerts, open-panel prompts, and error surfaces are localized through `L10n`.

## Capture Markup (Inline Area Annotate)

Capture Markup lets the user select a screen region and annotate it *before* saving — inside coordinated per-display overlays that share one desktop coordinate space. It bridges capture and editing into one continuous flow without opening the separate Annotate editor window.

```mermaid
flowchart TD
    A["Trigger (menu bar, global shortcut, or snapzy://capture/area-annotate)"] --> B["ScreenCaptureViewModel.captureAreaAnnotate()"]
    B --> C["Hide own windows (if excluded)"]
    C --> D["FrozenAreaCaptureSession.prepare() / fast snapshots for all displays"]
    D --> E["InlineAreaAnnotateCoordinator.start()"]
    E --> F["InlineAreaAnnotatePanel per display (.screenSaver level)"]
    F --> G["Phase 1: selecting — user drags a rect"]
    G --> H["Phase 2: annotating — canvas + toolbar + properties + action rail"]
    H --> I["User draws annotations"]
    H --> J["Move/resize selection (annotations offset automatically)"]
    I --> K["Finish: Cmd+S, Enter, or Done button"]
    J --> K
    K --> L["AnnotateExporter.renderFinalImage()"]
    L --> M["ScreenCaptureManager.saveProcessedImage()"]
    M --> N["PostCaptureActionHandler"]
    N --> O["Quick Access / clipboard / auto-open"]
```

### Inline Overlay Shortcuts

| Key | Action |
| --- | --- |
| `Enter` / `Return` | Finish and save |
| `⌘S` | Finish and save |
| `Esc` | Cancel and close |
| `Space` (hold) | Move selection (shows open-hand cursor) |
| `V` | Selection tool |
| `R` | Rectangle |
| `F` | Filled Rectangle |
| `O` | Oval |
| `A` | Arrow |
| `L` | Line |
| `T` | Text |
| `H` | Highlighter |
| `B` | Blur |
| `N` | Counter |
| `W` | Watermark |
| `P` | Pencil |

### Supported Tools

The inline overlay reuses the same drawing engine as the full Annotate editor and supports: Selection, Rectangle, Filled Rectangle, Oval, Arrow, Line, Text, Highlighter, Blur, Counter, Watermark, and Pencil.

Crop and Mockup are **not** available in the inline overlay (full editor only).

### Interaction Details

- **Move selection**: Hold `Space` and drag, or use the move handle in the toolbar.
- **Resize selection**: Drag any of the 8 handles (corners + edges) around the selection; cursor feedback changes per edge.
- **Quick Properties Bar**: Appears below the toolbar when a drawable tool is active. Shows context-aware controls: stroke color, fill color, text background, blur type, arrow style, watermark text/style/opacity/rotation, stroke width, font size, corner radius.
- **Action Rail**: Side rail with Done (prominent), Cancel, and Copy-to-Clipboard.
- **Multiple displays**: Capture Markup freezes every available display before showing the overlay, opens one coordinated panel per frozen display, maps display frames into one desktop coordinate space, tracks cross-display drags with a shared monitor, and uses `FrozenAreaCaptureSession.cropCompositeImage()` when the selected region spans display boundaries.
- **Cross-Spaces**: The overlay is an `NSPanel` at `.screenSaver` level with `canJoinAllSpaces` and `fullScreenAuxiliary`, so it works across Spaces.

### Notes

- The global shortcut for Capture Markup is enabled by default for new installs. Users can turn it off in Preferences → Shortcuts. The default key is `⇧⌘7`.
- The overlay reuses `AnnotateState`, `CanvasDrawingView`, and `AnnotateExporter` — no duplicated annotation logic.
- Moving or resizing the selected region refreshes the underlying cropped image while **preserving existing annotations** via `replaceSourceImagePreservingAnnotations(_:annotationOffset:)`.
- Single-display selections still use the per-display crop path; cross-display selections use the same composite crop path as frozen area capture.
- Finishing routes through the normal screenshot post-capture pipeline, so Quick Access, clipboard copy, auto-open, and history all behave identically to a standard area screenshot.
- Keyboard handling uses both local and global `NSEvent` monitors to catch `Space`, `Enter`, `Esc`, and `Cmd+S` reliably even when the app is not frontmost.

## Scrolling Capture

```mermaid
flowchart TD
    A["captureScrolling()"] --> B["AreaSelectionController.startSelection(mode: .scrollingCapture)"]
    B --> C["User selects only moving content"]
    C --> D["ScrollingCaptureCoordinator.beginSession()"]

    D --> E["Prepare region-scoped capture context"]
    D --> F["Show region overlay, HUD, preview window"]
    D --> G["Create live preview stream + shared frame ring"]
    D --> H["Create commit scheduler"]

    G --> I["ScrollingCaptureFrameSource publishes timestamped region frames"]
    I --> I1["ScrollingCaptureFrameRing keeps latest bounded frame history"]
    I1 --> J["ScrollingCapturePreviewRenderer presents stitched preview first"]

    H --> K["Initial commit or scroll-triggered commit request"]
    K --> L["ScrollingCaptureCommitScheduler keeps latest pending request"]
    L --> M["refreshPreview() commits newest eligible stream frame or still fallback"]
    M --> N["ScrollingCaptureStitcher append / ignore / pause / height-limit"]
    N --> O["Session model updates badge, caption, metrics"]

    F --> P["Global scroll monitor + settle timer"]
    P --> L

    O --> Q{"Done, cancel, or limit?"}
    Q -->|Continue| P
    Q -->|Done| R["finish() waits for idle commit lane"]
    R --> S["Flush final visible frame if needed"]
    S --> T["saveProcessedImage()"]
    T --> U["PostCaptureActionHandler"]
```

### Notes

- The subsystem in `Services/Capture/ScrollingCapture/` is intentionally self-contained: preview, stitcher, HUD, metrics, commit scheduling, and window placement all live there.
- The live stream is a low-latency frame source, not the primary visual result after capture starts.
- The preview rail prioritizes the stitched preview image so the visible result grows as accepted slices are merged.
- The preview lane and commit lane share the same bounded frame timeline through `ScrollingCaptureFrameRing`; still capture is now a fallback when the stream has no usable new frame.
- `previewTruthState` indicates whether stitched output is captured, syncing to uncommitted scroll, paused, or finalizing.
- Vision is a recovery tool inside `ScrollingCaptureStitcher`, not the default hot path.
- `ScrollingCaptureStitchUpdate.safety` marks confirmed versus unsafe stitch outcomes; final output is built from accepted slices only.
- Debug sessions emit `ScrollingCaptureDebug` lines to `~/Library/Logs/Snapzy/snapzy_YYYY-MM-DD.txt`; filter them with `grep 'ScrollingCaptureDebug' "$HOME/Library/Logs/Snapzy/snapzy_$(date +%F).txt"` when validating frame source, append deltas, confidence, safety, and final session summary.
- Session guidance, runtime badges, preview captions, and recovery toasts are localized and should stay in sync with `docs/LOCALIZATION.md`.

## Recording, GIF Output, and Smart Camera

```mermaid
flowchart TD
    A["startRecordingFlow()"] --> B{"Remember last area?"}
    B -->|Yes| C["RecordingCoordinator.showToolbar(savedRect)"]
    B -->|No| D["AreaSelectionController.startSelection(mode: .recording)"]
    D --> C

    C --> E["RecordingToolbarWindow + region overlays"]
    E --> F["prepareRecording(rect, format, quality, fps, audio flags)"]
    F --> G["ScreenRecordingManager.startRecording()"]

    G --> H["SCStream + AVAssetWriter in internal RecordingProcessing dir"]
    G --> I["RecordingMouseTracker"]
    G --> J["Optional click highlight + keystroke + annotation overlays"]

    H --> K["stopRecording()"]
    I --> K
    J --> K

    K --> K1["Move final video to export or temp capture root, delete RecordingProcessing dir"]
    K1 --> L["Persist RecordingMetadata if mouse samples are available"]
    K1 --> M{"Output mode"}

    M -->|Video| N["PostCaptureActionHandler.handleVideoCapture()"]
    M -->|GIF| O["Quick Access placeholder card"]
    O --> P["GIFConverter.convert()"]
    P --> Q["Replace Quick Access item URL with GIF"]
    Q --> R["PostCaptureActionHandler.handleVideoCapture(skipQuickAccess: true)"]

    L --> S["VideoEditorAutoFocusEngine reads metadata later"]
```

### Notes

- Recording metadata is stored separately from the media file and powers Smart Camera / Follow Mouse in the video editor.
- Recording media is written to a per-session internal `Application Support/Snapzy/Captures/RecordingProcessing/` directory first. When the writer finishes, Snapzy moves only the final video into the user export folder when Save is enabled, or into the temp capture root when Save is disabled, then deletes the processing directory and AVAssetWriter sidecars.
- Recorded system and microphone audio tracks are encoded as AAC-LC at 48 kHz stereo with an explicit stereo channel layout. When multiple audio sources are present, Snapzy normalizes the user-facing recording to one mixed AAC-LC stereo audio track for broad MP4/MOV compatibility across common players and upload platforms, while storing an editor-only multitrack audio source sidecar plus explicit track-role metadata for later per-source volume edits.
- GIF output is a two-step flow: record video first, then convert and swap the Quick Access item.
- `RecordingCoordinator` owns toolbar and overlay UX. `ScreenRecordingManager` owns media capture, timing, and metadata persistence.
- `AppStatusBarController` stays menu-first during active recording. The menu bar item keeps Snapzy's normal identity, shows the live elapsed time, and exposes stop plus pause/resume from the menu instead of left-click-to-stop.
- Opening Preferences from the menu bar during recording keeps Settings reachable without forcing a stop. When own-app capture is enabled, the active recording stream dynamically excludes that Settings window.
- Recording toolbar labels, output mode copy, microphone/save-folder alerts, and export errors are localized.

## Post-Capture Routing

```mermaid
flowchart TD
    A["Capture file is ready"] --> B["TempCaptureManager destination resolution"]
    B --> C{"Save enabled for this capture type?"}
    C -->|Yes| D["Screenshots write into user export directory"]
    C -->|No| E["Write into Application Support temp capture directory"]
    C -->|Recording Yes| D1["Record in internal processing dir, then move final video to export directory"]
    C -->|Recording No| E1["Record in internal processing dir, then move final video to temp capture root"]

    D --> F["PostCaptureActionHandler"]
    E --> F
    D1 --> F
    E1 --> F

    F --> G{"Show Quick Access?"}
    F --> H{"Copy file?"}
    F --> I{"Open Annotate? screenshot only"}

    G -->|Yes| J["QuickAccessManager.addScreenshot/addVideo"]
    G -->|No| K["No overlay card"]

    H -->|Yes| L["ClipboardHelper or file URL pasteboard write"]
    H -->|No| M["Skip clipboard"]

    I -->|Yes| N["AnnotateManager.openAnnotation(url:)"]
    I -->|No| O["Skip auto-open"]

    J --> P{"Temp file?"}
    P -->|Yes| Q["Save action moves file to export directory"]
    P -->|Dismiss| R["Temp file deleted"]
    P -->|Saved file| S["Open / drag / copy / delete"]

    J --> T{"Screenshot or video?"}
    T -->|Screenshot| U["Annotate, drag, cloud upload, save/open, delete"]
    T -->|Video or GIF| V["Video editor, drag, cloud upload, copy, save/open, delete"]
```

### Notes

- `AfterCaptureAction.save` is not a post-write callback. For screenshots it changes the destination before write; for recordings it chooses the final destination after the internal writer processing file is complete.
- Current cloud behavior is manual from Quick Access for screenshots, videos, and GIFs, plus Annotate for screenshots. The preference toggle enables those affordances; it does not auto-upload in `PostCaptureActionHandler`.
- Quick Access countdowns pause while a card is converting to GIF or uploading to cloud, then resume after the active work finishes.
- Temp captures are intentionally stored in Application Support, not `/tmp`, so drag-and-drop remains stable.
- Quick Access cards expose hover actions plus a matching context menu, opened with the cursor near the tail actions, for copy, save/open, edit, cloud upload, dismiss, and delete/trash actions. Settings → Quick Access lets users toggle actions and drag list rows to reorder the context menu. Card placement is separate: users drag actions onto the preview's center and corner slots, or drag preview actions outside the card to clear a slot.
- Quick Access action labels and post-capture error states are localized.

## Capture History Restore

```mermaid
flowchart TD
    A["History item open"] --> B["HistoryWindowController"]
    B --> C["QuickAccessManager.restoreHistoryItem()"]
    C --> D{"Quick Access item exists?"}
    D -->|Yes| E["Reuse existing card"]
    D -->|No| F["Insert restored card with history thumbnail metadata"]
    E --> G{"Capture type"}
    F --> G
    G -->|Screenshot| H["AnnotateManager.openAnnotation(for:)"]
    G -->|Video / GIF| I["VideoEditorManager.openEditor(for:)"]
```

### Notes

- Opening a capture from either history surface restores the item through Quick Access before opening the editor.
- History restore reuses an existing Quick Access card for the same file when one is already present, so the editor keeps the same item-scoped session.
- Screenshot, video, and GIF saves from restored history items follow the same Quick Access session behavior as fresh captures.

## Annotate and Cloud Re-Upload

```mermaid
flowchart TD
    A["Quick Access screenshot or auto-open"] --> B["AnnotateManager"]
    B --> C["AnnotateWindowController + AnnotateState"]
    C --> D["Canvas, crop, blur, text, watermark, shapes, mockup, cutout"]

    D --> E{"Action"}
    E -->|Save / export| F["AnnotateExporter.renderFinalImage()"]
    E -->|Copy| G["Clipboard write"]
    E -->|Share| H["NSSharingServicePicker"]
    E -->|Upload| I["CloudManager.upload()"]

    F --> J["Update file on disk"]
    J --> K["QuickAccess thumbnail refresh"]
    J --> L{"Cloud URL already exists?"}
    L -->|Yes| M["Mark item as cloud-stale"]
    L -->|No| N["No stale marker"]

    I --> O["Persist cloud URL + key"]
    O --> P["Copy public URL to clipboard"]
    O --> Q["Clear stale marker"]
```

### Notes

- Annotate windows cache session state per Quick Access item so the user can reopen the same card and keep editing.
- Canvas presets can be marked as the default for new full Annotate windows. Session restore keeps the cached canvas effects, and inline area annotate does not auto-apply this window default.
- Watermark annotations are editable items with text, style, opacity, size, rotation, and color controls; export/copy/share/upload render them through the same final image pipeline as other annotations.
- The crop tool can shrink or expand the editable canvas. Dragging crop handles outside the source image creates empty canvas space that accepts the same annotations as the original image area and is included in export/copy/share/upload.
- Drag-to-app starts with a lazy file promise and guarantees a rendered file-URL fallback for apps that do not support file promises, so the first drag attempt can be accepted by file-url-only targets.
- After a successful Annotate drag-to-app from a Quick Access item, Snapzy saves the current edits back to the source file before dismissing the Quick Access card.
- Manually opened Annotate windows from the menu bar, global shortcut, or toolbar plus button are independent, so users can work with multiple clipboard/drop sessions side by side.
- If a screenshot was already uploaded, later edits mark the cloud state stale until the user re-uploads.
- Annotate dialogs, preset actions, mockup labels, cutout/export alerts, and cloud re-upload messaging are localized.

## Video Editor

```mermaid
flowchart TD
    A["Quick Access video/GIF or empty editor"] --> B["VideoEditorManager"]
    B --> C["VideoEditorWindowController + VideoEditorState"]
    C --> D["Load asset and timeline"]
    D --> E{"Recording metadata available?"}
    E -->|Yes| F["VideoEditorAutoFocusEngine builds Follow Mouse path"]
    E -->|No| G["Manual zoom workflow only"]

    F --> H["Trim, zoom segments, wallpaper/background, export settings"]
    G --> H
    H --> I{"Export mode"}
    I -->|Video| J["VideoEditorExporter"]
    I -->|GIF| K["GIFResizer / GIF export path"]
    J --> L["Saved output file"]
    K --> L
```

### Notes

- Video preview and export apply custom volume through the same `AVAudioMix` path so Custom Volume changes are audible before saving.
- For Snapzy recordings that have an editor audio source sidecar, the editor loads that multitrack asset for preview/export while keeping save/replace operations pointed at the user-facing compatible video file.
- When the editor source exposes separate audio tracks, the editor uses stored track-role metadata keyed by `AVAssetTrack.trackID` to map system audio and microphone controls, falling back to `ScreenRecordingManager` writer order for older metadata. Custom volume preview and export share the same role-aware `AVAudioMix` path.
- Editor exports are normalized back to one mixed AAC-LC stereo audio track after multitrack export so saved files stay broadly compatible. Single-track videos keep one mixed volume control.
- Existing recordings created before the editor audio source sidecar exists contain one mixed audio track, so the editor cannot recover separated microphone/system sources from those older files.

## Key Files

| File | Responsibility |
| --- | --- |
| `Snapzy/Shared/Localization/L10n.swift` | Shared localization bridge for these flows |
| `Snapzy/Resources/Localization/{Shared,Features}/*.xcstrings` | Split runtime String Catalogs backing translated flow copy |
| `Snapzy/Features/Capture/CaptureViewModel.swift` | Entry point for screenshot, scrolling capture, OCR, cutout, and recording launch |
| `Snapzy/Services/Capture/OCRScanningOverlayWindow.swift` | Non-interactive scanning progress overlay for OCR area capture |
| `Snapzy/Services/Media/QRCodeService.swift` | Local QR payload detection for OCR capture |
| `scripts/run-qr-detection-performance-probe.sh` | Local Vision QR timing probe for OCR latency checks |
| `Snapzy/Services/Capture/ScreenCaptureManager.swift` | Core screenshot engine, frozen snapshot capture, and file writing |
| `Snapzy/Services/Capture/FrozenAreaCaptureSession.swift` | Frozen display snapshots used by area screenshot selection |
| `Snapzy/Services/Capture/PostCaptureActionHandler.swift` | Quick Access, clipboard, and screenshot auto-open routing |
| `Snapzy/Services/Capture/TempCaptureManager.swift` | Save-vs-temp destination logic and temp capture lifecycle |
| `Snapzy/Services/Capture/ScrollingCapture/ScrollingCaptureCoordinator.swift` | Long screenshot session orchestration |
| `Snapzy/Services/Capture/ScrollingCapture/ScrollingCaptureStitcher.swift` | Stitching and Vision-assisted recovery |
| `Snapzy/Features/Recording/RecordingCoordinator.swift` | Recording toolbar, overlays, stop/GIF handoff |
| `Snapzy/Services/Capture/ScreenRecordingManager.swift` | Screen recording media pipeline and metadata persistence |
| `Snapzy/Features/QuickAccess/QuickAccessManager.swift` | Floating stack state and countdown behavior |
| `Snapzy/Features/QuickAccess/Models/QuickAccessActionConfigurationStore.swift` | User-configurable Quick Access action visibility, context menu order, and card slot assignments |
| `Snapzy/Features/QuickAccess/Components/QuickAccessCardView.swift` | Card hover and context-menu actions including screenshot, video, and GIF cloud upload |
| `Snapzy/Features/History/HistoryWindowController.swift` | History restore routing through Quick Access |
| `Snapzy/Features/Annotate/AnnotateManager.swift` | Annotate window lifecycle and session caching |
| `Snapzy/Features/Annotate/InlineAreaAnnotateSession.swift` | Session state machine (selecting → annotating), key handling, finish/cancel |
| `Snapzy/Features/Annotate/InlineAreaAnnotateWindow.swift` | Full overlay UI: selection gesture, canvas, toolbar, properties bar, action rail, resize handles |
| `Snapzy/Features/Annotate/Services/AnnotateExporter.swift` | Final image render/export |
| `Snapzy/Features/VideoEditor/VideoEditorManager.swift` | Video editor window lifecycle |
| `Snapzy/Features/VideoEditor/Services/VideoEditorAutoFocusEngine.swift` | Follow Mouse / Smart Camera path reconstruction |
| `Snapzy/Services/Cloud/CloudManager.swift` | Upload facade, provider creation, history persistence |
