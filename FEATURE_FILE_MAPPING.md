# TeslaCamViewer - Feature-to-File Mapping

## Your Requirements → Corresponding Files

| Requirement | Primary File(s) | Key Location | Lines | Notes |
|---|---|---|---|---|
| **UI Theming / Light Mode / Dark Mode / Background Colors** | `TrimBarView.swift` | `TeslaCamViewer/Features/GridPlayer/` | 34-51 | Gray (0.3), blue (0.6), white — no theme system |
| | `GridPlayerView.swift` | `TeslaCamViewer/Features/GridPlayer/` | 74 | `.black` background |
| | `PlayerLayerView.swift` | `TeslaCamViewer/Features/GridPlayer/` | 23 | Black UIView background |
| | `ErrorBanner.swift` | `TeslaCamViewer/UI/` | 14 | Red (0.15) error styling |
| | `EventRowView.swift` | `TeslaCamViewer/Features/EventList/` | 30 | Gray placeholder for thumbnails |
| | `project.yml` | Root | — | No dark mode config (uses system defaults) |
| **VIDEO PREVIEW FUNCTIONALITY** | `MultiAVPlayer.swift` | `TeslaCamViewer/Infrastructure/` | 1-90 | Synchronized playback engine |
| | `PlaybackController.swift` | `TeslaCamViewer/Domain/` | 1-59 | @Observable playback state |
| | `GridPlayerView.swift` | `TeslaCamViewer/Features/GridPlayer/` | 1-148 | UI with 2×2 grid + full-screen toggle |
| | `PlayerLayerView.swift` | `TeslaCamViewer/Features/GridPlayer/` | 1-45 | AVPlayerLayer wrapper |
| | `PlaybackController.swift` | `TeslaCamViewer/Domain/` | 48-57 | Time observer (50ms interval) |
| **VIDEO EXPORT FUNCTIONALITY** | `AVComposer.swift` | `TeslaCamViewer/Infrastructure/` | 1-394 | **MAIN FILE**: composition + watermark |
| | `ExportJob.swift` | `TeslaCamViewer/Domain/` | 1-70 | Progress orchestration |
| | `ExportRequest.swift` | `TeslaCamViewer/Domain/Models/` | 1-39 | Export configuration |
| | `ExportSheetView.swift` | `TeslaCamViewer/Features/ExportSheet/` | 1-88 | Export UI |
| | `ExportSheetViewModel.swift` | `TeslaCamViewer/Features/ExportSheet/` | 1-66 | Export state machine |
| | `PhotoLibrarySaver.swift` | `TeslaCamViewer/Features/ExportSheet/` | — | Save to Photos app |
| | `AVComposer.exportSingleAngle()` | `TeslaCamViewer/Infrastructure/AVComposer.swift` | 12-29 | Single angle export method |
| | `AVComposer.exportGrid()` | `TeslaCamViewer/Infrastructure/AVComposer.swift` | 33-56 | Grid export method |
| **WATERMARK FUNCTIONALITY** | `AVComposer.attachWatermark()` | `TeslaCamViewer/Infrastructure/AVComposer.swift` | 267-369 | Main watermark attachment |
| | `AVComposer.timestampFrame()` | `TeslaCamViewer/Infrastructure/AVComposer.swift` | 371-381 | Watermark position calculation |
| | `AVComposer.angleLabel()` | `TeslaCamViewer/Infrastructure/AVComposer.swift` | 383-392 | Angle label text |
| | `ExportRequest.WatermarkPosition` | `TeslaCamViewer/Domain/Models/ExportRequest.swift` | 23-25 | Position enum |
| | `AppSettings.defaultWatermarkPosition` | `TeslaCamViewer/Domain/Models/AppSettings.swift` | 8 | User preference |
| | `SettingsView.swift` (Section "水印") | `TeslaCamViewer/Features/Settings/SettingsView.swift` | 24-30 | Watermark position picker |
| **LAYOUT/GRID (4-GRID/四宫格) VIDEO COMPOSITION** | `AVComposer.gridComposition()` | `TeslaCamViewer/Infrastructure/AVComposer.swift` | 122-206 | 2×2 composition builder |
| | `GridPlayerView.swift` | `TeslaCamViewer/Features/GridPlayer/` | 40-75 | UI grid display |
| | `GridPlayerView.cell()` | `TeslaCamViewer/Features/GridPlayer/GridPlayerView.swift` | 77-103 | Individual cell rendering |
| | `GridConfigSheet.swift` | `TeslaCamViewer/Features/GridConfig/` | 1-49 | Customize grid layout |
| | `CameraAngle.defaultGrid` | `TeslaCamViewer/Domain/Models/CameraAngle.swift` | 30-32 | Default 4 angles |
| | `GridPlayerViewModel` | `TeslaCamViewer/Features/GridPlayer/` | 1-30 | Grid angle state |
| **PROGRESS BAR / PLAYBACK CONTROLS** | `TrimBarView.swift` | `TeslaCamViewer/Features/GridPlayer/` | 1-110 | Trim bar + playhead scrubbing |
| | `TrimBarView.swift` (components) | `TeslaCamViewer/Features/GridPlayer/TrimBarView.swift` | 34-51 | Bar, handles, playhead visualization |
| | `TrimBarView.gesture()` | `TeslaCamViewer/Features/GridPlayer/TrimBarView.swift` | 55-80 | Drag interactions |
| | `GridPlayerView.controls` | `TeslaCamViewer/Features/GridPlayer/GridPlayerView.swift` | 105-135 | ⏪ -5s, ▶️ play/pause, ⏩ +5s buttons |
| | `PlaybackController.seek()` | `TeslaCamViewer/Domain/PlaybackController.swift` | 37-40 | Seek implementation |
| **VIEW ANGLE LABELS (前/后/左后视镜/右后视镜/左B柱/右B柱)** | `CameraAngle.swift` | `TeslaCamViewer/Domain/Models/` | 1-34 | Enum with 6 cases |
| | `CameraAngle.fileSuffix` | `TeslaCamViewer/Domain/Models/CameraAngle.swift` | 12-21 | Filename mapping |
| | `GridPlayerView.angleLabel()` | `TeslaCamViewer/Features/GridPlayer/GridPlayerView.swift` | 137-146 | Short labels: "前", "后", etc. |
| | `ExportSheetView.label()` | `TeslaCamViewer/Features/ExportSheet/ExportSheetView.swift` | 67-76 | Detailed labels: "前 Front", "左后视镜", etc. |
| | `GridConfigSheet.label()` | `TeslaCamViewer/Features/GridConfig/GridConfigSheet.swift` | 38-47 | Same as ExportSheet |
| | `AVComposer.angleLabel()` | `TeslaCamViewer/Infrastructure/AVComposer.swift` | 383-392 | Watermark labels: "前 Front", "左后 L-Rep", etc. |
| **LANDSCAPE/PORTRAIT ORIENTATION HANDLING** | `project.yml` | Root | 33-41 | Orientation config |
| | `GridPlayerView.aspectRatio()` | `TeslaCamViewer/Features/GridPlayer/GridPlayerView.swift` | 73 | 16:9 aspect ratio |
| | `GridPlayerView.GeometryReader` | `TeslaCamViewer/Features/GridPlayer/GridPlayerView.swift` | 41 | Responsive sizing |
| | `TrimBarView.GeometryReader` | `TeslaCamViewer/Features/GridPlayer/TrimBarView.swift` | 22 | Responsive scrubber |
| | `project.yml` (TARGETED_DEVICE_FAMILY) | Root | — | "1,2" (iPhone + iPad) |

