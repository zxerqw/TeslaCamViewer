# TeslaCamViewer - Codebase Architecture & Analysis

## 1. PROJECT OVERVIEW

### Project Type
**iOS Mobile Application** (iPhone/iPad)
- **Target Deployment**: iOS 17.0+
- **Development Language**: Swift 5.9
- **Primary UI Framework**: SwiftUI
- **Bundle ID**: me.melkor.TeslaCamViewer
- **Primary Audience**: Chinese Tesla owners

### Purpose
TeslaCamViewer is a dashcam footage viewer and editor for Tesla's TeslaCam video recording system. It allows users to:
- Browse saved, sentry, and recent dashcam recordings
- View multi-camera angles in a 2×2 grid layout (4-grid/四宫格)
- Trim and export videos with watermarks
- Support 6 camera angles (front, back, left/right repeaters, left/right B-pillars)
- Customize grid layout and export settings

---

## 2. TECH STACK

### Core Technologies
- **UI Framework**: SwiftUI (iOS 17+)
- **Video Processing**: AVFoundation, AVPlayer, AVAssetExportSession
- **Observation Pattern**: Swift Observation framework (@Observable)
- **Concurrency**: Swift async/await with Task, TaskGroup
- **File System**: FileManager, Security-scoped file access
- **Photo Library**: Photos framework (PHAssetCollection)
- **Core Graphics**: CALayer, CoreAnimation, CGAffineTransform

### Build System
- **Project Format**: XCGen (project.yml)
- **Swift Version**: 5.9
- **Strict Concurrency**: Enabled (`SWIFT_STRICT_CONCURRENCY: complete`)
- **Code Signing**: Automatic (Development Team: SW7BAJUMAC)

### Testing
- iOS Unit Tests + Integration Tests
- Test fixtures with multi-camera recordings (4-cam, 6-cam variants)

---

## 3. DIRECTORY STRUCTURE

```
TeslaCamViewer/
├── App/
│   ├── TeslaCamViewerApp.swift        (App entry point)
│   ├── AppDependencies.swift          (Dependency injection container)
│   └── Info.plist
│
├── Domain/
│   ├── Models/
│   │   ├── CameraAngle.swift          (Enum: 6 camera angles)
│   │   ├── AppSettings.swift          (User preferences)
│   │   ├── AppError.swift             (Error types)
│   │   ├── EventType.swift            (saved/sentry/recent)
│   │   ├── EventMetadata.swift        (City, reason, timestamp)
│   │   ├── TeslaEvent.swift           (A recording event)
│   │   ├── MinuteSegment.swift        (1-minute video chunk)
│   │   ├── TrimRange.swift            (Start/end time for trimming)
│   │   └── ExportRequest.swift        (Export configuration)
│   │
│   ├── Parsing/
│   │   ├── FilenameParser.swift       (Parse MP4 filenames)
│   │   ├── FolderNameParser.swift     (Parse folder timestamps)
│   │   └── SegmentAggregator.swift    (Combine minute files into events)
│   │
│   ├── Protocols/
│   │   ├── PlayerProtocol.swift       (Abstract player interface)
│   │   ├── ComposerProtocol.swift     (Abstract video composer)
│   │   ├── ScannerProtocol.swift      (Filesystem scanner)
│   │   └── BookmarkStoreProtocol.swift (Persistent file access)
│   │
│   ├── LibraryStore.swift             (@Observable event store)
│   ├── SettingsStore.swift            (Persistent user preferences)
│   ├── PlaybackController.swift       (Playback state management)
│   ├── ExportJob.swift                (Export orchestration)
│   └── RecentChunker.swift            (Group segments by time gap)
│
├── Infrastructure/
│   ├── MultiAVPlayer.swift            (Synchronized multi-camera playback)
│   ├── AVComposer.swift               (Video composition + watermark rendering)
│   ├── TeslaCamScanner.swift          (Filesystem scanning)
│   ├── BookmarkStore.swift            (iOS security-scoped bookmarks)
│   └── PhotoLibrarySaver.swift        (Save video to photo library)
│
├── Features/
│   │
│   ├── Root/
│   │   └── RootView.swift             (App shell, navigation)
│   │
│   ├── EventList/
│   │   ├── EventListView.swift        (Tab view: saved/sentry/recent)
│   │   ├── EventListViewModel.swift   (Filter events by type)
│   │   └── EventRowView.swift         (Thumbnail + metadata row)
│   │
│   ├── GridPlayer/
│   │   ├── GridPlayerView.swift       (2×2 grid + full-screen focus mode)
│   │   ├── GridPlayerViewModel.swift  (Grid angle management)
│   │   ├── PlayerLayerView.swift      (AVPlayerLayer wrapper)
│   │   └── TrimBarView.swift          (Trim handles + playhead scrubbing)
│   │
│   ├── ExportSheet/
│   │   ├── ExportSheetView.swift      (Export UI: layout, watermark, progress)
│   │   ├── ExportSheetViewModel.swift (Export state machine)
│   │   └── PhotoLibrarySaver.swift    (Save to Photos app)
│   │
│   ├── GridConfig/
│   │   └── GridConfigSheet.swift      (Customize 2×2 grid layout)
│   │
│   ├── FolderPicker/
│   │   └── FolderPickerView.swift     (UIDocumentPickerViewController wrapper)
│   │
│   └── Settings/
│       └── SettingsView.swift         (Recent gap threshold, watermark position)
│
└── UI/
    └── ErrorBanner.swift              (Red error banner component)
```

