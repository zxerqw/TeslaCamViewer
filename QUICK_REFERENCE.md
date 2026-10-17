# TeslaCamViewer - Quick Reference Guide

## PROJECT BASICS
- **Type**: iOS 17.0+ app (Swift 5.9)
- **Purpose**: Tesla dashcam viewer/editor with 6-camera support
- **Primary Audience**: Chinese users
- **Bundle ID**: me.melkor.TeslaCamViewer

---

## FEATURE LOCATIONS AT A GLANCE

### 🎨 UI Theming / Colors / Dark Mode
- **Status**: Uses SwiftUI defaults (implicit light/dark support)
- **Key Colors**: `.black`, `.white`, `.gray`, `.blue`, `.red`
- **No custom theme file** — uses system appearance
- **Color usage**:
  - `TrimBarView.swift` (L34-51) — progress bar colors
  - `GridPlayerView.swift` (L74) — black grid background
  - `ErrorBanner.swift` (L14) — red error styling

### 🎬 Video Preview
- **Engine**: `MultiAVPlayer.swift` (90 lines) — synchronized AVPlayer per angle
- **UI**: `GridPlayerView.swift` (148 lines) — 2×2 grid with full-screen toggle
- **Playback**: `PlaybackController.swift` — @Observable state management
- **Rendering**: `PlayerLayerView.swift` — AVPlayerLayer wrapper

### 💾 Video Export
- **Main orchestrator**: `ExportJob.swift` (70 lines) — progress tracking
- **Composition engine**: `AVComposer.swift` (394 lines) — **CORE FILE**
  - `exportSingleAngle()` — single camera export
  - `exportGrid()` — 2×2 grid export (1920×1080)
- **Export config**: `ExportRequest.swift` — layout + watermark position
- **UI**: `ExportSheetView.swift` + `ExportSheetViewModel.swift`

### 📍 Watermark
- **Implementation**: CALayer + CoreAnimation in `AVComposer.swift` (L210-393)
- **Components**:
  - Dynamic timestamp (one layer per second, opacity animated)
  - Per-cell angle labels (grid mode only)
  - Position configurable: topLeft/topRight/bottomLeft/bottomRight
- **Format**: `yyyy-MM-dd HH:mm:ss` + angle labels

### 📐 4-Grid Layout (四宫格)
- **Composition**: `AVComposer.gridComposition()` (L122-206)
  - Render size: 1920×1080
  - 4 synchronized tracks with CGAffineTransform scaling+translation
  - Cell order: [0]=TL, [1]=TR, [2]=BL, [3]=BR
- **UI Display**: `GridPlayerView.swift` (L64-103)
  - 2×2 grid with tap-to-fullscreen toggle
- **Configuration**: `GridConfigSheet.swift` — customize angle per cell
- **Default angles**: [front, back, leftRepeater, rightRepeater]

### ⏱️ Progress Bar & Playback Controls
- **Trim Bar**: `TrimBarView.swift` (110 lines)
  - Components: full-track, range-bar, start/end handles, playhead line, scrub triangle
  - Interaction: draggable trim handles + playhead scrubbing
  - Colors: gray (0.3), blue (0.6), white handles
- **Controls**: `GridPlayerView.swift` (L105-135)
  - ⏪ -5s, ▶️ play/pause, ⏩ +5s

### 🏷️ Angle Labels (前/后/左后视镜/右后视镜/左B柱/右B柱)
- **Definition**: `CameraAngle.swift` — 6 enum cases
- **Filename mapping**: front, back, left_repeater, right_repeater, left_pillar, right_pillar
- **UI Labels** (multiple contexts):
  - Grid overlay: "前", "后", "左后", "右后", "左柱", "右柱"
  - Export dialog: "前 Front", "后 Back", "左后视镜", "右后视镜", "左 B 柱", "右 B 柱"
  - Watermark: "前 Front", "后 Back", "左后 L-Rep", "右后 R-Rep", "左柱 L-Pil", "右柱 R-Pil"