---

## File Size & Complexity Reference

| File | LOC | Complexity | Purpose |
|------|-----|-----------|---------|
| `AVComposer.swift` | 394 | ⭐⭐⭐⭐⭐ | **MOST IMPORTANT** — video composition, watermark, grid layout |
| `GridPlayerView.swift` | 148 | ⭐⭐⭐ | Grid UI, full-screen toggle, playback controls |
| `TrimBarView.swift` | 110 | ⭐⭐⭐ | Progress bar, trim handles, playhead scrubbing |
| `RootView.swift` | 134 | ⭐⭐⭐ | App shell, navigation, folder picking |
| `MultiAVPlayer.swift` | 90 | ⭐⭐⭐ | Synchronized multi-camera playback |
| `ExportSheetView.swift` | 88 | ⭐⭐ | Export UI |
| `PlaybackController.swift` | 59 | ⭐⭐ | Playback state management |
| `ExportJob.swift` | 70 | ⭐⭐ | Export orchestration |
| `ExportSheetViewModel.swift` | 66 | ⭐⭐ | Export state machine |
| `EventListView.swift` | 45 | ⭐ | Event list UI |
| `PlayerLayerView.swift` | 45 | ⭐ | AVPlayerLayer wrapper |
| `ExportRequest.swift` | 39 | ⭐ | Data structure |
| `CameraAngle.swift` | 34 | ⭐ | Enum with 6 camera types |
| `TrimRange.swift` | 34 | ⭐ | Time range validation |
| `AppSettings.swift` | 20 | ⭐ | Settings model |
| `GridConfigSheet.swift` | 49 | ⭐⭐ | Grid customization UI |

---

## Color Usage Across Features

```
UI Theming:
├─ Black backgrounds
│  ├─ GridPlayerView (video area)
│  ├─ PlayerLayerView (video rendering)
│  └─ MissingAngleView (placeholder)
│
├─ Gray (#808080 with opacity 0.3)
│  └─ TrimBarView (full-duration track)
│
├─ Blue (#0066FF with opacity 0.6)
│  └─ TrimBarView (selected range)
│
├─ White (#FFFFFF)
│  ├─ TrimBarView (handles, playhead, line)
│  ├─ Angle labels (overlays)
│  └─ Text (primary content)
│
├─ Red (#FF3B30 with opacity 0.15 background, 1.0 text)
│  └─ ErrorBanner (error messages)
│
└─ System semantic colors
   ├─ .primary (text)
   ├─ .secondary (subtext)
   └─ Automatic light/dark mode adaptation
```

---

## Quick Search Guide

**Looking for...**
- **Video composition logic?** → `AVComposer.swift` (lines 122–206 for grid, 60–118 for single)
- **Watermark rendering?** → `AVComposer.attachWatermark()` (lines 267–369)
- **Grid UI?** → `GridPlayerView.swift` (lines 40–75 for layout, 77–103 for cells)
- **Trim bar?** → `TrimBarView.swift` (entire file, 110 lines)
- **Playback sync?** → `MultiAVPlayer.swift` (entire file, 90 lines)
- **Export dialog?** → `ExportSheetView.swift` (entire file, 88 lines)
- **Camera angles?** → `CameraAngle.swift` (entire file, 34 lines)
- **Settings UI?** → `SettingsView.swift` (lines 8–38)
- **Angle labels?** → Search for `angleLabel()` function (4 variants across files)
- **Color definitions?** → `TrimBarView.swift` (lines 34–51)
- **Orientation support?** → `project.yml` (lines 33–41) + `GridPlayerView.swift` (GeometryReader)