---

## 4. KEY FEATURES & RELATED FILES

### 4.1. UI THEMING / COLORS / LIGHT MODE / DARK MODE

**Current Approach**: SwiftUI defaults + Native color system
- Uses SwiftUI semantic colors: `.black`, `.white`, `.gray`, `.red`, `.blue`, `.primary`, `.secondary`
- No custom color palette or theme manager implemented
- iOS automatic light/dark mode support via system appearance

**Key Files**:
- `TrimBarView.swift` (lines 34-51): Gray background, blue trim range, white playhead
- `GridPlayerView.swift` (lines 74, 95): `.black` background for video grid
- `PlayerLayerView.swift` (line 23): Black background in `PlayerLayerUIView`
- `ErrorBanner.swift` (line 14): Red error color with opacity
- `EventRowView.swift` (line 30): Gray placeholder for missing thumbnails
- `MissingAngleView.swift` (line 37): Black background with white opacity text

**Related Code**:
```swift
// TrimBarView: progress bar colors
Rectangle().fill(.gray.opacity(0.3))    // Full duration track
Rectangle().fill(.blue.opacity(0.6))    // Selected range
Circle().fill(.white)                   // Trim handles
Rectangle().fill(.white)                // Playhead line

// GridPlayerView: grid background
.background(.black)

// ErrorBanner: error styling
.background(Color.red.opacity(0.15))
.foregroundStyle(.red)
```

**Dark Mode Support**: ✅ Implicit (system appearance-aware)
**Light Mode Support**: ✅ Implicit (system appearance-aware)
**Custom Theme Files**: ❌ None (uses defaults)

---

### 4.2. VIDEO PREVIEW FUNCTIONALITY

**Architecture**: Multi-synchronized AVPlayer playback

**Key Files**:
1. **`Infrastructure/MultiAVPlayer.swift`** (90 lines)
   - Core playback engine for multi-camera sync
   - Properties:
     - `playersByAngle: [CameraAngle: AVPlayer]` — per-angle players
     - `currentTime, totalDuration, isPlaying` — aggregated state
   - Methods:
     - `load(event:angles:)` — Create AVMutableComposition per angle
     - `play(), pause()` — Synchronize across all players
     - `seek(to:)` — Parallel seek with task group
     - `player(for:)` — Get player for specific angle
   - **Sync Strategy**: Uses `CMClockGetHostTimeClock()` for host clock synchronization

2. **`Domain/PlaybackController.swift`** (59 lines)
   - UI-facing playback state management
   - @Observable for reactive updates
   - Attaches periodic time observer (50ms intervals)
   - Maintains `currentTime, isPlaying, totalDuration, loadedAngles`

3. **`Features/GridPlayer/PlayerLayerView.swift`** (45 lines)
   - UIViewRepresentable wrapping AVPlayerLayer
   - Video gravity: `.resizeAspect`
   - Black background