### 📱 Landscape/Portrait Orientation
- **Config**: `project.yml` (L33-41) — all orientations supported
- **Responsive**: SwiftUI `GeometryReader` in `GridPlayerView` + `TrimBarView`
- **Aspect ratio**: 16:9 maintained with `contentMode: .fit`
- **Device support**: iPhone 1, 2 (iPad)

---

## KEY FILE REFERENCE

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| **Camera angles** | `Domain/Models/CameraAngle.swift` | 34 | Enum + labels |
| **Export config** | `Domain/Models/ExportRequest.swift` | 39 | Layout + watermark |
| **Trim range** | `Domain/Models/TrimRange.swift` | 34 | Start/end validation |
| **Playback state** | `Domain/PlaybackController.swift` | 59 | @Observable wrapper |
| **Export job** | `Domain/ExportJob.swift` | 70 | Progress orchestration |
| **Video composition** | `Infrastructure/AVComposer.swift` | 394 | **CORE: export + watermark** |
| **Multi-player** | `Infrastructure/MultiAVPlayer.swift` | 90 | Synced playback |
| **Grid view** | `Features/GridPlayer/GridPlayerView.swift` | 148 | 2×2 + full-screen |
| **Progress bar** | `Features/GridPlayer/TrimBarView.swift` | 110 | Scrubbing + trim |
| **Export UI** | `Features/ExportSheet/ExportSheetView.swift` | 88 | Export dialog |
| **Export logic** | `Features/ExportSheet/ExportSheetViewModel.swift` | 66 | Mode + angles |
| **Grid config** | `Features/GridConfig/GridConfigSheet.swift` | 49 | Customize layout |
| **Settings** | `Features/Settings/SettingsView.swift` | 38 | Watermark + gap |
| **App shell** | `Features/Root/RootView.swift` | 134 | Navigation |
| **Dependencies** | `App/AppDependencies.swift` | 21 | DI container |

---

## ARCHITECTURE OVERVIEW

```
┌─────────────────────────────────────────┐
│            TeslaCamViewerApp            │
│        (SwiftUI Entry Point)            │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│         AppDependencies (DI)            │
├─────────────────────────────────────────┤
│ • SettingsStore (persistent prefs)      │
│ • LibraryStore (event list)             │
│ • PlaybackController (@Observable)      │
│ • ExportJob + AVComposer (video)        │
│ • TeslaCamScanner (filesystem)          │
│ • BookmarkStore (security-scoped URLs)  │
└──────────────┬──────────────────────────┘
               │
        ┌──────┼──────┐
        │      │      │
        ▼      ▼      ▼
    RootView EventList GridPlayer
        │               │
        │               ├─── GridPlayerView (2×2 grid UI)
        │               ├─── TrimBarView (progress + trim)
        │               ├─── PlayerLayerView (AVPlayer render)
        │               └─── GridConfigSheet
        │
        └─── ExportSheet
             ├─── ExportSheetView (UI)
             ├─── ExportSheetViewModel (state)
             └─── ExportJob + AVComposer (video processing)

[Domain Models]
• CameraAngle (6 angles)
• TeslaEvent (recording event)
• MinuteSegment (1-minute chunk)
• ExportRequest (export config)
• TrimRange (start/end times)

[Infrastructure]
• MultiAVPlayer (sync playback)
• AVComposer (video composition + watermark)
• TeslaCamScanner (filesystem parsing)
• BookmarkStore (persistent access)
```

---

## EXPORT FLOW