4. **`Features/GridPlayer/GridPlayerView.swift`** (148 lines)
   - SwiftUI container for 2×2 grid or full-screen single angle
   - Play/pause/seek buttons (±5 second jumps)
   - `@State var focusedAngle: CameraAngle?` — switches grid ↔ full-screen

**Playback Flow**:
```
GridPlayerView
  ├─ .task { await viewModel.load() }
  │   └─ playback.load(event, angles: allAvailable)
  │       └─ MultiAVPlayer.load() creates AVComposition per angle
  │
  ├─ PlayerLayerView (4× in grid)
  │   └─ AVPlayerLayer renders each angle
  │
  └─ Controls: play/pause/±5s seek
      └─ Task { await playback.seek(to:) }
          └─ MultiAVPlayer synchronous seek across all players
```

---

### 4.3. VIDEO EXPORT FUNCTIONALITY

**Architecture**: AVAssetExportSession with AVMutableVideoComposition

**Key Files**:

1. **`Domain/ExportRequest.swift`** (39 lines)
   - Configuration object:
     - `Layout`: `.singlesPerAngle(angles: [CameraAngle])` or `.gridCombined(angles: [CameraAngle])`
     - `WatermarkPosition`: `.topLeft, .topRight, .bottomLeft, .bottomRight`
     - `range: TrimRange` — start/end times
     - `event: TeslaEvent` — source event

2. **`Domain/ExportJob.swift`** (70 lines)
   - Orchestrates export workflow
   - @Observable with `isRunning, progress (0.0–1.0)`
   - Handles progress aggregation across multiple angle exports
   - Returns `ExportResult(outputURLs: [URL])`
   - Export to temp directory, saved to Photos app

3. **`Infrastructure/AVComposer.swift`** (394 lines) — **CORE VIDEO COMPOSITION**
   
   **Single Angle Export**:
   ```swift
   func exportSingleAngle(_ angle: CameraAngle, request: ExportRequest, to url: URL, progress: @escaping (Float) -> Void)
   ```
   - Builds AVMutableComposition by combining minute segments
   - Inserts time ranges from source files
   - Render size determined from native video size (1280×960)
   
   **Grid Export** (2×2 layout):
   ```swift
   func exportGrid(request: ExportRequest, to url: URL, progress: @escaping (Float) -> Void)
   ```
   - Creates 4 synchronized tracks (one per angle)
   - Render size: 1920×1080 (4K-like grid)
   - Applies CGAffineTransform per layer:
     - Scale factor: `min(cellW / nativeWidth, cellH / nativeHeight)`
     - Position: Top-left, top-right, bottom-left, bottom-right
   - Layer ordering: [0]=TL, [1]=TR, [2]=BL, [3]=BR
   
   **Export Settings**:
   - Preset: `AVAssetExportPresetHighestQuality`
   - Format: MP4 (.mp4)
   - Frame rate: 30 fps
   - `shouldOptimizeForNetworkUse = true`
   - Progress polling: 250ms intervals

4. **`Features/ExportSheet/ExportSheetView.swift`** (88 lines)
   - UI for export configuration:
     - Layout toggle: Grid vs. Singles
     - Angle selection (if singles mode)
     - Watermark position picker
     - Progress bar during export
     - Share button on completion

5. **`Features/ExportSheet/ExportSheetViewModel.swift`** (66 lines)
   - Mode: `.grid` or `.singles`
   - `selectedAngles: Set<CameraAngle>`
   - Aggregates progress from ExportJob
   - Saves to Photos library via PhotoLibrarySaver

**Export Layouts**:

| Layout | Output | Description |
|--------|--------|-------------|
| **Grid (四宫格)** | 1 MP4 (1920×1080) | 2×2 grid of 4 angles, all synchronized |
| **Singles** | N MP4s | One file per selected angle (independent) |

**Export Flow**:
```
User clicks "导出" (Export)
  ↓
ExportSheetView displays options
  ├─ Choose layout (grid vs. singles)
  ├─ Select angles (if singles)
  └─ Choose watermark position
  ↓
User clicks "开始导出" (Start Export)
  ↓
ExportSheetViewModel.run()
  ├─ Creates ExportRequest
  ├─ Calls ExportJob.run()
  │   └─ Calls AVComposer.exportGrid() or .exportSingleAngle()
  │       ├─ Builds AVMutableComposition from segments
  │       ├─ Attaches watermark (CALayer tree)
  │       └─ Runs AVAssetExportSession
  └─ Saves to Photos library
```

---

### 4.4. WATERMARK FUNCTIONALITY

**Implementation**: CALayer-based watermark baked into exported video

**Key File**: `Infrastructure/AVComposer.swift` (lines 210–393)

**Watermark Components**:

1. **Dynamic Timestamp**:
   - One CATextLayer per second of video
   - Opacity keyframe animation: `[0, 1, 0, 0]`
   - Only visible during its respective second
   - Format: `yyyy-MM-dd HH:mm:ss`
   - Position: Configurable (top/bottom, left/right)
   - Shadow: black (opacity 0.9, radius 3)

2. **Per-Cell Angle Labels** (grid mode only):
   - CATextLayer per grid cell showing angle name
   - Chinese + English: "前 Front", "后 Back", "左后 L-Rep", etc.
   - Positioned at top-left of each cell (12px from edge, 8px below top)
   - Font: Helvetica, 20pt

**CA Coordinate System Note**:
```swift
// CA coords: Y=0 is BOTTOM, Y=height is TOP
// Video grid: row 0 = top of video (high CA Y), row 1 = bottom (low CA Y)
let cellTopCA = renderSize.height - CGFloat(row) * cellH
let y = cellTopCA - labelH - 8
```

**Watermark Positions** (per ExportRequest.WatermarkPosition):
```swift
enum WatermarkPosition: String {
    case topLeft      → (pad, renderHeight - h - pad)
    case topRight     → (renderWidth - w - pad, renderHeight - h - pad)
    case bottomLeft   → (pad, pad)
    case bottomRight  → (renderWidth - w - pad, pad)
}
```

**Attaching Watermark**:
```swift
func attachWatermark(videoComposition: AVMutableVideoComposition, renderSize: CGSize, info: WatermarkBakeInfo)
  ├─ Create parent CALayer (full video frame)
  ├─ Add video layer (renders video content)
  ├─ Add timestamp layers (one per second with opacity animation)
  ├─ Add angle labels (if grid mode)
  └─ Assign to videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(...)
```

**Watermark Simulator Caveat**:
```swift
#if !targetEnvironment(simulator)
    attachWatermark(...)  // Skipped on simulator (XPC sandbox issue)
#endif
```

---

### 4.5. LAYOUT/GRID (4-GRID/四宫格) VIDEO COMPOSITION

**Grid Structure**: 2×2 layout (4 camera angles)

**Key Files**:

1. **`Infrastructure/AVComposer.swift`** (lines 122–206)
   - `gridComposition(request:angles:renderSize:)` — builds composition
   
2. **`Features/GridPlayer/GridPlayerView.swift`** (lines 40–75)
   - Displays 4-grid in UI
   - Renders 2×2 layout using SwiftUI GeometryReader
   
3. **`Features/GridConfig/GridConfigSheet.swift`** (49 lines)
   - Allows user to customize which angle goes in which cell

**Grid Composition Details**:

```swift
// renderSize: 1920×1080 (full video)
// cellW: 960, cellH: 540 (each quadrant)

// Cell positions (idx → row, col):
// idx=0 → row=0, col=0 → Top-left
// idx=1 → row=0, col=1 → Top-right
// idx=2 → row=1, col=0 → Bottom-left
// idx=3 → row=1, col=1 → Bottom-right

for (idx, angle) in angles.enumerated() {
    let track = comp.addMutableTrack(...)  // Add video track per angle
    
    // Build composition from segments
    for seg in request.event.segments { ... }
    
    // Apply transform: scale + translate to cell position
    let scaleF = min(cellW / nativeSize.width, cellH / nativeSize.height)
    let scaled = CGSize(width: nativeSize.width * scaleF, height: nativeSize.height * scaleF)
    
    let row = idx / 2, col = idx % 2
    let cellX = CGFloat(col) * cellW
    let cellY = CGFloat(row) * cellH
    let offsetX = cellX + (cellW - scaled.width) / 2   // Center horizontally
    let offsetY = cellY + (cellH - scaled.height) / 2  // Center vertically
    
    let t = CGAffineTransform(scaleX: scaleF, y: scaleF)
        .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    
    layer.setTransform(t, at: .zero)
}
```