```
User clicks "导出"
    ↓
ExportSheetView (layout toggle, angle picker, watermark position)
    ↓
User clicks "开始导出"
    ↓
ExportSheetViewModel.run()
    ├─ Builds ExportRequest
    ├─ Calls ExportJob.run()
    │   ├─ Grid mode? → AVComposer.exportGrid()
    │   │   ├─ Create AVMutableComposition (4 tracks)
    │   │   ├─ Apply CGAffineTransform (scale + position)
    │   │   ├─ Attach watermark (CALayer tree)
    │   │   └─ Run AVAssetExportSession → MP4 (1920×1080)
    │   │
    │   └─ Singles mode? → AVComposer.exportSingleAngle() ×N
    │       ├─ Create AVMutableComposition (1 track)
    │       ├─ Attach watermark (CALayer)
    │       └─ Run AVAssetExportSession → MP4 ×N
    │
    └─ Save to Photos library
```

---

## WATERMARK DETAILS

**Dynamic Timestamp** (per-second CATextLayer):
- Visible only during its second: opacity animation [0,1,0,0]
- Format: `yyyy-MM-dd HH:mm:ss`
- Shadow: black, opacity 0.9, radius 3px

**Angle Labels** (grid mode only):
- Chinese + English on each quadrant
- Font: Helvetica 20pt
- Positioned 12px from left, 8px below cell top
- Shadow: same as timestamp

**CA Coordinate System** (important!):
- Y=0 is BOTTOM, Y=height is TOP (opposite of video coords)
- Row 0 (top of video) = high CA Y
- Row 1 (bottom of video) = low CA Y

**Positions**:
- `topLeft` → (pad, renderHeight - h - pad)
- `topRight` → (renderWidth - w - pad, renderHeight - h - pad)
- `bottomLeft` → (pad, pad)
- `bottomRight` → (renderWidth - w - pad, pad)

---

## VIDEO SPECS

**Single Angle Export**:
- Render size: 1280×960 (native size from video)
- Frame rate: 30 fps
- Format: MP4, highest quality

**Grid Export (4-grid)**:
- Render size: 1920×1080 (full 2×2)
- Cell size: 960×540 each
- Frame rate: 30 fps
- Format: MP4, highest quality
- Scaling: uniform scale to fit cell, centered

**Playback**:
- Synchronization: CMClockGetHostTimeClock()
- Time observer interval: 50ms
- Time tolerance: zero (precise seek)

---

## COLOR REFERENCE

| Component | Color | Opacity | Context |
|-----------|-------|---------|---------|
| Full-duration track | gray | 0.3 | Trim bar background |
| Trim range bar | blue | 0.6 | Selected region |
| Trim handles | white | 1.0 | Draggable |
| Handle outline | blue | 1.0 | Handle border |
| Playhead line | white | 1.0 | Scrub indicator |
| Playhead triangle | white | 1.0 | Scrub handle |
| Grid background | black | 1.0 | Video area |
| Player background | black | 1.0 | AVPlayer layer |
| Error banner bg | red | 0.15 | Error container |
| Error text | red | 1.0 | Error message |
| Missing angle bg | black | 1.0 | Placeholder |
| Missing angle icon | white | 0.6 | Icon |

---

## SETTINGS CONFIGURATION

**File**: `Features/Settings/SettingsView.swift`

**User-Configurable**:
1. **Recent Gap Threshold** (slider)
   - Range: 60s–1800s (1–30 minutes)
   - Default: 300s (5 minutes)
   - Used to chunk Recent events by gap

2. **Watermark Default Position** (picker)
   - Options: topLeft, topRight, bottomLeft, bottomRight
   - Persisted in AppSettings

---

## TESTING

**Test Structure**:
- `TeslaCamViewerTests/Unit/` — Model, parsing, store tests
- `TeslaCamViewerTests/Integration/` — AVComposer, MultiAVPlayer, Scanner
- **Fixtures**: `TeslaCamViewerTests/Fixtures/`
  - 4-cam recordings (saved, sentry)
  - 6-cam recordings
  - Corrupted files

---

## DEPLOYMENT

- **Min iOS**: 17.0
- **Devices**: All iPhones + iPads
- **Team ID**: SW7BAJUMAC (public, safe to commit)
- **Current Version**: 0.1.0 (Build 1)
- **Orientations**: Portrait, LandscapeLeft, LandscapeRight (iPhone); all 4 (iPad)