**UI Grid Display** (`GridPlayerView.swift` lines 64–103):

```swift
// SwiftUI grid rendering
let cellW = geo.size.width / 2
let cellH = geo.size.height / 2

ForEach(Array(viewModel.gridAngles.enumerated()), id: \.offset) { idx, angle in
    cell(for: angle, index: idx, size: CGSize(width: cellW, height: cellH))
}

// Each cell:
PlayerLayerView(player: playback.player(for: angle))
    .frame(width: cellW, height: cellH)
    .position(x: CGFloat(col) * cellW + cellW / 2,
              y: CGFloat(row) * cellH + cellH / 2)
    .overlay(angleLabel)  // "前", "后", etc.
    .onTapGesture { focusedAngle = angle }  // Full-screen focus
```

**Default Grid**:
```swift
CameraAngle.defaultGrid = [.front, .back, .leftRepeater, .rightRepeater]
```

---

### 4.6. PROGRESS BAR / PLAYBACK CONTROLS

**Progress Bar (Trim Bar)**:

**File**: `Features/GridPlayer/TrimBarView.swift` (110 lines)

**Components**:
1. **Full-duration background track** (gray, 0.3 opacity)
2. **Selected range bar** (blue, 0.6 opacity)
3. **Start trim handle** (white circle + blue outline, draggable)
4. **End trim handle** (white circle + blue outline, draggable)
5. **Playhead vertical line** (white, 2pt wide)
6. **Playhead scrub handle** (down-pointing triangle, white)

**Geometry**:
```swift
private let inset: CGFloat = 20           // Horizontal margins
private let handleSize: CGFloat = 20      // Visual size of handle
private let hitSize: CGFloat = 44         // Apple HIG minimum touch target
private let trimY: CGFloat = 24           // Vertical center of trim bar
private let playheadHandleY: CGFloat = 56 // Vertical center of scrub handle

// Usage:
let startX = inset + startFrac * usable
let endX = inset + endFrac * usable
let currX = inset + currFrac * usable
```

**Interaction**:
```swift
// Start handle drag
.gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
    .onChanged { g in
        let clamped = min(max(inset, g.location.x), endX - 4)
        let frac = Double((clamped - inset) / usable)
        trimStart = CMTime(seconds: frac * total, preferredTimescale: 600)
        onScrub(trimStart)
    })

// Playhead scrub handle drag
.onChanged { g in
    let clamped = min(max(inset, g.location.x), inset + usable)
    let frac = Double((clamped - inset) / usable)
    let t = CMTime(seconds: frac * total, preferredTimescale: 600)
    onScrub(t)  // Seek immediately
}
```

**Playback Controls**:

**File**: `Features/GridPlayer/GridPlayerView.swift` (lines 105–135)

**Controls**:
```swift
HStack(spacing: 24) {
    Button { seek(currentTime - 5s) }  // ⏪ Go back 5 sec
        label: { Image(systemName: "gobackward.5") }
    
    Button { play() | pause() }         // ▶️ / ⏸️ Play/pause toggle
        label: { Image(systemName: viewModel.playback.isPlaying ? "pause.fill" : "play.fill") }
    
    Button { seek(currentTime + 5s) }  // ⏩ Go forward 5 sec
        label: { Image(systemName: "goforward.5") }
}
```

---

### 4.7. VIEW ANGLE LABELS (前/后/左后视镜/右后视镜/左B柱/右B柱)

**Camera Angles Supported**:

**File**: `Domain/Models/CameraAngle.swift`

```swift
public enum CameraAngle: String, CaseIterable, Codable, Hashable {
    case front           // 前 (Front)
    case back            // 后 (Back)
    case leftRepeater    // 左后 or 左后视镜 (Left Repeater / L-Rep)
    case rightRepeater   // 右后 or 右后视镜 (Right Repeater / R-Rep)
    case leftPillar      // 左柱 or 左B柱 (Left B-pillar)
    case rightPillar     // 右柱 or 右B柱 (Right B-pillar)
}
```

**Filename Suffixes** (as used by Tesla):
```
front        → "front"
back         → "back"
leftRepeater → "left_repeater"
rightRepeater → "right_repeater"
leftPillar   → "left_pillar"
rightPillar  → "right_pillar"
```

**UI Labels**:

| File | Component | Labels |
|------|-----------|--------|
| `GridPlayerView.swift` | Angle label overlay (grid cells) | "前", "后", "左后", "右后", "左柱", "右柱" |
| `ExportSheetView.swift` | Export dialog | "前 Front", "后 Back", "左后视镜", "右后视镜", "左 B 柱", "右 B 柱" |
| `GridConfigSheet.swift` | Grid configuration | Same as ExportSheet |
| `AVComposer.swift` | Watermark labels (exported video) | "前 Front", "后 Back", "左后 L-Rep", "右后 R-Rep", "左柱 L-Pil", "右柱 R-Pil" |

**Label Functions**:
```swift
// GridPlayerView (short labels)
func angleLabel(_ a: CameraAngle) -> String {
    switch a {
    case .front: return "前"
    case .back: return "后"
    case .leftRepeater: return "左后"
    case .rightRepeater: return "右后"
    case .leftPillar: return "左柱"
    case .rightPillar: return "右柱"
    }
}

// ExportSheetView (detailed labels)
func label(_ a: CameraAngle) -> String {
    switch a {
    case .front: return "前 Front"
    case .back: return "后 Back"
    case .leftRepeater: return "左后视镜"
    case .rightRepeater: return "右后视镜"
    case .leftPillar: return "左 B 柱"
    case .rightPillar: return "右 B 柱"
    }
}

// AVComposer watermark labels
func angleLabel(_ a: CameraAngle) -> String {
    switch a {
    case .front: return "前 Front"
    case .back: return "后 Back"
    case .leftRepeater: return "左后 L-Rep"
    case .rightRepeater: return "右后 R-Rep"
    case .leftPillar: return "左柱 L-Pil"
    case .rightPillar: return "右柱 R-Pil"
    }
}
```

---

### 4.8. LANDSCAPE / PORTRAIT ORIENTATION HANDLING

**Configuration**: `project.yml` (lines 33–41)

```yaml
UISupportedInterfaceOrientations:
  - UIInterfaceOrientationPortrait
  - UIInterfaceOrientationLandscapeLeft
  - UIInterfaceOrientationLandscapeRight

UISupportedInterfaceOrientations~ipad:
  - UIInterfaceOrientationPortrait
  - UIInterfaceOrientationPortraitUpsideDown
  - UIInterfaceOrientationLandscapeLeft
  - UIInterfaceOrientationLandscapeRight
```

**Supported Orientations**:
- iPhone: Portrait, Landscape Left, Landscape Right
- iPad: Portrait, Portrait Upside-Down, Landscape Left, Landscape Right

**SwiftUI Responsiveness**:

1. **GridPlayerView**: Uses `GeometryReader` for responsive layout
   ```swift
   GeometryReader { geo in
       let cellW = geo.size.width / 2
       let cellH = geo.size.height / 2
       // Dynamically sizes grid cells
   }
   ```

2. **TrimBarView**: Uses `GeometryReader` for responsive scrubber
   ```swift
   GeometryReader { geo in
       let usable = max(1, geo.size.width - inset * 2)
       // Scales handle positions
   }
   ```

3. **AspectRatio Preservation**:
   ```swift
   GridPlayerView {
       .aspectRatio(16/9, contentMode: .fit)
       .background(.black)
   }
   ```

**Device Support**:
- Devices: All iPhones (iPhone 12+), all iPads
- Device Family: 1 (iPhone), 2 (iPad)
  ```yaml
  TARGETED_DEVICE_FAMILY: "1,2"
  ```

---

## 5. ARCHITECTURE PATTERNS

### 5.1. Dependency Injection
**File**: `App/AppDependencies.swift`
```swift
@MainActor
final class AppDependencies {
    let settings: SettingsStore
    let bookmarks: BookmarkStoreProtocol
    let scanner: ScannerProtocol
    let library: LibraryStore
    let playback: PlaybackController
    let exportJob: ExportJob
}
```
All major services initialized at app launch, passed via constructor.

### 5.2. Observation Pattern (@Observable)
- **PlaybackController**: Reactive playback state (currentTime, isPlaying, totalDuration)
- **ExportJob**: Progress updates during export
- **LibraryStore**: Event list reactivity
- **ExportSheetViewModel**: Mode, selectedAngles, progress
- **GridPlayerViewModel**: Grid angle configuration

### 5.3. Protocol-Based Design
- **PlayerProtocol**: Abstract multi-camera playback (implemented by MultiAVPlayer)
- **ComposerProtocol**: Abstract video composition (implemented by AVComposer)
- **ScannerProtocol**: Abstract filesystem scanning (implemented by TeslaCamScanner)
- **BookmarkStoreProtocol**: Abstract persistent file access (implemented by BookmarkStore)

### 5.4. MVVM with SwiftUI
- **ViewModel** examples: GridPlayerViewModel, ExportSheetViewModel, EventListViewModel
- State management via @Observable and @Binding

---

## 6. IMPORTANT FILE PATHS (COMPREHENSIVE LIST)

### App Entry Point
- `TeslaCamViewer/App/TeslaCamViewerApp.swift`
- `TeslaCamViewer/App/AppDependencies.swift`

### Domain Models
- `TeslaCamViewer/Domain/Models/CameraAngle.swift` ← **Camera angle enums**
- `TeslaCamViewer/Domain/Models/AppSettings.swift` ← **User settings (watermark, recent gap)**
- `TeslaCamViewer/Domain/Models/AppError.swift`
- `TeslaCamViewer/Domain/Models/TeslaEvent.swift` ← **Event data structure**
- `TeslaCamViewer/Domain/Models/MinuteSegment.swift`
- `TeslaCamViewer/Domain/Models/EventMetadata.swift`
- `TeslaCamViewer/Domain/Models/EventType.swift` ← **saved/sentry/recent**
- `TeslaCamViewer/Domain/Models/TrimRange.swift` ← **Trim start/end**
- `TeslaCamViewer/Domain/Models/ExportRequest.swift` ← **Export configuration**

### Domain Logic
- `TeslaCamViewer/Domain/LibraryStore.swift` ← **Event list management**
- `TeslaCamViewer/Domain/SettingsStore.swift` ← **Persistent user preferences**
- `TeslaCamViewer/Domain/PlaybackController.swift` ← **Playback state**
- `TeslaCamViewer/Domain/ExportJob.swift` ← **Export orchestration**
- `TeslaCamViewer/Domain/RecentChunker.swift`
- `TeslaCamViewer/Domain/Parsing/FilenameParser.swift`
- `TeslaCamViewer/Domain/Parsing/FolderNameParser.swift`
- `TeslaCamViewer/Domain/Parsing/SegmentAggregator.swift`

### Protocols
- `TeslaCamViewer/Domain/Protocols/PlayerProtocol.swift`
- `TeslaCamViewer/Domain/Protocols/ComposerProtocol.swift`
- `TeslaCamViewer/Domain/Protocols/ScannerProtocol.swift`
- `TeslaCamViewer/Domain/Protocols/BookmarkStoreProtocol.swift`

### Infrastructure
- `TeslaCamViewer/Infrastructure/MultiAVPlayer.swift` ← **Multi-camera playback**
- `TeslaCamViewer/Infrastructure/AVComposer.swift` ← **Video composition + watermark** (394 lines)
- `TeslaCamViewer/Infrastructure/TeslaCamScanner.swift` ← **Filesystem scanning**
- `TeslaCamViewer/Infrastructure/BookmarkStore.swift` ← **Security-scoped access**
- `TeslaCamViewer/Infrastructure/PhotoLibrarySaver.swift` ← **Save to Photos app** (?)

### UI Screens
- `TeslaCamViewer/Features/Root/RootView.swift` ← **App shell**
- `TeslaCamViewer/Features/EventList/EventListView.swift` ← **Tab: saved/sentry/recent**
- `TeslaCamViewer/Features/EventList/EventListViewModel.swift`
- `TeslaCamViewer/Features/EventList/EventRowView.swift`
- `TeslaCamViewer/Features/GridPlayer/GridPlayerView.swift` ← **2×2 grid + player**
- `TeslaCamViewer/Features/GridPlayer/GridPlayerViewModel.swift`
- `TeslaCamViewer/Features/GridPlayer/PlayerLayerView.swift` ← **AVPlayerLayer wrapper**
- `TeslaCamViewer/Features/GridPlayer/TrimBarView.swift` ← **Progress bar + trim**
- `TeslaCamViewer/Features/ExportSheet/ExportSheetView.swift` ← **Export UI**
- `TeslaCamViewer/Features/ExportSheet/ExportSheetViewModel.swift`
- `TeslaCamViewer/Features/ExportSheet/PhotoLibrarySaver.swift`
- `TeslaCamViewer/Features/GridConfig/GridConfigSheet.swift` ← **Customize grid layout**
- `TeslaCamViewer/Features/FolderPicker/FolderPickerView.swift`
- `TeslaCamViewer/Features/Settings/SettingsView.swift` ← **Recent gap, watermark position**

### UI Components
- `TeslaCamViewer/UI/ErrorBanner.swift` ← **Error display component**

### Configuration
- `project.yml` ← **Build configuration, orientations, permissions**
- `TeslaCamViewer/Info.plist`

### Tests
- `TeslaCamViewerTests/Unit/` — Unit tests for models, parsing, stores
- `TeslaCamViewerTests/Integration/` — Integration tests (AVComposer, MultiAVPlayer, Scanner)
- `TeslaCamViewerTests/SmokeTest.swift`

---

## 7. KEY TECHNOLOGIES & PATTERNS SUMMARY

| Feature | Technology | Key File(s) |
|---------|-----------|------------|
| **Multi-camera playback** | AVPlayer + AVMutableComposition | MultiAVPlayer.swift |
| **Video export** | AVAssetExportSession + AVMutableVideoComposition | AVComposer.swift |
| **Watermark baking** | CALayer + AVVideoCompositionCoreAnimationTool | AVComposer.swift |
| **4-grid composition** | CGAffineTransform (scale + translate per layer) | AVComposer.swift (gridComposition) |
| **Progress bar/scrubbing** | GeometryReader + DragGesture + CMTime | TrimBarView.swift |
| **File access** | Security-scoped URLs + FileManager | BookmarkStore.swift |
| **Persistence** | UserDefaults (via AppSettings, SettingsStore) | SettingsStore.swift |
| **UI State Management** | @Observable + @Binding | PlaybackController.swift, ExportSheetViewModel.swift |
| **Orientation support** | SwiftUI GeometryReader + device family config | project.yml, GridPlayerView.swift |
| **Dark/Light mode** | SwiftUI semantic colors (implicit) | All color usage |
| **Photos integration** | Photos framework | PhotoLibrarySaver.swift |

---

## 8. BUILD & DEPLOYMENT

**Project Configuration**:
- **Swift Version**: 5.9
- **Minimum Deployment**: iOS 17.0
- **Build System**: XCGen (from project.yml)
- **Code Signing**: Automatic (Team: SW7BAJUMAC)
- **Strict Concurrency**: Enabled

**Output**:
- **App Name**: TeslaCamViewer
- **Bundle ID**: me.melkor.TeslaCamViewer
- **Version**: 0.1.0 (Build 1)

**Test Configuration**:
- Test Target: TeslaCamViewerTests
- Coverage enabled
- Test fixtures included (Fixtures/ directory)

---

## 9. SUMMARY

**TeslaCamViewer** is a production-grade iOS app for browsing and editing Tesla dashcam footage. It leverages:

1. **Clean architecture** (App/Domain/Infrastructure/Features) with dependency injection
2. **Modern Swift patterns** (@Observable, async/await, Sendable)
3. **Advanced video composition** for synchronized multi-camera playback and grid export
4. **Watermark rendering** via CoreAnimation layer compositing
5. **Responsive UI** via SwiftUI GeometryReader for landscape/portrait
6. **Chinese localization** with user-centric features (angle labels, export formats)

**Key strengths**:
- Modular, protocol-based design
- Comprehensive test suite with fixtures
- Strict concurrency enabled (thread-safe)
- Efficient video processing with progress tracking

**Areas for potential enhancement**:
- Custom theme/color system (currently uses defaults)
- Offline caching of thumbnails
- More granular video export settings (bitrate, resolution, codec)

