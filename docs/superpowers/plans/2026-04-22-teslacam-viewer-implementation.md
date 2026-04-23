# TeslaCamViewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an iOS 17+ App that browses Tesla TeslaCam USB footage and exports watermarked video clips (single-angle or 2×2 grid) from Saved / Sentry / Recent events.

**Architecture:** Three-layer separation — Infrastructure (file scanning, AVFoundation playback & composition) → Domain (`@Observable` stores and use cases) → SwiftUI Views. Domain depends on Infrastructure only via protocols; the `App` entry assembles concrete implementations.

**Tech Stack:** Swift 5.9+, SwiftUI, AVFoundation, XCTest, xcodegen (project generation), xcbeautify (log formatting), xcodebuild, Xcode 15.3+ / Xcode 26.

**Design reference:** `docs/superpowers/specs/2026-04-22-teslacam-viewer-design.md`

**Tooling prerequisites** — all already installed at `/opt/homebrew/bin/`:

```bash
which xcodegen xcbeautify xcodebuild
# /opt/homebrew/bin/xcodegen
# /opt/homebrew/bin/xcbeautify
# /usr/bin/xcodebuild
```

If not present: `brew install xcodegen xcbeautify`. ffmpeg (only needed once for T7): `brew install ffmpeg`.

---

## File Structure

All paths are relative to the project root `/Users/shanehou/Developer/Projects/TeslaCamViewer/`.

```
TeslaCamViewer.xcodeproj/                    Xcode project
TeslaCamViewer/                              App target source
  ├── App/
  │    ├── TeslaCamViewerApp.swift           @main entry; assembles dependencies
  │    └── AppDependencies.swift             DI container (concrete Scanner, Composer instances)
  ├── Domain/
  │    ├── Models/
  │    │    ├── CameraAngle.swift            enum + fileSuffix + defaultGrid
  │    │    ├── EventType.swift              enum (saved/sentry/recent)
  │    │    ├── MinuteSegment.swift          struct
  │    │    ├── TeslaEvent.swift             struct + totalDuration
  │    │    ├── EventMetadata.swift          struct (Codable from event.json)
  │    │    ├── TrimRange.swift              struct + invariants
  │    │    ├── ExportRequest.swift          struct + Layout + WatermarkPosition
  │    │    ├── AppSettings.swift            struct (Codable)
  │    │    └── AppError.swift               LocalizedError enum
  │    ├── Parsing/
  │    │    ├── FilenameParser.swift         parse "YYYY-MM-DD_HH-MM-SS-{angle}.mp4"
  │    │    ├── FolderNameParser.swift       parse "YYYY-MM-DD_HH-MM-SS" → Date
  │    │    └── SegmentAggregator.swift      group files → [MinuteSegment]
  │    ├── RecentChunker.swift               split [MinuteSegment] by gap threshold
  │    ├── Protocols/
  │    │    ├── ScannerProtocol.swift
  │    │    ├── BookmarkStoreProtocol.swift
  │    │    ├── PlayerProtocol.swift
  │    │    └── ComposerProtocol.swift
  │    ├── LibraryStore.swift                @Observable holds events; re-chunk on settings change
  │    ├── SettingsStore.swift               @Observable wraps AppSettings + UserDefaults
  │    ├── PlaybackController.swift          @Observable façade around PlayerProtocol
  │    └── ExportJob.swift                   orchestrates ComposerProtocol runs + Photos write
  ├── Infrastructure/
  │    ├── TeslaCamScanner.swift             concrete ScannerProtocol
  │    ├── BookmarkStore.swift               concrete BookmarkStoreProtocol (UserDefaults)
  │    ├── MultiAVPlayer.swift               concrete PlayerProtocol (≤4 AVPlayers + sourceClock)
  │    └── AVComposer.swift                  concrete ComposerProtocol (AVMutableComposition + CALayer)
  ├── Features/
  │    ├── Root/
  │    │    └── RootView.swift               first-launch gate vs. main TabView
  │    ├── FolderPicker/
  │    │    └── FolderPickerView.swift       UIDocumentPicker wrapper for folder mode
  │    ├── EventList/
  │    │    ├── EventListView.swift          TabView: Saved / Sentry / Recent
  │    │    ├── EventListViewModel.swift     @Observable binds LibraryStore per-tab
  │    │    └── EventRowView.swift           one row: thumbnail + time + metadata
  │    ├── GridPlayer/
  │    │    ├── GridPlayerView.swift         2×2 grid of AVPlayerLayers + TrimBar
  │    │    ├── GridPlayerViewModel.swift    @Observable
  │    │    ├── PlayerLayerView.swift        UIViewRepresentable wrapping AVPlayerLayer
  │    │    └── TrimBarView.swift            thumbnail strip + two handles + playhead
  │    ├── GridConfig/
  │    │    └── GridConfigSheet.swift        pick which 4 angles are shown
  │    ├── ExportSheet/
  │    │    ├── ExportSheetView.swift
  │    │    └── ExportSheetViewModel.swift
  │    └── Settings/
  │         └── SettingsView.swift           Recent-gap slider + watermark default + reset folder
  └── UI/
       ├── ErrorBanner.swift                 displays AppError
       └── Theme.swift                       color/spacing constants

TeslaCamViewerTests/                         unit + integration test target
  ├── Unit/
  │    ├── CameraAngleTests.swift
  │    ├── FilenameParserTests.swift
  │    ├── FolderNameParserTests.swift
  │    ├── SegmentAggregatorTests.swift
  │    ├── RecentChunkerTests.swift
  │    ├── TeslaEventTests.swift             totalDuration + availableAngles
  │    ├── TrimRangeTests.swift
  │    ├── AppSettingsTests.swift            Codable roundtrip
  │    ├── AppErrorTests.swift               LocalizedError strings
  │    └── LibraryStoreTests.swift           re-chunk on settings change (uses fake Scanner)
  ├── Integration/
  │    └── TeslaCamScannerTests.swift        runs against Fixtures/*
  └── Fixtures/
       ├── README.md                         how to regenerate the MP4s
       ├── generate-fixtures.sh              uses ffmpeg + touch -t to mint samples
       ├── fixture-6cam-saved/TeslaCam/...
       ├── fixture-4cam-sentry/TeslaCam/...
       ├── fixture-corrupted/TeslaCam/...
       ├── fixture-recent-continuous/TeslaCam/...
       └── fixture-recent-gapped/TeslaCam/...
```

File-size guidance: each source file above should stay under ~250 lines. If a task would push a file past that, split it (the structure above already pre-splits the ones most likely to bloat: parsing, Models/, Features).

---

## Task Dependency Overview

```
T1 Scaffolding
      ↓
T2 Core Models ─────────┐
      ↓                 │
T3 Parsers              │
      ↓                 │
T4 SegmentAggregator    │
      ↓                 │
T5 RecentChunker        │
      ↓                 │
T6 AppSettings + Store  │
      ↓                 │
T7 Fixtures ← uses generate-fixtures.sh
      ↓
T8 TeslaCamScanner (needs T3-T5 + fixtures)
      ↓
T9 LibraryStore (integrates Scanner + SettingsStore + RecentChunker)
      ↓
T10 MultiAVPlayer + PlaybackController
      ↓
T11 AVComposer + ExportJob
      ↓
T12 EventList Feature
      ↓
T13 GridPlayer Feature (uses T10)
      ↓
T14 GridConfig + ExportSheet Features (uses T11)
      ↓
T15 Settings + Root + FolderPicker + wire-up
```

Tasks T2–T6 are pure Swift and have no platform dependencies — they can be completed and committed one after another with fast feedback loops. T7 prepares fixtures once; every later task that reads fixtures depends on T7. T10–T11 require real simulator/device runs for AVFoundation behavior verification.

---

## Task 1: Project Scaffolding (CLI-only with xcodegen)

**Files:**
- Create: `project.yml` (xcodegen spec)
- Create: `Makefile` (wraps xcodebuild + xcbeautify for humans and subagents)
- Create: `TeslaCamViewer/App/TeslaCamViewerApp.swift`
- Create: `TeslaCamViewer/Info.plist` (generated by xcodegen from project.yml info properties)
- Create: `TeslaCamViewerTests/SmokeTest.swift`
- Create: `TeslaCamViewerTests/Info.plist` (generated by xcodegen)
- Modify: `.gitignore` — add `TeslaCamViewer.xcodeproj/`
- Generated (by xcodegen, gitignored): `TeslaCamViewer.xcodeproj/`

**Why this task first:** Get `make test` working with a single smoke test so every subsequent task has a working build loop. The whole project is CLI-driven — no Xcode GUI interaction is required for any task in this plan.

- [ ] **Step 1: Write `project.yml`**

Path: `project.yml`

```yaml
name: TeslaCamViewer
options:
  bundleIdPrefix: me.melkor
  deploymentTarget:
    iOS: "17.0"
  developmentLanguage: zh-Hans
  createIntermediateGroups: true
  generateEmptyDirectories: true
settings:
  base:
    SWIFT_VERSION: "5.9"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    ENABLE_USER_SCRIPT_SANDBOXING: NO
    SWIFT_STRICT_CONCURRENCY: complete
targets:
  TeslaCamViewer:
    type: application
    platform: iOS
    sources:
      - path: TeslaCamViewer
    info:
      path: TeslaCamViewer/Info.plist
      properties:
        CFBundleDisplayName: TeslaCamViewer
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        UISupportedInterfaceOrientations~ipad:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationPortraitUpsideDown
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        NSPhotoLibraryAddUsageDescription: "用于把导出的行车记录仪视频保存到相册。"
        NSPhotoLibraryUsageDescription: "用于把导出的行车记录仪视频保存到相册。"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: me.melkor.TeslaCamViewer
        TARGETED_DEVICE_FAMILY: "1,2"
        CODE_SIGN_STYLE: Automatic
  TeslaCamViewerTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: TeslaCamViewerTests
    dependencies:
      - target: TeslaCamViewer
    info:
      path: TeslaCamViewerTests/Info.plist
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: me.melkor.TeslaCamViewerTests
        CODE_SIGN_STYLE: Automatic
        BUNDLE_LOADER: $(TEST_HOST)
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/TeslaCamViewer.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/TeslaCamViewer
schemes:
  TeslaCamViewer:
    build:
      targets:
        TeslaCamViewer: all
        TeslaCamViewerTests: [test]
    test:
      targets:
        - TeslaCamViewerTests
      gatherCoverageData: true
      coverageTargets:
        - TeslaCamViewer
    run:
      config: Debug
    archive:
      config: Release
```

- [ ] **Step 2: Write the `Makefile`**

Path: `Makefile`

```makefile
# TeslaCamViewer — CLI build harness.
# Run `make help` for the menu.

SCHEME         := TeslaCamViewer
PROJECT        := TeslaCamViewer.xcodeproj
SIMULATOR      := iPhone 17
DESTINATION    := platform=iOS Simulator,name=$(SIMULATOR),OS=latest
DERIVED_DATA   := build
XCBEAUTIFY     := xcbeautify --renderer terminal

# Tell xcodebuild to be quiet about meta-output; xcbeautify formats the rest.
XCODEBUILD_FLAGS := -project $(PROJECT) -scheme $(SCHEME) \
    -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) \
    COMPILER_INDEX_STORE_ENABLE=NO

.PHONY: help
help:
	@echo "Targets:"
	@echo "  generate   regenerate Xcode project from project.yml"
	@echo "  build      build for the configured simulator"
	@echo "  test       run the full test suite"
	@echo "  test-only TESTS=Class[/method]   run a subset"
	@echo "  clean      remove build/ and DerivedData"
	@echo "  boot       boot the default simulator"
	@echo "  install    install the built .app onto the booted simulator"
	@echo "  launch     launch the installed app on the booted simulator"
	@echo "  run        build + install + launch (end-to-end on simulator)"

.PHONY: generate
generate:
	xcodegen generate

# `generate` is cheap and idempotent; make every build step depend on it so
# that adding a new .swift file never requires you to remember to regen.
$(PROJECT): project.yml
	xcodegen generate

.PHONY: build
build: $(PROJECT)
	set -o pipefail && xcodebuild $(XCODEBUILD_FLAGS) build | $(XCBEAUTIFY)

.PHONY: test
test: $(PROJECT)
	set -o pipefail && xcodebuild $(XCODEBUILD_FLAGS) test | $(XCBEAUTIFY)

# Usage: make test-only TESTS=CameraAngleTests
# Or:    make test-only TESTS=CameraAngleTests/test_fileSuffix_mapsEachAngleToTeslaNaming
.PHONY: test-only
test-only: $(PROJECT)
	@if [ -z "$(TESTS)" ]; then echo "Set TESTS=Class or TESTS=Class/method"; exit 1; fi
	set -o pipefail && xcodebuild $(XCODEBUILD_FLAGS) \
	    -only-testing:TeslaCamViewerTests/$(TESTS) test | $(XCBEAUTIFY)

.PHONY: clean
clean:
	rm -rf $(DERIVED_DATA)

.PHONY: boot
boot:
	-xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	open -a Simulator

.PHONY: install
install: build boot
	xcrun simctl install booted $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(SCHEME).app

.PHONY: launch
launch:
	xcrun simctl launch --console-pty booted me.melkor.$(SCHEME)

.PHONY: run
run: install launch
```

- [ ] **Step 3: Write `.gitignore` additions (append to existing)**

Path: `.gitignore` (the file already exists with `build/`, `DerivedData/`, etc. — add the xcodegen output):

```bash
# Append to .gitignore (preserve existing contents)
cat >> .gitignore <<'EOF'

# xcodegen-generated — regenerate with `make generate`
TeslaCamViewer.xcodeproj/
EOF
```

- [ ] **Step 4: Create the app entry point**

Path: `TeslaCamViewer/App/TeslaCamViewerApp.swift`

```swift
import SwiftUI

@main
struct TeslaCamViewerApp: App {
    var body: some Scene {
        WindowGroup {
            Text("TeslaCamViewer")
        }
    }
}
```

- [ ] **Step 5: Create the stub test**

Path: `TeslaCamViewerTests/SmokeTest.swift`

```swift
import XCTest

final class SmokeTest: XCTestCase {
    func test_project_compiles() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

- [ ] **Step 6: Generate the Xcode project**

```bash
cd /Users/shanehou/Developer/Projects/TeslaCamViewer
make generate
```

Expected stdout (last line): `Created project at <path>/TeslaCamViewer.xcodeproj`.

Expected filesystem: `TeslaCamViewer.xcodeproj/` now exists and is listed in `.gitignore`.

- [ ] **Step 7: Run tests**

```bash
make test
```

Expected last lines (xcbeautify output):
```
    Executed 1 test, with 0 failures (0 unexpected) in 0.001 (...) seconds
Test Succeeded
```

If you instead see something like `Unable to find a device matching the provided destination`, list simulators with `xcrun simctl list devices available | grep iPhone` and adjust `SIMULATOR := iPhone 17` in the `Makefile` to an available device.

- [ ] **Step 8: Commit**

```bash
git add project.yml Makefile .gitignore TeslaCamViewer/ TeslaCamViewerTests/
git commit -m "chore: bootstrap xcodegen-driven project with smoke test"
```

---

## Task 2: Core Data Models (pure types)

**Dependencies:** T1

**Files:**
- Create: `TeslaCamViewer/Domain/Models/CameraAngle.swift`
- Create: `TeslaCamViewer/Domain/Models/EventType.swift`
- Create: `TeslaCamViewer/Domain/Models/MinuteSegment.swift`
- Create: `TeslaCamViewer/Domain/Models/EventMetadata.swift`
- Create: `TeslaCamViewer/Domain/Models/TeslaEvent.swift`
- Create: `TeslaCamViewer/Domain/Models/TrimRange.swift`
- Create: `TeslaCamViewer/Domain/Models/ExportRequest.swift`
- Create: `TeslaCamViewer/Domain/Models/AppSettings.swift`
- Create: `TeslaCamViewer/Domain/Models/AppError.swift`
- Test: `TeslaCamViewerTests/Unit/CameraAngleTests.swift`
- Test: `TeslaCamViewerTests/Unit/TeslaEventTests.swift`
- Test: `TeslaCamViewerTests/Unit/TrimRangeTests.swift`
- Test: `TeslaCamViewerTests/Unit/AppSettingsTests.swift`
- Test: `TeslaCamViewerTests/Unit/AppErrorTests.swift`

**Rule:** Each file, one type. No file over 80 lines.

### 2a. `CameraAngle`

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Unit/CameraAngleTests.swift`

```swift
import XCTest
@testable import TeslaCamViewer

final class CameraAngleTests: XCTestCase {

    func test_fileSuffix_mapsEachAngleToTeslaNaming() {
        XCTAssertEqual(CameraAngle.front.fileSuffix, "front")
        XCTAssertEqual(CameraAngle.back.fileSuffix, "back")
        XCTAssertEqual(CameraAngle.leftRepeater.fileSuffix, "left_repeater")
        XCTAssertEqual(CameraAngle.rightRepeater.fileSuffix, "right_repeater")
        XCTAssertEqual(CameraAngle.leftPillar.fileSuffix, "left_pillar")
        XCTAssertEqual(CameraAngle.rightPillar.fileSuffix, "right_pillar")
    }

    func test_defaultGrid_isFrontBackAndTwoRepeaters() {
        XCTAssertEqual(
            CameraAngle.defaultGrid,
            [.front, .back, .leftRepeater, .rightRepeater]
        )
    }

    func test_fromFileSuffix_matchesAllCases() {
        for angle in CameraAngle.allCases {
            XCTAssertEqual(CameraAngle(fileSuffix: angle.fileSuffix), angle)
        }
    }

    func test_fromFileSuffix_returnsNilOnUnknown() {
        XCTAssertNil(CameraAngle(fileSuffix: "trunk"))
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
make test-only TESTS=CameraAngleTests 2>&1 | tail -15
```

Expected: compile error `cannot find 'CameraAngle' in scope`.

- [ ] **Step 3: Implement**

Path: `TeslaCamViewer/Domain/Models/CameraAngle.swift`

```swift
import Foundation

public enum CameraAngle: String, CaseIterable, Codable, Hashable {
    case front
    case back
    case leftRepeater
    case rightRepeater
    case leftPillar
    case rightPillar

    /// Suffix Tesla uses in the MP4 filename, e.g. "2024-07-15_14-32-01-**front**.mp4".
    public var fileSuffix: String {
        switch self {
        case .front:          return "front"
        case .back:           return "back"
        case .leftRepeater:   return "left_repeater"
        case .rightRepeater:  return "right_repeater"
        case .leftPillar:     return "left_pillar"
        case .rightPillar:    return "right_pillar"
        }
    }

    public init?(fileSuffix: String) {
        guard let match = CameraAngle.allCases.first(where: { $0.fileSuffix == fileSuffix })
        else { return nil }
        self = match
    }

    /// The 4 angles pre-selected for the default grid when a user opens an event.
    public static let defaultGrid: [CameraAngle] = [
        .front, .back, .leftRepeater, .rightRepeater
    ]
}
```

- [ ] **Step 4: Run — expect pass**

Same `xcodebuild` command as Step 2. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(domain): add CameraAngle enum with Tesla filename mapping"
```

### 2b. `EventType`, `EventMetadata`, `MinuteSegment`

- [ ] **Step 1: Write failing tests**

Append to `TeslaCamViewerTests/Unit/TeslaEventTests.swift`:

```swift
import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class TeslaEventTests: XCTestCase {

    func test_minuteSegment_exposesFilesByAngle() {
        let ts = Date(timeIntervalSince1970: 1_721_050_321)
        let url = URL(fileURLWithPath: "/tmp/front.mp4")
        let seg = MinuteSegment(
            timestamp: ts,
            duration: CMTime(seconds: 60, preferredTimescale: 600),
            filesByAngle: [.front: url]
        )
        XCTAssertEqual(seg.filesByAngle[.front], url)
        XCTAssertNil(seg.filesByAngle[.back])
    }

    func test_eventMetadata_decodesFromTeslaEventJSON() throws {
        let json = #"""
        {"timestamp":"2024-07-15T14:32:01","city":"Mountain View","reason":"sentry_aware_object_detection"}
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithOptionalFractionalSeconds
        let meta = try decoder.decode(EventMetadata.self, from: json)
        XCTAssertEqual(meta.city, "Mountain View")
        XCTAssertEqual(meta.reason, "sentry_aware_object_detection")
        XCTAssertNotNil(meta.timestamp)
    }

    func test_totalDuration_sumsAllSegmentDurations() {
        let event = TeslaEvent.fixture(
            segments: [
                .fixture(offsetSeconds: 0,   durationSeconds: 60),
                .fixture(offsetSeconds: 60,  durationSeconds: 60),
                .fixture(offsetSeconds: 120, durationSeconds: 45)
            ]
        )
        XCTAssertEqual(event.totalDuration.seconds, 165, accuracy: 0.001)
    }

    func test_availableAngles_isUnionAcrossSegments() {
        let event = TeslaEvent.fixture(
            segments: [
                .fixture(angles: [.front, .back]),
                .fixture(angles: [.front, .leftRepeater])
            ]
        )
        XCTAssertEqual(event.availableAngles, [.front, .back, .leftRepeater])
    }
}
```

Also create helper `TeslaEvent+Fixture.swift` under `TeslaCamViewerTests/Unit/Helpers/`:

```swift
import Foundation
import CoreMedia
@testable import TeslaCamViewer

extension TeslaEvent {
    static func fixture(
        id: String = "fix-1",
        type: EventType = .saved,
        startTime: Date = Date(timeIntervalSince1970: 1_721_050_321),
        segments: [MinuteSegment],
        thumbnailURL: URL? = nil,
        eventMetadata: EventMetadata? = nil
    ) -> TeslaEvent {
        TeslaEvent(
            id: id,
            type: type,
            startTime: startTime,
            segments: segments,
            availableAngles: Set(segments.flatMap { $0.filesByAngle.keys }),
            thumbnailURL: thumbnailURL,
            eventMetadata: eventMetadata
        )
    }
}

extension MinuteSegment {
    static func fixture(
        offsetSeconds: Double = 0,
        durationSeconds: Double = 60,
        angles: [CameraAngle] = [.front, .back, .leftRepeater, .rightRepeater]
    ) -> MinuteSegment {
        let base = Date(timeIntervalSince1970: 1_721_050_321)
        let files = Dictionary(uniqueKeysWithValues: angles.map {
            ($0, URL(fileURLWithPath: "/tmp/\(Int(offsetSeconds))-\($0.fileSuffix).mp4"))
        })
        return MinuteSegment(
            timestamp: base.addingTimeInterval(offsetSeconds),
            duration: CMTime(seconds: durationSeconds, preferredTimescale: 600),
            filesByAngle: files
        )
    }
}
```

And a Foundation extension for `DateDecodingStrategy` (Tesla's `event.json` timestamps don't have fractional seconds):

Path: `TeslaCamViewerTests/Unit/Helpers/JSONDecoder+Tesla.swift`

```swift
import Foundation

extension JSONDecoder.DateDecodingStrategy {
    static let iso8601WithOptionalFractionalSeconds: Self = .custom { decoder in
        let str = try decoder.singleValueContainer().decode(String.self)
        let formatters: [ISO8601DateFormatter] = {
            let full = ISO8601DateFormatter()
            full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let compact = ISO8601DateFormatter()
            compact.formatOptions = [.withInternetDateTime]
            let localFull = DateFormatter()
            localFull.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            localFull.timeZone = TimeZone(secondsFromGMT: 0)
            // DateFormatter doesn't conform to ISO8601DateFormatter; fall through on nil
            _ = localFull
            return [full, compact]
        }()
        for f in formatters {
            if let d = f.date(from: str) { return d }
        }
        // Fallback: naive "yyyy-MM-dd'T'HH:mm:ss" (no tz)
        let local = DateFormatter()
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        local.timeZone = TimeZone(secondsFromGMT: 0)
        if let d = local.date(from: str) { return d }
        throw DecodingError.dataCorruptedError(
            in: try decoder.singleValueContainer(),
            debugDescription: "Unrecognized date string: \(str)"
        )
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
make test-only TESTS=TeslaEventTests 2>&1 | tail -15
```

Expected: `cannot find 'MinuteSegment'`, etc.

- [ ] **Step 3: Implement models**

Path: `TeslaCamViewer/Domain/Models/EventType.swift`

```swift
public enum EventType: String, Codable, CaseIterable {
    case saved
    case sentry
    case recent
}
```

Path: `TeslaCamViewer/Domain/Models/EventMetadata.swift`

```swift
import Foundation

public struct EventMetadata: Codable, Equatable {
    public let timestamp: Date?
    public let city: String?
    public let reason: String?

    public init(timestamp: Date?, city: String?, reason: String?) {
        self.timestamp = timestamp
        self.city = city
        self.reason = reason
    }
}
```

Path: `TeslaCamViewer/Domain/Models/MinuteSegment.swift`

```swift
import Foundation
import CoreMedia

public struct MinuteSegment: Equatable {
    public let timestamp: Date
    public let duration: CMTime
    public let filesByAngle: [CameraAngle: URL]

    public init(timestamp: Date, duration: CMTime, filesByAngle: [CameraAngle: URL]) {
        self.timestamp = timestamp
        self.duration = duration
        self.filesByAngle = filesByAngle
    }
}
```

Path: `TeslaCamViewer/Domain/Models/TeslaEvent.swift`

```swift
import Foundation
import CoreMedia

public struct TeslaEvent: Identifiable, Equatable {
    public let id: String
    public let type: EventType
    public let startTime: Date
    public let segments: [MinuteSegment]
    public let availableAngles: Set<CameraAngle>
    public let thumbnailURL: URL?
    public let eventMetadata: EventMetadata?

    public init(
        id: String,
        type: EventType,
        startTime: Date,
        segments: [MinuteSegment],
        availableAngles: Set<CameraAngle>,
        thumbnailURL: URL?,
        eventMetadata: EventMetadata?
    ) {
        self.id = id
        self.type = type
        self.startTime = startTime
        self.segments = segments
        self.availableAngles = availableAngles
        self.thumbnailURL = thumbnailURL
        self.eventMetadata = eventMetadata
    }

    public var totalDuration: CMTime {
        segments.reduce(CMTime.zero) { acc, seg in acc + seg.duration }
    }
}
```

- [ ] **Step 4: Run — expect pass**

Same as Step 2. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(domain): add EventType, MinuteSegment, TeslaEvent, EventMetadata"
```

### 2c. `TrimRange`

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Unit/TrimRangeTests.swift`

```swift
import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class TrimRangeTests: XCTestCase {

    func test_init_clampsAndOrdersWithinBounds() {
        let total = CMTime(seconds: 180, preferredTimescale: 600)
        let r = TrimRange(
            start: .init(seconds: -5, preferredTimescale: 600),
            end: .init(seconds: 200, preferredTimescale: 600),
            totalDuration: total
        )
        XCTAssertEqual(r.start.seconds, 0, accuracy: 0.001)
        XCTAssertEqual(r.end.seconds, 180, accuracy: 0.001)
    }

    func test_init_whenStartExceedsEnd_swapsThem() {
        let total = CMTime(seconds: 120, preferredTimescale: 600)
        let r = TrimRange(
            start: .init(seconds: 80, preferredTimescale: 600),
            end: .init(seconds: 10, preferredTimescale: 600),
            totalDuration: total
        )
        XCTAssertEqual(r.start.seconds, 10, accuracy: 0.001)
        XCTAssertEqual(r.end.seconds, 80, accuracy: 0.001)
    }

    func test_init_whenCollapsed_leavesOneSecondOfRange() {
        let total = CMTime(seconds: 60, preferredTimescale: 600)
        let r = TrimRange(
            start: .init(seconds: 30, preferredTimescale: 600),
            end: .init(seconds: 30, preferredTimescale: 600),
            totalDuration: total
        )
        XCTAssertEqual((r.end - r.start).seconds, 1, accuracy: 0.001)
    }

    func test_fullRange_spansZeroToTotalDuration() {
        let total = CMTime(seconds: 120, preferredTimescale: 600)
        let r = TrimRange.fullRange(totalDuration: total)
        XCTAssertEqual(r.start, .zero)
        XCTAssertEqual(r.end, total)
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
make test-only TESTS=TrimRangeTests 2>&1 | tail -15
```

- [ ] **Step 3: Implement**

Path: `TeslaCamViewer/Domain/Models/TrimRange.swift`

```swift
import Foundation
import CoreMedia

public struct TrimRange: Equatable {
    public let start: CMTime
    public let end: CMTime

    /// Clamps both ends into `[.zero, totalDuration]`, orders them,
    /// and ensures a minimum range of 1s if both collapsed to the same value.
    public init(start: CMTime, end: CMTime, totalDuration: CMTime) {
        let minVal = CMTime.zero
        let maxVal = totalDuration
        var s = max(minVal, min(maxVal, start))
        var e = max(minVal, min(maxVal, end))
        if s > e { swap(&s, &e) }
        if s == e {
            let oneSec = CMTime(seconds: 1, preferredTimescale: 600)
            if e + oneSec <= maxVal {
                e = e + oneSec
            } else if s - oneSec >= minVal {
                s = s - oneSec
            }
        }
        self.start = s
        self.end = e
    }

    public static func fullRange(totalDuration: CMTime) -> TrimRange {
        TrimRange(start: .zero, end: totalDuration, totalDuration: totalDuration)
    }

    public var duration: CMTime { end - start }
}
```

- [ ] **Step 4: Run — expect pass**

Same command. Expected `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(domain): add TrimRange with clamping invariants"
```

### 2d. `ExportRequest`

- [ ] **Step 1: Write failing test**

Path: extend `TeslaCamViewerTests/Unit/TrimRangeTests.swift` or create `TeslaCamViewerTests/Unit/ExportRequestTests.swift`:

```swift
import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class ExportRequestTests: XCTestCase {

    func test_gridLayout_requiresExactlyFourAngles() {
        let ok = ExportRequest.Layout.gridCombined(angles: [.front, .back, .leftRepeater, .rightRepeater])
        XCTAssertTrue(ok.isValid)

        let tooFew = ExportRequest.Layout.gridCombined(angles: [.front, .back])
        XCTAssertFalse(tooFew.isValid)
    }

    func test_singlesLayout_requiresAtLeastOneAngle() {
        XCTAssertFalse(ExportRequest.Layout.singlesPerAngle(angles: []).isValid)
        XCTAssertTrue(ExportRequest.Layout.singlesPerAngle(angles: [.front]).isValid)
    }

    func test_watermarkPosition_codable_roundtrip() throws {
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        for pos in ExportRequest.WatermarkPosition.allCases {
            let data = try enc.encode(pos)
            let back = try dec.decode(ExportRequest.WatermarkPosition.self, from: data)
            XCTAssertEqual(pos, back)
        }
    }
}
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement**

Path: `TeslaCamViewer/Domain/Models/ExportRequest.swift`

```swift
import Foundation
import CoreMedia

public struct ExportRequest {
    public enum Layout: Equatable {
        case singlesPerAngle(angles: [CameraAngle])
        case gridCombined(angles: [CameraAngle])

        public var isValid: Bool {
            switch self {
            case .singlesPerAngle(let angles): return !angles.isEmpty
            case .gridCombined(let angles):    return angles.count == 4
            }
        }

        public var angles: [CameraAngle] {
            switch self {
            case .singlesPerAngle(let a), .gridCombined(let a): return a
            }
        }
    }

    public enum WatermarkPosition: String, Codable, CaseIterable, Equatable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    public let event: TeslaEvent
    public let layout: Layout
    public let range: TrimRange
    public let watermarkPosition: WatermarkPosition

    public init(event: TeslaEvent, layout: Layout, range: TrimRange, watermarkPosition: WatermarkPosition) {
        self.event = event
        self.layout = layout
        self.range = range
        self.watermarkPosition = watermarkPosition
    }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(domain): add ExportRequest with Layout/WatermarkPosition"
```

### 2e. `AppSettings`

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Unit/AppSettingsTests.swift`

```swift
import XCTest
@testable import TeslaCamViewer

final class AppSettingsTests: XCTestCase {

    func test_defaults_matchSpec() {
        let s = AppSettings()
        XCTAssertEqual(s.recentGapThresholdSeconds, 300)        // 5 minutes
        XCTAssertEqual(s.defaultWatermarkPosition, .bottomLeft)
    }

    func test_codable_roundtrip() throws {
        let s = AppSettings(recentGapThresholdSeconds: 900, defaultWatermarkPosition: .topRight)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(back.recentGapThresholdSeconds, 900)
        XCTAssertEqual(back.defaultWatermarkPosition, .topRight)
    }

    func test_clampsRecentGapOnInit() {
        let tooLow  = AppSettings(recentGapThresholdSeconds: 10,   defaultWatermarkPosition: .bottomLeft)
        let tooHigh = AppSettings(recentGapThresholdSeconds: 9_999, defaultWatermarkPosition: .bottomLeft)
        XCTAssertEqual(tooLow.recentGapThresholdSeconds,  AppSettings.minRecentGapSeconds)
        XCTAssertEqual(tooHigh.recentGapThresholdSeconds, AppSettings.maxRecentGapSeconds)
    }
}
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement**

Path: `TeslaCamViewer/Domain/Models/AppSettings.swift`

```swift
import Foundation

public struct AppSettings: Codable, Equatable {
    public static let minRecentGapSeconds = 60        // 1 minute (matches spec slider min)
    public static let maxRecentGapSeconds = 1_800     // 30 minutes

    public var recentGapThresholdSeconds: Int
    public var defaultWatermarkPosition: ExportRequest.WatermarkPosition

    public init(
        recentGapThresholdSeconds: Int = 300,
        defaultWatermarkPosition: ExportRequest.WatermarkPosition = .bottomLeft
    ) {
        self.recentGapThresholdSeconds = max(
            Self.minRecentGapSeconds,
            min(Self.maxRecentGapSeconds, recentGapThresholdSeconds)
        )
        self.defaultWatermarkPosition = defaultWatermarkPosition
    }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(domain): add AppSettings with clamping on init"
```

### 2f. `AppError`

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Unit/AppErrorTests.swift`

```swift
import XCTest
@testable import TeslaCamViewer

final class AppErrorTests: XCTestCase {

    func test_notTeslaCamFolder_hasDescription() {
        let e: AppError = .notTeslaCamFolder
        XCTAssertNotNil(e.errorDescription)
        XCTAssertTrue(e.errorDescription!.contains("TeslaCam"))
    }

    func test_diskSpaceInsufficient_describesBytes() {
        let e: AppError = .diskSpaceInsufficient(neededBytes: 5_000_000_000, availableBytes: 1_000_000_000)
        let desc = e.errorDescription ?? ""
        XCTAssertTrue(desc.contains("5"))      // needed
        XCTAssertTrue(desc.contains("1"))      // available
    }

    func test_eventCorrupted_embedsUnderlyingMessage() {
        struct DummyError: Error, LocalizedError { var errorDescription: String? { "bad json" } }
        let e: AppError = .eventCorrupted(id: "2024-07-15_14-32-01", underlying: DummyError())
        let desc = e.errorDescription ?? ""
        XCTAssertTrue(desc.contains("2024-07-15"))
    }
}
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement**

Path: `TeslaCamViewer/Domain/Models/AppError.swift`

```swift
import Foundation

public enum AppError: LocalizedError, Equatable {
    case notTeslaCamFolder
    case bookmarkStale
    case photoLibraryDenied
    case diskSpaceInsufficient(neededBytes: Int64, availableBytes: Int64)
    case eventCorrupted(id: String, underlying: Error)
    case exportFailed(underlying: Error)
    case memoryPressure

    public var errorDescription: String? {
        switch self {
        case .notTeslaCamFolder:
            return "在选中的文件夹里没找到 TeslaCam 结构（RecentClips / SavedClips / SentryClips）。请重新选择 U 盘根目录或 TeslaCam 文件夹。"
        case .bookmarkStale:
            return "上次选中的文件夹已不可用，请重新选择 TeslaCam 文件夹。"
        case .photoLibraryDenied:
            return "相册权限未授予。导出文件将仅通过分享面板保存。"
        case .diskSpaceInsufficient(let need, let have):
            // SI GB (1e9 bytes) to match the test's digit assertions and common
            // disk-space UI conventions.
            let gbNeed = Double(need) / 1_000_000_000
            let gbHave = Double(have) / 1_000_000_000
            return String(format: "磁盘空间不足：需要约 %.1f GB，可用 %.1f GB。", gbNeed, gbHave)
        case .eventCorrupted(let id, let err):
            return "事件 \(id) 已损坏，已跳过：\(err.localizedDescription)"
        case .exportFailed(let err):
            return "导出失败：\(err.localizedDescription)"
        case .memoryPressure:
            return "内存不足，已暂停播放。"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notTeslaCamFolder, .bookmarkStale:
            return "点击下方按钮重新选择 TeslaCam 文件夹。"
        case .photoLibraryDenied:
            return "前往「设置 → 隐私 → 照片」授予 TeslaCamViewer 访问权限。"
        default:
            return nil
        }
    }

    public static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.notTeslaCamFolder, .notTeslaCamFolder),
             (.bookmarkStale, .bookmarkStale),
             (.photoLibraryDenied, .photoLibraryDenied),
             (.memoryPressure, .memoryPressure):
            return true
        case let (.diskSpaceInsufficient(a, b), .diskSpaceInsufficient(c, d)):
            return a == c && b == d
        case let (.eventCorrupted(a, _), .eventCorrupted(b, _)):
            return a == b
        case (.exportFailed, .exportFailed):
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(domain): add AppError with localized Chinese descriptions"
```

---

## Task 3: Parsers

**Dependencies:** T2

**Files:**
- Create: `TeslaCamViewer/Domain/Parsing/FilenameParser.swift`
- Create: `TeslaCamViewer/Domain/Parsing/FolderNameParser.swift`
- Test: `TeslaCamViewerTests/Unit/FilenameParserTests.swift`
- Test: `TeslaCamViewerTests/Unit/FolderNameParserTests.swift`

### 3a. `FolderNameParser`

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Unit/FolderNameParserTests.swift`

```swift
import XCTest
@testable import TeslaCamViewer

final class FolderNameParserTests: XCTestCase {

    func test_parses_validFolderName() {
        let result = FolderNameParser.parse("2024-07-15_14-32-01")
        XCTAssertNotNil(result)
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: result!)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 7)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 32)
        XCTAssertEqual(comps.second, 1)
    }

    func test_rejects_extraCharacters() {
        XCTAssertNil(FolderNameParser.parse("2024-07-15_14-32-01 copy"))
    }

    func test_rejects_wrongSeparators() {
        XCTAssertNil(FolderNameParser.parse("2024-07-15 14:32:01"))
    }

    func test_rejects_unixHiddenFolder() {
        XCTAssertNil(FolderNameParser.parse(".DS_Store"))
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
make test-only TESTS=FolderNameParserTests 2>&1 | tail -10
```

- [ ] **Step 3: Implement**

Path: `TeslaCamViewer/Domain/Parsing/FolderNameParser.swift`

```swift
import Foundation

public enum FolderNameParser {
    /// Parses a Tesla event folder name `"YYYY-MM-DD_HH-MM-SS"` into a UTC-anchored `Date`.
    /// Returns nil for anything else (hidden folders, names with extra characters, etc.).
    public static func parse(_ name: String) -> Date? {
        // Tesla folder names are purely ASCII digits + '-' + '_' and always 19 chars.
        guard name.count == 19 else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: name)
    }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(parse): add FolderNameParser"
```

### 3b. `FilenameParser`

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Unit/FilenameParserTests.swift`

```swift
import XCTest
@testable import TeslaCamViewer

final class FilenameParserTests: XCTestCase {

    func test_parses_allKnownAngles() {
        let cases: [(String, CameraAngle)] = [
            ("2024-07-15_14-32-01-front.mp4",          .front),
            ("2024-07-15_14-32-01-back.mp4",           .back),
            ("2024-07-15_14-32-01-left_repeater.mp4",  .leftRepeater),
            ("2024-07-15_14-32-01-right_repeater.mp4", .rightRepeater),
            ("2024-07-15_14-32-01-left_pillar.mp4",    .leftPillar),
            ("2024-07-15_14-32-01-right_pillar.mp4",   .rightPillar),
        ]
        for (name, expectedAngle) in cases {
            let parsed = FilenameParser.parse(name)
            XCTAssertNotNil(parsed, "failed for \(name)")
            XCTAssertEqual(parsed?.angle, expectedAngle)
        }
    }

    func test_timestamp_matchesUTC() {
        let parsed = FilenameParser.parse("2024-07-15_14-32-01-front.mp4")!
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: parsed.timestamp)
        XCTAssertEqual(comps.minute, 32)
        XCTAssertEqual(comps.second, 1)
    }

    func test_rejects_nonMp4() {
        XCTAssertNil(FilenameParser.parse("2024-07-15_14-32-01-front.mov"))
    }

    func test_rejects_unknownAngle() {
        XCTAssertNil(FilenameParser.parse("2024-07-15_14-32-01-trunk.mp4"))
    }

    func test_rejects_malformed() {
        XCTAssertNil(FilenameParser.parse("front.mp4"))
        XCTAssertNil(FilenameParser.parse("random.mp4"))
        XCTAssertNil(FilenameParser.parse("thumb.png"))
    }
}
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement**

Path: `TeslaCamViewer/Domain/Parsing/FilenameParser.swift`

```swift
import Foundation

public enum FilenameParser {
    public struct ParsedFile: Equatable {
        public let timestamp: Date
        public let angle: CameraAngle
    }

    /// Parses `"YYYY-MM-DD_HH-MM-SS-{angle}.mp4"`. Returns nil for anything else.
    public static func parse(_ filename: String) -> ParsedFile? {
        // Require `.mp4` suffix.
        guard filename.hasSuffix(".mp4") else { return nil }
        let base = String(filename.dropLast(4))   // strip ".mp4"

        // Minimum length for "YYYY-MM-DD_HH-MM-SS-X" = 21
        guard base.count > 20 else { return nil }

        // Timestamp is first 19 chars, expected "YYYY-MM-DD_HH-MM-SS"
        let tsPart = String(base.prefix(19))
        guard base.dropFirst(19).first == "-" else { return nil }
        let anglePart = String(base.dropFirst(20))   // after timestamp '-'
        guard let angle = CameraAngle(fileSuffix: anglePart) else { return nil }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let ts = f.date(from: tsPart) else { return nil }
        return ParsedFile(timestamp: ts, angle: angle)
    }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(parse): add FilenameParser"
```

---

## Task 4: SegmentAggregator

**Dependencies:** T3

**Files:**
- Create: `TeslaCamViewer/Domain/Parsing/SegmentAggregator.swift`
- Test: `TeslaCamViewerTests/Unit/SegmentAggregatorTests.swift`

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Unit/SegmentAggregatorTests.swift`

```swift
import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class SegmentAggregatorTests: XCTestCase {

    func test_groupsSameTimestampAcrossAngles() {
        let base = Date(timeIntervalSince1970: 1_721_050_321)
        let urls = [
            url("2024-07-15_14-32-01-front.mp4"),
            url("2024-07-15_14-32-01-back.mp4"),
            url("2024-07-15_14-32-01-left_repeater.mp4"),
            url("2024-07-15_14-32-01-right_repeater.mp4"),
            url("2024-07-15_14-33-01-front.mp4"),
            url("2024-07-15_14-33-01-back.mp4"),
        ]
        let segments = SegmentAggregator.aggregate(
            urls: urls,
            defaultSegmentDuration: CMTime(seconds: 60, preferredTimescale: 600)
        )
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].filesByAngle.count, 4)
        XCTAssertEqual(segments[1].filesByAngle.count, 2)
        XCTAssertEqual(segments[0].timestamp, segments[0].timestamp)   // sanity
        XCTAssertLessThan(segments[0].timestamp, segments[1].timestamp)
        _ = base
    }

    func test_skipsUnparseableFiles() {
        let urls = [
            url("2024-07-15_14-32-01-front.mp4"),
            url("thumb.png"),
            url("event.json"),
            url(".DS_Store"),
            url("random.mp4"),
        ]
        let segments = SegmentAggregator.aggregate(
            urls: urls,
            defaultSegmentDuration: CMTime(seconds: 60, preferredTimescale: 600)
        )
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].filesByAngle.count, 1)
        XCTAssertEqual(segments[0].filesByAngle.keys.first, .front)
    }

    func test_resultIsSortedByTimestamp() {
        let urls = [
            url("2024-07-15_14-34-01-front.mp4"),
            url("2024-07-15_14-32-01-front.mp4"),
            url("2024-07-15_14-33-01-front.mp4"),
        ]
        let segments = SegmentAggregator.aggregate(
            urls: urls,
            defaultSegmentDuration: CMTime(seconds: 60, preferredTimescale: 600)
        )
        XCTAssertEqual(segments.map { $0.timestamp }, segments.map { $0.timestamp }.sorted())
    }

    func test_emptyInput_returnsEmpty() {
        XCTAssertTrue(SegmentAggregator.aggregate(urls: [], defaultSegmentDuration: .zero).isEmpty)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/fake/\(name)")
    }
}
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement**

Path: `TeslaCamViewer/Domain/Parsing/SegmentAggregator.swift`

```swift
import Foundation
import CoreMedia

public enum SegmentAggregator {
    /// Groups a list of file URLs by timestamp into MinuteSegments.
    /// `defaultSegmentDuration` is used as a placeholder duration; the Scanner
    /// may replace it with the actual asset duration once it probes AVAssets.
    public static func aggregate(
        urls: [URL],
        defaultSegmentDuration: CMTime
    ) -> [MinuteSegment] {
        var byTimestamp: [Date: [CameraAngle: URL]] = [:]
        for url in urls {
            guard let parsed = FilenameParser.parse(url.lastPathComponent) else { continue }
            byTimestamp[parsed.timestamp, default: [:]][parsed.angle] = url
        }
        return byTimestamp
            .sorted { $0.key < $1.key }
            .map { (timestamp, files) in
                MinuteSegment(timestamp: timestamp, duration: defaultSegmentDuration, filesByAngle: files)
            }
    }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(parse): add SegmentAggregator"
```

---

## Task 5: RecentChunker

**Dependencies:** T4

**Files:**
- Create: `TeslaCamViewer/Domain/RecentChunker.swift`
- Test: `TeslaCamViewerTests/Unit/RecentChunkerTests.swift`

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Unit/RecentChunkerTests.swift`

```swift
import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class RecentChunkerTests: XCTestCase {

    func test_continuousSegments_yieldOneChunk() {
        let segments = makeSegments(startOffsetsMinutes: [0, 1, 2, 3, 4])
        let chunks = RecentChunker.chunk(segments: segments, gapThresholdSeconds: 300)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 5)
    }

    func test_gapExceedsThreshold_splits() {
        // 3 segments, then a 10-minute gap, then 2 more
        let segments = makeSegments(startOffsetsMinutes: [0, 1, 2, 12, 13])
        let chunks = RecentChunker.chunk(segments: segments, gapThresholdSeconds: 300)   // 5 min
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 3)
        XCTAssertEqual(chunks[1].count, 2)
    }

    func test_wideThreshold_mergesBack() {
        let segments = makeSegments(startOffsetsMinutes: [0, 1, 2, 12, 13])
        let chunks = RecentChunker.chunk(segments: segments, gapThresholdSeconds: 1_800)  // 30 min
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 5)
    }

    func test_gapEqualsThreshold_belongsToFirstChunk() {
        // gap of exactly 300s (5 min) = boundary: ≤ threshold → same chunk
        let segments = makeSegments(startOffsetsMinutes: [0, 1, 2, 7])
        // between seg[2].timestamp+60s and seg[3].timestamp: (7-2)*60 = 300s; seg duration 60s
        // gap = start(seg3) - end(seg2) = 7*60 - (2*60+60) = 420 - 180 = 240s  (well under threshold)
        // Reframe: between end-of-last-seg and start-of-next-seg.
        let chunks = RecentChunker.chunk(segments: segments, gapThresholdSeconds: 240)
        XCTAssertEqual(chunks.count, 1)
    }

    func test_gapJustOverThreshold_splits() {
        let segments = makeSegments(startOffsetsMinutes: [0, 1, 2, 7])
        // gap 240s; threshold 239 → splits
        let chunks = RecentChunker.chunk(segments: segments, gapThresholdSeconds: 239)
        XCTAssertEqual(chunks.count, 2)
    }

    func test_emptyInput_returnsEmpty() {
        XCTAssertTrue(RecentChunker.chunk(segments: [], gapThresholdSeconds: 300).isEmpty)
    }

    func test_singleSegment_isOwnChunk() {
        let segments = makeSegments(startOffsetsMinutes: [0])
        XCTAssertEqual(RecentChunker.chunk(segments: segments, gapThresholdSeconds: 300).count, 1)
    }

    // MARK: helpers

    private func makeSegments(startOffsetsMinutes offsets: [Int]) -> [MinuteSegment] {
        let base = Date(timeIntervalSince1970: 1_721_050_321)
        return offsets.map { mins in
            MinuteSegment(
                timestamp: base.addingTimeInterval(TimeInterval(mins * 60)),
                duration: CMTime(seconds: 60, preferredTimescale: 600),
                filesByAngle: [.front: URL(fileURLWithPath: "/tmp/fake-\(mins).mp4")]
            )
        }
    }
}
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement**

Path: `TeslaCamViewer/Domain/RecentChunker.swift`

```swift
import Foundation

public enum RecentChunker {
    /// Splits a time-sorted list of MinuteSegments into event-level chunks.
    /// Two adjacent segments belong to the same chunk if the gap between
    /// `previous.end` and `next.start` is **≤** `gapThresholdSeconds`.
    public static func chunk(
        segments: [MinuteSegment],
        gapThresholdSeconds: Int
    ) -> [[MinuteSegment]] {
        guard !segments.isEmpty else { return [] }
        let threshold = TimeInterval(gapThresholdSeconds)
        var chunks: [[MinuteSegment]] = [[segments[0]]]
        for next in segments.dropFirst() {
            let prev = chunks[chunks.count - 1].last!
            let prevEnd = prev.timestamp.addingTimeInterval(prev.duration.seconds)
            let gap = next.timestamp.timeIntervalSince(prevEnd)
            if gap <= threshold {
                chunks[chunks.count - 1].append(next)
            } else {
                chunks.append([next])
            }
        }
        return chunks
    }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(domain): add RecentChunker for gap-based event splitting"
```

---

## Task 6: SettingsStore

**Dependencies:** T2 (AppSettings)

**Files:**
- Create: `TeslaCamViewer/Domain/SettingsStore.swift`
- Test: `TeslaCamViewerTests/Unit/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Unit/SettingsStoreTests.swift`

```swift
import XCTest
@testable import TeslaCamViewer

final class SettingsStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_firstLaunch_returnsDefaults() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, AppSettings())
    }

    func test_updating_persistsAcrossInstances() {
        let store1 = SettingsStore(defaults: defaults)
        store1.settings.recentGapThresholdSeconds = 900
        let store2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(store2.settings.recentGapThresholdSeconds, 900)
    }

    func test_updating_clampsOutOfRangeToValid() {
        let store = SettingsStore(defaults: defaults)
        store.settings.recentGapThresholdSeconds = 99_999
        XCTAssertEqual(store.settings.recentGapThresholdSeconds, AppSettings.maxRecentGapSeconds)
    }

    func test_changes_bumpVersion() {
        let store = SettingsStore(defaults: defaults)
        let v0 = store.version
        store.settings.recentGapThresholdSeconds = 600
        XCTAssertGreaterThan(store.version, v0)
    }
}
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement**

Path: `TeslaCamViewer/Domain/SettingsStore.swift`

```swift
import Foundation
import Observation

@Observable
public final class SettingsStore {
    private static let storageKey = "TeslaCamViewer.AppSettings.v1"
    private let defaults: UserDefaults

    public var settings: AppSettings {
        didSet {
            // Re-clamp in case the UI assigned an out-of-range value directly.
            let clamped = AppSettings(
                recentGapThresholdSeconds: settings.recentGapThresholdSeconds,
                defaultWatermarkPosition: settings.defaultWatermarkPosition
            )
            if clamped != settings {
                settings = clamped
                return   // didSet will run again; it'll hit the guard and persist there.
            }
            persist()
            version &+= 1
        }
    }

    /// Monotonically increasing counter bumped on every mutation, for
    /// consumers (e.g. `LibraryStore`) that want a cheap "something changed" trigger.
    public private(set) var version: Int = 0

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(domain): add SettingsStore with UserDefaults persistence"
```

---

## Task 7: Test Fixtures

**Dependencies:** T1 (project exists); otherwise standalone.

**Files:**
- Create: `TeslaCamViewerTests/Fixtures/README.md`
- Create: `TeslaCamViewerTests/Fixtures/generate-fixtures.sh`
- Create (via script): `TeslaCamViewerTests/Fixtures/fixture-*/...`

**Why now:** Task 8 (Scanner) needs these. We generate tiny 5-second MP4s deterministically with `ffmpeg` so the repo stays small (~500 KB total), and we set POSIX mtime on filenames so the timestamps match the Tesla naming convention rather than the file creation time.

- [ ] **Step 1: Verify ffmpeg is installed**

```bash
which ffmpeg || brew install ffmpeg
```

- [ ] **Step 2: Write the fixture-generator script**

Path: `TeslaCamViewerTests/Fixtures/generate-fixtures.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# One 5-second 1280x720 test MP4 we'll copy everywhere.
TMP_MP4="$HERE/.tmp-testsrc.mp4"
if [ ! -f "$TMP_MP4" ]; then
    ffmpeg -y -f lavfi -i testsrc=size=1280x720:rate=30 -t 5 \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$TMP_MP4" \
        -loglevel error
fi

# Rebuild all fixture directories from scratch.
for f in fixture-6cam-saved fixture-4cam-sentry fixture-corrupted \
         fixture-recent-continuous fixture-recent-gapped; do
    rm -rf "$HERE/$f"
done

# --- fixture-6cam-saved: new car, 6 angles, 1 SavedClip with 3 MinuteSegments
EV="fixture-6cam-saved/TeslaCam/SavedClips/2024-07-15_14-32-01"
mkdir -p "$EV"
for m in 30 31 32; do
    MIN_BASE="2024-07-15_14-${m}-01"
    for a in front back left_repeater right_repeater left_pillar right_pillar; do
        cp "$TMP_MP4" "$EV/${MIN_BASE}-${a}.mp4"
    done
done
printf '%s' '{"timestamp":"2024-07-15T14:32:01","city":"Mountain View","reason":"user_interaction_honk"}' > "$EV/event.json"
# thumb.png: just use front frame
ffmpeg -y -i "$TMP_MP4" -vframes 1 "$EV/thumb.png" -loglevel error

# --- fixture-4cam-sentry: old car, 4 angles, 2 SentryClips with 1 segment each
SENTRY_DIR="fixture-4cam-sentry/TeslaCam/SentryClips"
for clip in 2024-07-15_03-22-15 2024-07-16_11-05-00; do
    EV="$SENTRY_DIR/$clip"
    mkdir -p "$EV"
    for a in front back left_repeater right_repeater; do
        cp "$TMP_MP4" "$EV/${clip}-${a}.mp4"
    done
    printf '%s' "{\"timestamp\":\"${clip/_/T}\",\"reason\":\"sentry_aware_object_detection\"}" \
        | sed 's/-/-/g' > "$EV/event.json"
done

# --- fixture-corrupted: broken JSON + missing angle + stray files
EV="fixture-corrupted/TeslaCam/SavedClips/2024-07-17_09-00-00"
mkdir -p "$EV"
# Only 2 angles (back/right_pillar missing)
for a in front left_repeater; do
    cp "$TMP_MP4" "$EV/2024-07-17_09-00-00-${a}.mp4"
done
printf '%s' 'this is not valid json {{{' > "$EV/event.json"
touch "$EV/.DS_Store"
# Also include one folder with an unparseable name that must be skipped entirely.
BAD_DIR="fixture-corrupted/TeslaCam/SavedClips/random_trash_folder"
mkdir -p "$BAD_DIR"
cp "$TMP_MP4" "$BAD_DIR/some_file.mp4"

# --- fixture-recent-continuous: 5 minutes of back-to-back minute files, 4 angles
REC="fixture-recent-continuous/TeslaCam/RecentClips"
mkdir -p "$REC"
for m in 00 01 02 03 04; do
    MIN_BASE="2024-07-18_10-${m}-00"
    for a in front back left_repeater right_repeater; do
        cp "$TMP_MP4" "$REC/${MIN_BASE}-${a}.mp4"
    done
done

# --- fixture-recent-gapped: two clumps of 3 minutes each with a 10-minute gap
REC="fixture-recent-gapped/TeslaCam/RecentClips"
mkdir -p "$REC"
for m in 00 01 02 12 13 14; do
    # pad minute to two digits
    printf -v MM '%02d' "$m"
    MIN_BASE="2024-07-19_08-${MM}-00"
    for a in front back left_repeater right_repeater; do
        cp "$TMP_MP4" "$REC/${MIN_BASE}-${a}.mp4"
    done
done

rm -f "$TMP_MP4"
echo "Fixtures generated under $HERE"
```

- [ ] **Step 3: Write README**

Path: `TeslaCamViewerTests/Fixtures/README.md`

````markdown
# Test Fixtures

Each `fixture-*/TeslaCam/` mimics a real Tesla USB stick layout, but with tiny
5-second MP4s generated via `ffmpeg testsrc`.

## Regenerating

```bash
cd TeslaCamViewerTests/Fixtures
./generate-fixtures.sh
```

## What each fixture proves

- `fixture-6cam-saved/` — new car, 6 angles, 1 SavedClip with 3 MinuteSegments, includes thumb.png + event.json
- `fixture-4cam-sentry/` — old car, 4 angles, 2 SentryClips (one segment each)
- `fixture-corrupted/` — broken event.json + missing 2 angles + `.DS_Store` + junk folder. Scanner must skip gracefully.
- `fixture-recent-continuous/` — 5 consecutive minutes of RecentClips. Chunker with 5-min threshold → 1 event.
- `fixture-recent-gapped/` — two 3-minute clumps with a 10-minute gap. Chunker with 5-min threshold → 2 events, with 30-min threshold → 1 event.

## Why check in binaries?

Tiny deterministic ffmpeg output (~40 KB per file) keeps the repo small and
avoids requiring ffmpeg in CI. Regenerate only when naming conventions change.
````

- [ ] **Step 4: Run script**

```bash
cd /Users/shanehou/Developer/Projects/TeslaCamViewer/TeslaCamViewerTests/Fixtures
chmod +x generate-fixtures.sh
./generate-fixtures.sh
```

Expected output: `Fixtures generated under <path>`.

- [ ] **Step 5: Verify produced files**

```bash
cd /Users/shanehou/Developer/Projects/TeslaCamViewer/TeslaCamViewerTests/Fixtures
find . -type f \( -name '*.mp4' -o -name '*.json' -o -name '*.png' -o -name '.DS_Store' \) | sort | head -30
```

Expected: you see files like `fixture-6cam-saved/TeslaCam/SavedClips/2024-07-15_14-32-01/2024-07-15_14-32-01-front.mp4`, etc.

- [ ] **Step 6: Add the Fixtures directory as a test-target resource in `project.yml`**

Path: `project.yml` — modify the `TeslaCamViewerTests` target's `sources` block:

```yaml
  TeslaCamViewerTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: TeslaCamViewerTests
        excludes:
          - "Fixtures/**"
      - path: TeslaCamViewerTests/Fixtures
        buildPhase: resources
        type: folder          # ← copy the whole dir as a single folder reference
```

This makes `Bundle(for: XCTestCase.self).url(forResource: "Fixtures", withExtension: nil)` resolvable at test time. Regenerate the project:

```bash
make generate
make test-only TESTS=SmokeTest 2>&1 | tail -10
```

Expected: `Test Succeeded` (smoke test still passes; fixtures now copied into the test bundle).

- [ ] **Step 7: Commit**

```bash
git add TeslaCamViewerTests/Fixtures/
git commit -m "test: add TeslaCam structure fixtures for scanner integration"
```

---

## Task 8: TeslaCamScanner (Integration)

**Dependencies:** T3, T4, T7

**Files:**
- Create: `TeslaCamViewer/Domain/Protocols/ScannerProtocol.swift`
- Create: `TeslaCamViewer/Infrastructure/TeslaCamScanner.swift`
- Test: `TeslaCamViewerTests/Integration/TeslaCamScannerTests.swift`

- [ ] **Step 1: Write failing integration test**

Path: `TeslaCamViewerTests/Integration/TeslaCamScannerTests.swift`

```swift
import XCTest
@testable import TeslaCamViewer

final class TeslaCamScannerTests: XCTestCase {

    private func fixtureURL(_ name: String) -> URL {
        let bundle = Bundle(for: Self.self)
        return bundle.url(forResource: "Fixtures/\(name)/TeslaCam", withExtension: nil)
            ?? URL(fileURLWithPath: "/nonexistent")
    }

    func test_scan_sixCamSaved_returnsOneSavedEventWithAllAngles() async throws {
        let url = fixtureURL("fixture-6cam-saved")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "fixture not copied into test bundle")
        let scanner = TeslaCamScanner()
        let result = try await scanner.scan(root: url)
        XCTAssertEqual(result.savedEvents.count, 1)
        XCTAssertTrue(result.sentryEvents.isEmpty)
        XCTAssertTrue(result.recentSegments.isEmpty)

        let event = result.savedEvents[0]
        XCTAssertEqual(event.type, .saved)
        XCTAssertEqual(event.availableAngles.count, 6)
        XCTAssertEqual(event.segments.count, 3)
        XCTAssertNotNil(event.thumbnailURL)
        XCTAssertEqual(event.eventMetadata?.city, "Mountain View")
    }

    func test_scan_fourCamSentry_returnsTwoEventsOldCar() async throws {
        let scanner = TeslaCamScanner()
        let result = try await scanner.scan(root: fixtureURL("fixture-4cam-sentry"))
        XCTAssertEqual(result.sentryEvents.count, 2)
        for ev in result.sentryEvents {
            XCTAssertEqual(ev.availableAngles, [.front, .back, .leftRepeater, .rightRepeater])
        }
    }

    func test_scan_corrupted_skipsBadFoldersAndFiles() async throws {
        let scanner = TeslaCamScanner()
        let result = try await scanner.scan(root: fixtureURL("fixture-corrupted"))
        XCTAssertEqual(result.savedEvents.count, 1, "random_trash_folder must be skipped")
        let ev = result.savedEvents[0]
        XCTAssertEqual(ev.availableAngles, [.front, .leftRepeater])
        XCTAssertNil(ev.eventMetadata, "corrupted JSON → metadata nil, does not throw")
    }

    func test_scan_recentContinuous_returnsUnchunkedSegments() async throws {
        let scanner = TeslaCamScanner()
        let result = try await scanner.scan(root: fixtureURL("fixture-recent-continuous"))
        XCTAssertEqual(result.recentSegments.count, 5, "one per consecutive minute")
        XCTAssertTrue(result.savedEvents.isEmpty)
    }

    func test_scan_recentGapped_returnsAllSixSegmentsUnchunked() async throws {
        let scanner = TeslaCamScanner()
        let result = try await scanner.scan(root: fixtureURL("fixture-recent-gapped"))
        XCTAssertEqual(result.recentSegments.count, 6)
        // Scanner does NOT chunk; that's RecentChunker's job.
    }

    func test_scan_nonTeslaCamFolder_throwsNotTeslaCamFolder() async throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        let scanner = TeslaCamScanner()
        do {
            _ = try await scanner.scan(root: empty)
            XCTFail("expected AppError.notTeslaCamFolder")
        } catch AppError.notTeslaCamFolder {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
make test-only TESTS=TeslaCamScannerTests 2>&1 | tail -15
```

Expected: compile errors `cannot find 'TeslaCamScanner'` and `cannot find 'ScannerProtocol'`.

- [ ] **Step 3: Define protocol**

Path: `TeslaCamViewer/Domain/Protocols/ScannerProtocol.swift`

```swift
import Foundation

public struct ScanResult: Equatable {
    public var savedEvents: [TeslaEvent]
    public var sentryEvents: [TeslaEvent]
    /// RecentClips is returned UNCHUNKED. `LibraryStore` runs `RecentChunker`
    /// over these segments using the current `AppSettings.recentGapThresholdSeconds`.
    public var recentSegments: [MinuteSegment]

    public init(savedEvents: [TeslaEvent], sentryEvents: [TeslaEvent], recentSegments: [MinuteSegment]) {
        self.savedEvents = savedEvents
        self.sentryEvents = sentryEvents
        self.recentSegments = recentSegments
    }
}

public protocol ScannerProtocol {
    func scan(root: URL) async throws -> ScanResult
}
```

- [ ] **Step 4: Implement Scanner**

Path: `TeslaCamViewer/Infrastructure/TeslaCamScanner.swift`

```swift
import Foundation
import CoreMedia
import AVFoundation

public final class TeslaCamScanner: ScannerProtocol {
    private let fileManager: FileManager
    private let defaultSegmentDuration: CMTime

    public init(
        fileManager: FileManager = .default,
        defaultSegmentDuration: CMTime = CMTime(seconds: 60, preferredTimescale: 600)
    ) {
        self.fileManager = fileManager
        self.defaultSegmentDuration = defaultSegmentDuration
    }

    public func scan(root: URL) async throws -> ScanResult {
        let saved = root.appendingPathComponent("SavedClips")
        let sentry = root.appendingPathComponent("SentryClips")
        let recent = root.appendingPathComponent("RecentClips")

        // If root is the USB root (contains TeslaCam/), unwrap once.
        let effectiveRoot: URL = {
            let nested = root.appendingPathComponent("TeslaCam")
            if fileManager.fileExists(atPath: nested.appendingPathComponent("SavedClips").path)
                || fileManager.fileExists(atPath: nested.appendingPathComponent("SentryClips").path)
                || fileManager.fileExists(atPath: nested.appendingPathComponent("RecentClips").path) {
                return nested
            }
            return root
        }()

        let eSaved = effectiveRoot.appendingPathComponent("SavedClips")
        let eSentry = effectiveRoot.appendingPathComponent("SentryClips")
        let eRecent = effectiveRoot.appendingPathComponent("RecentClips")

        let anyExists =
            fileManager.fileExists(atPath: eSaved.path)  ||
            fileManager.fileExists(atPath: eSentry.path) ||
            fileManager.fileExists(atPath: eRecent.path)
        guard anyExists else { throw AppError.notTeslaCamFolder }
        _ = saved; _ = sentry; _ = recent  // silence unused warnings if needed

        let savedEvents  = fileManager.fileExists(atPath: eSaved.path)  ? scanClipDirectory(eSaved,  type: .saved)  : []
        let sentryEvents = fileManager.fileExists(atPath: eSentry.path) ? scanClipDirectory(eSentry, type: .sentry) : []
        let recentSegs   = fileManager.fileExists(atPath: eRecent.path) ? scanRecentDirectory(eRecent)              : []

        return ScanResult(
            savedEvents: savedEvents.sorted(by: { $0.startTime > $1.startTime }),
            sentryEvents: sentryEvents.sorted(by: { $0.startTime > $1.startTime }),
            recentSegments: recentSegs
        )
    }

    // MARK: - per-event folders (Saved / Sentry)

    private func scanClipDirectory(_ dir: URL, type: EventType) -> [TeslaEvent] {
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
        } catch {
            return []
        }

        var out: [TeslaEvent] = []
        for child in children {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let startTime = FolderNameParser.parse(child.lastPathComponent) else { continue }

            let files = (try? fileManager.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? []
            let mp4s = files.filter { $0.pathExtension.lowercased() == "mp4" }
            let segments = SegmentAggregator.aggregate(urls: mp4s, defaultSegmentDuration: defaultSegmentDuration)
            guard !segments.isEmpty else { continue }

            let available = Set(segments.flatMap { $0.filesByAngle.keys })
            let metadataURL = child.appendingPathComponent("event.json")
            let metadata: EventMetadata? = {
                guard fileManager.fileExists(atPath: metadataURL.path),
                      let data = try? Data(contentsOf: metadataURL) else { return nil }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = TeslaCamScanner.eventJsonDateStrategy
                return try? decoder.decode(EventMetadata.self, from: data)
            }()
            let thumbURL = child.appendingPathComponent("thumb.png")
            let thumbnail: URL? = fileManager.fileExists(atPath: thumbURL.path) ? thumbURL : nil

            out.append(TeslaEvent(
                id: child.lastPathComponent,
                type: type,
                startTime: startTime,
                segments: segments,
                availableAngles: available,
                thumbnailURL: thumbnail,
                eventMetadata: metadata
            ))
        }
        return out
    }

    // MARK: - flat RecentClips

    private func scanRecentDirectory(_ dir: URL) -> [MinuteSegment] {
        let files = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let mp4s = files.filter { $0.pathExtension.lowercased() == "mp4" }
        return SegmentAggregator.aggregate(urls: mp4s, defaultSegmentDuration: defaultSegmentDuration)
    }

    static let eventJsonDateStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let str = try decoder.singleValueContainer().decode(String.self)
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime]
        if let d = f1.date(from: str) { return d }
        let f2 = DateFormatter()
        f2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f2.locale = Locale(identifier: "en_US_POSIX")
        f2.timeZone = TimeZone(secondsFromGMT: 0)
        if let d = f2.date(from: str) { return d }
        throw DecodingError.dataCorruptedError(
            in: try decoder.singleValueContainer(),
            debugDescription: "Unrecognized date string: \(str)"
        )
    }
}
```

- [ ] **Step 5: Run — expect pass**

Same command as Step 2. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(infra): implement TeslaCamScanner with integration tests"
```

---

## Task 9: LibraryStore

**Dependencies:** T5, T6, T8

**Files:**
- Create: `TeslaCamViewer/Domain/LibraryStore.swift`
- Test: `TeslaCamViewerTests/Unit/LibraryStoreTests.swift`

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Unit/LibraryStoreTests.swift`

```swift
import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class LibraryStoreTests: XCTestCase {

    /// Minimal in-memory scanner stub returning a canned ScanResult.
    private final class FakeScanner: ScannerProtocol {
        var result: ScanResult
        init(result: ScanResult) { self.result = result }
        func scan(root: URL) async throws -> ScanResult { result }
    }

    private func makeFakeResult(
        recentOffsetsMinutes: [Int] = []
    ) -> ScanResult {
        let savedEvent = TeslaEvent.fixture(id: "saved-1", type: .saved, segments: [.fixture()])
        let sentryEvent = TeslaEvent.fixture(id: "sentry-1", type: .sentry, segments: [.fixture()])
        let base = Date(timeIntervalSince1970: 1_721_050_321)
        let segs = recentOffsetsMinutes.map { mins in
            MinuteSegment(
                timestamp: base.addingTimeInterval(TimeInterval(mins * 60)),
                duration: CMTime(seconds: 60, preferredTimescale: 600),
                filesByAngle: [.front: URL(fileURLWithPath: "/tmp/\(mins).mp4")]
            )
        }
        return ScanResult(savedEvents: [savedEvent], sentryEvents: [sentryEvent], recentSegments: segs)
    }

    func test_loadEvents_populatesSavedAndSentry() async throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let scanner = FakeScanner(result: makeFakeResult())
        let store = LibraryStore(scanner: scanner, settings: settings)
        try await store.load(root: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(store.savedEvents.count, 1)
        XCTAssertEqual(store.sentryEvents.count, 1)
        XCTAssertEqual(store.recentEvents.count, 0)
    }

    func test_recentEvents_useCurrentThreshold() async throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.settings.recentGapThresholdSeconds = 300     // 5 min

        let scanner = FakeScanner(result: makeFakeResult(recentOffsetsMinutes: [0, 1, 12, 13]))
        let store = LibraryStore(scanner: scanner, settings: settings)
        try await store.load(root: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(store.recentEvents.count, 2)
    }

    func test_changingThreshold_reChunksWithoutRescan() async throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.settings.recentGapThresholdSeconds = 300
        let scanner = FakeScanner(result: makeFakeResult(recentOffsetsMinutes: [0, 1, 12, 13]))
        let store = LibraryStore(scanner: scanner, settings: settings)
        try await store.load(root: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(store.recentEvents.count, 2)

        // Change the fake scanner's canned result so that if LibraryStore
        // accidentally rescans, the test would notice — but it should not rescan.
        scanner.result = ScanResult(savedEvents: [], sentryEvents: [], recentSegments: [])
        settings.settings.recentGapThresholdSeconds = 1_800     // 30 min

        // Allow the store's observation to run.
        await Task.yield()

        XCTAssertEqual(store.recentEvents.count, 1, "threshold widened → one merged event")
        // Saved/sentry unchanged, proving no rescan happened:
        XCTAssertEqual(store.savedEvents.count, 1)
    }
}
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement**

Path: `TeslaCamViewer/Domain/LibraryStore.swift`

```swift
import Foundation
import Observation

@Observable
public final class LibraryStore {
    public private(set) var savedEvents: [TeslaEvent] = []
    public private(set) var sentryEvents: [TeslaEvent] = []
    public private(set) var recentEvents: [TeslaEvent] = []

    public private(set) var lastError: AppError?
    public private(set) var isLoading = false

    @ObservationIgnored private let scanner: ScannerProtocol
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var cachedRecentSegments: [MinuteSegment] = []
    @ObservationIgnored private var lastSettingsVersion: Int = -1
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    public init(scanner: ScannerProtocol, settings: SettingsStore) {
        self.scanner = scanner
        self.settings = settings
        startObservingSettings()
    }

    deinit { observationTask?.cancel() }

    public func load(root: URL) async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await scanner.scan(root: root)
            savedEvents = result.savedEvents
            sentryEvents = result.sentryEvents
            cachedRecentSegments = result.recentSegments
            rechunkRecent()
        } catch let err as AppError {
            lastError = err
            throw err
        } catch {
            lastError = .eventCorrupted(id: "scan", underlying: error)
            throw error
        }
    }

    // MARK: - Settings reactivity

    private func startObservingSettings() {
        observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Re-register observation each iteration — this is the standard
                // pattern for reacting to @Observable changes outside SwiftUI.
                let currentVersion = withObservationTracking {
                    self?.settings.version ?? 0
                } onChange: { /* will fire once; loop re-registers */ }

                guard let self else { return }
                if currentVersion != self.lastSettingsVersion {
                    self.lastSettingsVersion = currentVersion
                    self.rechunkRecent()
                }
                try? await Task.sleep(nanoseconds: 50_000_000)   // 50 ms poll between observations
            }
        }
    }

    private func rechunkRecent() {
        let chunks = RecentChunker.chunk(
            segments: cachedRecentSegments,
            gapThresholdSeconds: settings.settings.recentGapThresholdSeconds
        )
        recentEvents = chunks.map { segs -> TeslaEvent in
            let first = segs.first!
            let available = Set(segs.flatMap { $0.filesByAngle.keys })
            return TeslaEvent(
                id: "recent-\(ISO8601DateFormatter().string(from: first.timestamp))",
                type: .recent,
                startTime: first.timestamp,
                segments: segs,
                availableAngles: available,
                thumbnailURL: nil,
                eventMetadata: nil
            )
        }.sorted(by: { $0.startTime > $1.startTime })
    }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(domain): add LibraryStore with reactive re-chunking"
```

---

## Task 10: BookmarkStore + Security-scoped folder access

**Dependencies:** T2

**Files:**
- Create: `TeslaCamViewer/Domain/Protocols/BookmarkStoreProtocol.swift`
- Create: `TeslaCamViewer/Infrastructure/BookmarkStore.swift`
- Test: `TeslaCamViewerTests/Unit/BookmarkStoreTests.swift`

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Unit/BookmarkStoreTests.swift`

```swift
import XCTest
@testable import TeslaCamViewer

final class BookmarkStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "BookmarkStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_initiallyNoBookmark() {
        let store = BookmarkStore(defaults: defaults)
        XCTAssertFalse(store.hasBookmark)
    }

    func test_saveAndLoad_roundtripRealDirectoryOnDisk() throws {
        // Use a real tmp directory so the bookmark actually resolves.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = BookmarkStore(defaults: defaults)
        try store.save(url: tmp)
        XCTAssertTrue(store.hasBookmark)

        let resolved = try store.resolve()
        XCTAssertEqual(resolved.standardizedFileURL.path, tmp.standardizedFileURL.path)
    }

    func test_resolveMissingBookmark_throwsBookmarkStale() {
        let store = BookmarkStore(defaults: defaults)
        do {
            _ = try store.resolve()
            XCTFail("expected AppError.bookmarkStale")
        } catch AppError.bookmarkStale {
            // ok
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func test_clear_removesBookmark() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = BookmarkStore(defaults: defaults)
        try store.save(url: tmp)
        store.clear()
        XCTAssertFalse(store.hasBookmark)
    }
}
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement protocol + store**

Path: `TeslaCamViewer/Domain/Protocols/BookmarkStoreProtocol.swift`

```swift
import Foundation

public protocol BookmarkStoreProtocol {
    var hasBookmark: Bool { get }
    func save(url: URL) throws
    func resolve() throws -> URL
    func clear()
}
```

Path: `TeslaCamViewer/Infrastructure/BookmarkStore.swift`

```swift
import Foundation

public final class BookmarkStore: BookmarkStoreProtocol {
    private static let key = "TeslaCamViewer.FolderBookmark.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasBookmark: Bool {
        defaults.data(forKey: Self.key) != nil
    }

    public func save(url: URL) throws {
        #if os(iOS)
        let data = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
        defaults.set(data, forKey: Self.key)
    }

    public func resolve() throws -> URL {
        guard let data = defaults.data(forKey: Self.key) else { throw AppError.bookmarkStale }
        var stale = false
        let url: URL
        do {
            #if os(iOS)
            url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            #else
            url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            #endif
        } catch {
            throw AppError.bookmarkStale
        }
        if stale { throw AppError.bookmarkStale }
        return url
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(infra): add BookmarkStore for folder-scoped URL persistence"
```

---

## Task 11: MultiAVPlayer + PlaybackController

**Dependencies:** T2, T7

**Files:**
- Create: `TeslaCamViewer/Domain/Protocols/PlayerProtocol.swift`
- Create: `TeslaCamViewer/Infrastructure/MultiAVPlayer.swift`
- Create: `TeslaCamViewer/Domain/PlaybackController.swift`
- Test: `TeslaCamViewerTests/Integration/MultiAVPlayerTests.swift`

- [ ] **Step 1: Write failing test (uses real AVFoundation against fixtures)**

Path: `TeslaCamViewerTests/Integration/MultiAVPlayerTests.swift`

```swift
import XCTest
import AVFoundation
import CoreMedia
@testable import TeslaCamViewer

final class MultiAVPlayerTests: XCTestCase {

    private func fixtureEvent() async throws -> TeslaEvent {
        let bundle = Bundle(for: Self.self)
        let root = bundle.url(forResource: "Fixtures/fixture-6cam-saved/TeslaCam", withExtension: nil)!
        let scanner = TeslaCamScanner()
        let result = try await scanner.scan(root: root)
        return result.savedEvents[0]
    }

    func test_totalDuration_isSumOfSegmentDurations() async throws {
        let event = try await fixtureEvent()
        let player = MultiAVPlayer()
        try await player.load(event: event, angles: [.front, .back])
        // Fixture: 3 segments × ~5s = ~15s
        let expected = event.totalDuration.seconds
        XCTAssertEqual(player.totalDuration.seconds, expected, accuracy: 0.5)
    }

    func test_seek_bringsAllPlayersWithin100msSyncWindow() async throws {
        let event = try await fixtureEvent()
        let player = MultiAVPlayer()
        try await player.load(event: event, angles: [.front, .back, .leftRepeater, .rightRepeater])
        try await player.seek(to: CMTime(seconds: 6, preferredTimescale: 600))

        let times = player.debugPerAnglePlayhead()
        XCTAssertFalse(times.isEmpty)
        let maxGap = times.max()!.seconds - times.min()!.seconds
        XCTAssertLessThan(maxGap, 0.1)
    }

    func test_missingAngle_doesNotThrowAndIsSkipped() async throws {
        let event = try await fixtureEvent()
        let player = MultiAVPlayer()
        // fixture-6cam-saved HAS left_pillar, so synthesize an event that doesn't.
        let trimmed = TeslaEvent(
            id: event.id, type: event.type, startTime: event.startTime,
            segments: event.segments,
            availableAngles: [.front, .back],   // pretend
            thumbnailURL: event.thumbnailURL, eventMetadata: event.eventMetadata
        )
        try await player.load(event: trimmed, angles: [.front, .back, .leftPillar])
        XCTAssertEqual(player.loadedAngles, [.front, .back])
    }
}
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement protocol + player**

Path: `TeslaCamViewer/Domain/Protocols/PlayerProtocol.swift`

```swift
import Foundation
import CoreMedia
import AVFoundation

public protocol PlayerProtocol: AnyObject {
    var totalDuration: CMTime { get }
    var loadedAngles: [CameraAngle] { get }
    var currentTime: CMTime { get }
    var isPlaying: Bool { get }

    func load(event: TeslaEvent, angles: [CameraAngle]) async throws
    func play()
    func pause()
    func seek(to time: CMTime) async throws

    /// SwiftUI needs to show per-angle AVPlayerLayers. The view layer will ask for these players.
    func player(for angle: CameraAngle) -> AVPlayer?
}
```

Path: `TeslaCamViewer/Infrastructure/MultiAVPlayer.swift`

```swift
import Foundation
import CoreMedia
import AVFoundation

public final class MultiAVPlayer: PlayerProtocol {
    public private(set) var totalDuration: CMTime = .zero
    public private(set) var loadedAngles: [CameraAngle] = []
    public var currentTime: CMTime {
        playersByAngle.values.first?.currentTime() ?? .zero
    }
    public var isPlaying: Bool {
        playersByAngle.values.first?.timeControlStatus == .playing
    }

    private var playersByAngle: [CameraAngle: AVPlayer] = [:]

    public init() {}

    public func load(event: TeslaEvent, angles requested: [CameraAngle]) async throws {
        teardown()

        let angles = requested.filter { event.availableAngles.contains($0) }
        var players: [CameraAngle: AVPlayer] = [:]

        for angle in angles {
            let comp = AVMutableComposition()
            let track = comp.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )!
            var cursor: CMTime = .zero
            for seg in event.segments {
                guard let url = seg.filesByAngle[angle] else {
                    // Leave a gap of `seg.duration` so playhead stays aligned with other angles.
                    cursor = cursor + seg.duration
                    continue
                }
                let asset = AVURLAsset(url: url)
                do {
                    let videoTracks = try await asset.loadTracks(withMediaType: .video)
                    guard let vt = videoTracks.first else { cursor = cursor + seg.duration; continue }
                    let dur = try await asset.load(.duration)
                    try track.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: vt, at: cursor)
                    cursor = cursor + dur
                } catch {
                    cursor = cursor + seg.duration   // skip broken file, keep alignment
                }
            }
            let item = AVPlayerItem(asset: comp)
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            player.sourceClock = CMClockGetHostTimeClock()
            players[angle] = player
        }

        playersByAngle = players
        loadedAngles = angles
        totalDuration = event.totalDuration
    }

    public func play()  { playersByAngle.values.forEach { $0.play()  } }
    public func pause() { playersByAngle.values.forEach { $0.pause() } }

    public func seek(to time: CMTime) async throws {
        await withTaskGroup(of: Void.self) { group in
            for p in playersByAngle.values {
                group.addTask {
                    await withCheckedContinuation { cont in
                        p.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                            cont.resume()
                        }
                    }
                }
            }
        }
    }

    public func player(for angle: CameraAngle) -> AVPlayer? { playersByAngle[angle] }

    public func debugPerAnglePlayhead() -> [CMTime] {
        playersByAngle.values.map { $0.currentTime() }
    }

    private func teardown() {
        playersByAngle.values.forEach { $0.pause() }
        playersByAngle.removeAll()
        loadedAngles.removeAll()
        totalDuration = .zero
    }
}
```

Path: `TeslaCamViewer/Domain/PlaybackController.swift`

```swift
import Foundation
import CoreMedia
import AVFoundation
import Observation

@Observable
public final class PlaybackController {
    public private(set) var totalDuration: CMTime = .zero
    public private(set) var currentTime: CMTime = .zero
    public private(set) var isPlaying: Bool = false
    public private(set) var loadedAngles: [CameraAngle] = []
    public private(set) var trim: TrimRange = TrimRange(start: .zero, end: .init(seconds: 1, preferredTimescale: 600), totalDuration: .init(seconds: 1, preferredTimescale: 600))

    @ObservationIgnored private let player: PlayerProtocol
    @ObservationIgnored private var timeObserver: Any?

    public init(player: PlayerProtocol) {
        self.player = player
    }

    public func load(event: TeslaEvent, angles: [CameraAngle]) async throws {
        try await player.load(event: event, angles: angles)
        totalDuration = player.totalDuration
        loadedAngles = player.loadedAngles
        trim = TrimRange.fullRange(totalDuration: totalDuration)
        attachTimeObserver()
    }

    public func play()  { player.play();  isPlaying = true }
    public func pause() { player.pause(); isPlaying = false }

    public func seek(to t: CMTime) async throws {
        try await player.seek(to: t)
        currentTime = t
    }

    public func setTrim(start: CMTime, end: CMTime) {
        trim = TrimRange(start: start, end: end, totalDuration: totalDuration)
    }

    public func player(for angle: CameraAngle) -> AVPlayer? { player.player(for: angle) }

    private func attachTimeObserver() {
        guard let p = player.player(for: loadedAngles.first ?? .front) else { return }
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            self?.currentTime = t
            self?.isPlaying = p.timeControlStatus == .playing
        }
    }
}
```

- [ ] **Step 4: Run — expect pass**

```bash
make test-only TESTS=MultiAVPlayerTests 2>&1 | tail -15
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(infra): implement MultiAVPlayer + PlaybackController with per-angle composition"
```

---

## Task 12: AVComposer + ExportJob

**Dependencies:** T2, T7

**Files:**
- Create: `TeslaCamViewer/Domain/Protocols/ComposerProtocol.swift`
- Create: `TeslaCamViewer/Infrastructure/AVComposer.swift`
- Create: `TeslaCamViewer/Domain/ExportJob.swift`
- Test: `TeslaCamViewerTests/Integration/AVComposerTests.swift`

### 12a. ComposerProtocol + AVComposer

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Integration/AVComposerTests.swift`

```swift
import XCTest
import AVFoundation
@testable import TeslaCamViewer

final class AVComposerTests: XCTestCase {

    private func fixtureEvent() async throws -> TeslaEvent {
        let bundle = Bundle(for: Self.self)
        let root = bundle.url(forResource: "Fixtures/fixture-6cam-saved/TeslaCam", withExtension: nil)!
        let scanner = TeslaCamScanner()
        return try await scanner.scan(root: root).savedEvents[0]
    }

    private var outputURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AVComposerTests-\(UUID().uuidString).mp4")
    }

    func test_singleAngle_export_producesPlayableMP4() async throws {
        let event = try await fixtureEvent()
        let request = ExportRequest(
            event: event,
            layout: .singlesPerAngle(angles: [.front]),
            range: TrimRange(start: .zero, end: CMTime(seconds: 4, preferredTimescale: 600), totalDuration: event.totalDuration),
            watermarkPosition: .bottomLeft
        )
        let outURL = outputURL
        defer { try? FileManager.default.removeItem(at: outURL) }

        let composer = AVComposer()
        try await composer.exportSingleAngle(.front, request: request, to: outURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path))
        let asset = AVURLAsset(url: outURL)
        let dur = try await asset.load(.duration)
        XCTAssertEqual(dur.seconds, 4, accuracy: 0.5)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty)
    }

    func test_gridExport_producesPlayable2x2Video() async throws {
        let event = try await fixtureEvent()
        let request = ExportRequest(
            event: event,
            layout: .gridCombined(angles: [.front, .back, .leftRepeater, .rightRepeater]),
            range: TrimRange(start: .zero, end: CMTime(seconds: 4, preferredTimescale: 600), totalDuration: event.totalDuration),
            watermarkPosition: .bottomLeft
        )
        let outURL = outputURL
        defer { try? FileManager.default.removeItem(at: outURL) }

        let composer = AVComposer()
        try await composer.exportGrid(request: request, to: outURL)

        let asset = AVURLAsset(url: outURL)
        let track = try await asset.loadTracks(withMediaType: .video).first
        XCTAssertNotNil(track)
        let size = try await track!.load(.naturalSize)
        XCTAssertEqual(size.width, 1920)
        XCTAssertEqual(size.height, 1080)
    }
}
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement protocol**

Path: `TeslaCamViewer/Domain/Protocols/ComposerProtocol.swift`

```swift
import Foundation

public protocol ComposerProtocol {
    /// Export a single angle at the event's native resolution with a timestamp watermark.
    func exportSingleAngle(_ angle: CameraAngle, request: ExportRequest, to url: URL) async throws

    /// Export four angles into a 1920×1080 2×2 grid with per-cell angle labels + timestamp watermark.
    func exportGrid(request: ExportRequest, to url: URL) async throws
}
```

- [ ] **Step 4: Implement AVComposer**

Path: `TeslaCamViewer/Infrastructure/AVComposer.swift`

```swift
import Foundation
import AVFoundation
import CoreMedia
import QuartzCore
import UIKit

public final class AVComposer: ComposerProtocol {
    public init() {}

    // MARK: Single angle

    public func exportSingleAngle(_ angle: CameraAngle, request: ExportRequest, to url: URL) async throws {
        let (composition, videoComp, renderSize) = try await singleAngleComposition(
            request: request, angle: angle
        )
        try await runExport(
            composition: composition,
            videoComposition: videoComp,
            renderSize: renderSize,
            watermarkBakeInfo: .init(
                position: request.watermarkPosition,
                layoutKind: .single,
                eventStart: request.event.startTime,
                rangeStart: request.range.start
            ),
            to: url
        )
    }

    // MARK: Grid

    public func exportGrid(request: ExportRequest, to url: URL) async throws {
        guard case .gridCombined(let angles) = request.layout, angles.count == 4 else {
            throw AppError.exportFailed(underlying: NSError(
                domain: "AVComposer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "gridCombined requires exactly 4 angles"]
            ))
        }
        let (composition, videoComp) = try await gridComposition(
            request: request, angles: angles, renderSize: CGSize(width: 1920, height: 1080)
        )
        try await runExport(
            composition: composition,
            videoComposition: videoComp,
            renderSize: CGSize(width: 1920, height: 1080),
            watermarkBakeInfo: .init(
                position: request.watermarkPosition,
                layoutKind: .grid(angles: angles),
                eventStart: request.event.startTime,
                rangeStart: request.range.start
            ),
            to: url
        )
    }

    // MARK: - single angle helpers

    private func singleAngleComposition(
        request: ExportRequest,
        angle: CameraAngle
    ) async throws -> (AVMutableComposition, AVMutableVideoComposition, CGSize) {
        let comp = AVMutableComposition()
        let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let trimDuration = request.range.end - request.range.start

        var eventCursor: CMTime = .zero       // running timeline position in the event
        var compositionCursor: CMTime = .zero // where we insert next in the composition
        var renderSize = CGSize(width: 1280, height: 960)

        for seg in request.event.segments {
            let segStart = eventCursor
            let segEnd = eventCursor + seg.duration
            defer { eventCursor = segEnd }

            let overlapStart = max(segStart, request.range.start)
            let overlapEnd = min(segEnd, request.range.end)
            guard overlapStart < overlapEnd else { continue }

            guard let u = seg.filesByAngle[angle] else {
                compositionCursor = compositionCursor + (overlapEnd - overlapStart)
                continue
            }
            let asset = AVURLAsset(url: u)
            do {
                let vts = try await asset.loadTracks(withMediaType: .video)
                guard let vt = vts.first else {
                    compositionCursor = compositionCursor + (overlapEnd - overlapStart)
                    continue
                }
                let fileOffset = overlapStart - segStart
                let insertDuration = overlapEnd - overlapStart
                try track.insertTimeRange(
                    CMTimeRange(start: fileOffset, duration: insertDuration),
                    of: vt,
                    at: compositionCursor
                )
                let sz = try await vt.load(.naturalSize)
                if sz.width > 0, sz.height > 0 { renderSize = sz }
                compositionCursor = compositionCursor + insertDuration
            } catch {
                compositionCursor = compositionCursor + (overlapEnd - overlapStart)
            }
        }

        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = renderSize
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)

        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: trimDuration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        instr.layerInstructions = [layer]
        videoComp.instructions = [instr]

        return (comp, videoComp, renderSize)
    }

    // MARK: - grid helpers

    private func gridComposition(
        request: ExportRequest,
        angles: [CameraAngle],
        renderSize: CGSize
    ) async throws -> (AVMutableComposition, AVMutableVideoComposition) {
        let comp = AVMutableComposition()
        let cellW = renderSize.width / 2
        let cellH = renderSize.height / 2
        let trimDuration = request.range.end - request.range.start

        var layerInstrs: [AVMutableVideoCompositionLayerInstruction] = []

        for (idx, angle) in angles.enumerated() {
            let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            // For this angle, walk the event's segments and insert only the portions
            // overlapping [range.start, range.end]. This is the single-pass approach:
            // no second composition, no getTransformRamp needed.
            var eventCursor: CMTime = .zero          // timeline position of current segment start in the event
            var compositionCursor: CMTime = .zero    // where we're inserting into this track
            var nativeSize = CGSize(width: 1280, height: 960)

            for seg in request.event.segments {
                let segStart = eventCursor
                let segEnd = eventCursor + seg.duration
                defer { eventCursor = segEnd }

                // Compute overlap between [segStart, segEnd] and [range.start, range.end]
                let overlapStart = max(segStart, request.range.start)
                let overlapEnd = min(segEnd, request.range.end)
                guard overlapStart < overlapEnd else { continue }

                guard let u = seg.filesByAngle[angle] else {
                    compositionCursor = compositionCursor + (overlapEnd - overlapStart)
                    continue
                }
                let asset = AVURLAsset(url: u)
                do {
                    let vts = try await asset.loadTracks(withMediaType: .video)
                    guard let vt = vts.first else {
                        compositionCursor = compositionCursor + (overlapEnd - overlapStart)
                        continue
                    }
                    // Offset inside this segment's file:
                    let fileOffset = overlapStart - segStart
                    let insertDuration = overlapEnd - overlapStart
                    try track.insertTimeRange(
                        CMTimeRange(start: fileOffset, duration: insertDuration),
                        of: vt,
                        at: compositionCursor
                    )
                    let sz = try await vt.load(.naturalSize)
                    if sz.width > 0, sz.height > 0 { nativeSize = sz }
                    compositionCursor = compositionCursor + insertDuration
                } catch {
                    compositionCursor = compositionCursor + (overlapEnd - overlapStart)
                }
            }

            // Scale to cover the 1/4 cell and center.
            let scale = max(cellW / nativeSize.width, cellH / nativeSize.height)
            let scaled = CGSize(width: nativeSize.width * scale, height: nativeSize.height * scale)
            let row = idx / 2, col = idx % 2   // 0=TL, 1=TR, 2=BL, 3=BR
            let cellX = CGFloat(col) * cellW
            let cellY = CGFloat(row) * cellH
            let offsetX = cellX + (cellW - scaled.width) / 2
            let offsetY = cellY + (cellH - scaled.height) / 2

            let t = CGAffineTransform(translationX: offsetX, y: offsetY)
                .scaledBy(x: scale, y: scale)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(t, at: .zero)
            layerInstrs.append(layer)
        }

        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = renderSize
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)
        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: trimDuration)
        instr.layerInstructions = layerInstrs
        videoComp.instructions = [instr]

        return (comp, videoComp)
    }

    // MARK: - watermark + export

    struct WatermarkBakeInfo {
        enum LayoutKind { case single, grid(angles: [CameraAngle]) }
        let position: ExportRequest.WatermarkPosition
        let layoutKind: LayoutKind
        let eventStart: Date
        let rangeStart: CMTime
    }

    private func runExport(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        watermarkBakeInfo info: WatermarkBakeInfo,
        to url: URL
    ) async throws {
        attachWatermark(videoComposition: videoComposition, renderSize: renderSize, info: info)

        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw AppError.exportFailed(underlying: NSError(domain: "AVComposer", code: 2)) }

        session.outputURL = url
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true

        // Wrap the callback-based export in a continuation. The iOS 18+ async
        // `export()` is not available on the iOS 17 deployment target.
        await withCheckedContinuation { cont in
            session.exportAsynchronously { cont.resume() }
        }
        if session.status != .completed {
            throw AppError.exportFailed(underlying: session.error ?? NSError(domain: "AVComposer", code: 3))
        }
    }

    private func attachWatermark(
        videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        info: WatermarkBakeInfo
    ) {
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)

        // Timestamp layer — animated via keyframes over the full duration.
        let timestamp = CATextLayer()
        timestamp.font = UIFont.systemFont(ofSize: 24, weight: .semibold)
        timestamp.fontSize = 24
        timestamp.foregroundColor = UIColor.white.cgColor
        timestamp.shadowColor = UIColor.black.cgColor
        timestamp.shadowOpacity = 0.9
        timestamp.shadowRadius = 3
        timestamp.alignmentMode = .left
        timestamp.contentsScale = UIScreen.main.scale
        timestamp.frame = timestampFrame(renderSize: renderSize, position: info.position)
        parent.addSublayer(timestamp)

        // Build one sample per second; good enough resolution for dashcam timestamps.
        let totalSeconds = Int(videoComposition.instructions.first?.timeRange.duration.seconds ?? 0)
        var values: [String] = []
        var keyTimes: [NSNumber] = []
        let eventStart = info.eventStart
        let base = eventStart.addingTimeInterval(info.rangeStart.seconds)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        for sec in 0...max(1, totalSeconds) {
            values.append(df.string(from: base.addingTimeInterval(TimeInterval(sec))))
            let frac = totalSeconds > 0 ? Double(sec) / Double(totalSeconds) : 0
            keyTimes.append(NSNumber(value: frac))
        }
        let anim = CAKeyframeAnimation(keyPath: "string")
        anim.values = values
        anim.keyTimes = keyTimes
        anim.calculationMode = .discrete
        anim.duration = max(1, Double(totalSeconds))
        anim.isRemovedOnCompletion = false
        anim.beginTime = AVCoreAnimationBeginTimeAtZero
        timestamp.add(anim, forKey: "timestamp")
        timestamp.string = values.first ?? ""

        // Per-cell angle labels for grid layouts
        if case .grid(let angles) = info.layoutKind {
            let cellW = renderSize.width / 2
            let cellH = renderSize.height / 2
            for (idx, angle) in angles.enumerated() {
                let label = CATextLayer()
                label.string = angleLabel(angle)
                label.font = UIFont.systemFont(ofSize: 20, weight: .medium)
                label.fontSize = 20
                label.foregroundColor = UIColor.white.cgColor
                label.shadowColor = UIColor.black.cgColor
                label.shadowOpacity = 0.9
                label.shadowRadius = 3
                label.contentsScale = UIScreen.main.scale
                let row = idx / 2, col = idx % 2
                let x = CGFloat(col) * cellW + 12
                // CoreAnimation is flipped; top of cell = renderSize.height - (row+1)*cellH
                let y = renderSize.height - CGFloat(row) * cellH - 32
                label.frame = CGRect(x: x, y: y, width: 180, height: 24)
                parent.addSublayer(label)
            }
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parent
        )
    }

    private func timestampFrame(renderSize: CGSize, position: ExportRequest.WatermarkPosition) -> CGRect {
        let w: CGFloat = 320, h: CGFloat = 28, pad: CGFloat = 16
        switch position {
        case .bottomLeft:  return CGRect(x: pad, y: pad, width: w, height: h)
        case .bottomRight: return CGRect(x: renderSize.width - w - pad, y: pad, width: w, height: h)
        case .topLeft:     return CGRect(x: pad, y: renderSize.height - h - pad, width: w, height: h)
        case .topRight:    return CGRect(x: renderSize.width - w - pad, y: renderSize.height - h - pad, width: w, height: h)
        }
    }

    private func angleLabel(_ a: CameraAngle) -> String {
        switch a {
        case .front: return "前 Front"
        case .back: return "后 Back"
        case .leftRepeater: return "左后 L-Rep"
        case .rightRepeater: return "右后 R-Rep"
        case .leftPillar: return "左柱 L-Pil"
        case .rightPillar: return "右柱 R-Pil"
        }
    }
}
```

- [ ] **Step 5: Run — expect pass**

```bash
make test-only TESTS=AVComposerTests 2>&1 | tail -20
```

Export is slow; this test can take up to 60s. If it flakes, use `-maximum-concurrent-test-simulator-destinations 1`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(infra): implement AVComposer with single-angle and 2x2 grid export + watermark"
```

### 12b. ExportJob

- [ ] **Step 1: Write failing test**

Path: `TeslaCamViewerTests/Integration/ExportJobTests.swift`

```swift
import XCTest
import CoreMedia
@testable import TeslaCamViewer

final class ExportJobTests: XCTestCase {

    private final class StubComposer: ComposerProtocol {
        var singleCalls: [(CameraAngle, URL)] = []
        var gridCalls: [URL] = []
        var shouldFail: Error?

        func exportSingleAngle(_ angle: CameraAngle, request: ExportRequest, to url: URL) async throws {
            if let e = shouldFail { throw e }
            singleCalls.append((angle, url))
            FileManager.default.createFile(atPath: url.path, contents: Data([0x00]))
        }

        func exportGrid(request: ExportRequest, to url: URL) async throws {
            if let e = shouldFail { throw e }
            gridCalls.append(url)
            FileManager.default.createFile(atPath: url.path, contents: Data([0x00]))
        }
    }

    private func makeRequest(layout: ExportRequest.Layout) -> ExportRequest {
        let event = TeslaEvent.fixture(segments: [.fixture(), .fixture(offsetSeconds: 60)])
        return ExportRequest(
            event: event,
            layout: layout,
            range: TrimRange.fullRange(totalDuration: event.totalDuration),
            watermarkPosition: .bottomLeft
        )
    }

    func test_singlesLayout_callsComposerOncePerAngle() async throws {
        let composer = StubComposer()
        let job = ExportJob(composer: composer)
        let req = makeRequest(layout: .singlesPerAngle(angles: [.front, .back]))
        let result = try await job.run(req)
        XCTAssertEqual(composer.singleCalls.count, 2)
        XCTAssertEqual(composer.gridCalls.count, 0)
        XCTAssertEqual(result.outputURLs.count, 2)
    }

    func test_gridLayout_callsComposerOnce() async throws {
        let composer = StubComposer()
        let job = ExportJob(composer: composer)
        let req = makeRequest(layout: .gridCombined(angles: [.front, .back, .leftRepeater, .rightRepeater]))
        let result = try await job.run(req)
        XCTAssertEqual(composer.gridCalls.count, 1)
        XCTAssertEqual(composer.singleCalls.count, 0)
        XCTAssertEqual(result.outputURLs.count, 1)
    }

    func test_composerError_becomesAppErrorExportFailed() async {
        let composer = StubComposer()
        composer.shouldFail = NSError(domain: "t", code: 1)
        let job = ExportJob(composer: composer)
        let req = makeRequest(layout: .gridCombined(angles: [.front, .back, .leftRepeater, .rightRepeater]))
        do {
            _ = try await job.run(req)
            XCTFail("expected throw")
        } catch AppError.exportFailed {
            // ok
        } catch {
            XCTFail("expected AppError.exportFailed, got \(error)")
        }
    }

    func test_invalidLayout_throwsBeforeCallingComposer() async {
        let composer = StubComposer()
        let job = ExportJob(composer: composer)
        let req = makeRequest(layout: .singlesPerAngle(angles: []))
        do {
            _ = try await job.run(req)
            XCTFail("expected throw")
        } catch AppError.exportFailed {
            XCTAssertEqual(composer.singleCalls.count, 0)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement ExportJob**

Path: `TeslaCamViewer/Domain/ExportJob.swift`

```swift
import Foundation
import Observation

public struct ExportResult {
    public let outputURLs: [URL]
}

@Observable
public final class ExportJob {
    public private(set) var isRunning = false
    public private(set) var progress: Double = 0

    @ObservationIgnored private let composer: ComposerProtocol
    @ObservationIgnored private let tempDir: URL

    public init(composer: ComposerProtocol, tempDir: URL = FileManager.default.temporaryDirectory) {
        self.composer = composer
        self.tempDir = tempDir
    }

    @discardableResult
    public func run(_ request: ExportRequest) async throws -> ExportResult {
        guard request.layout.isValid else {
            throw AppError.exportFailed(underlying: NSError(
                domain: "ExportJob", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Invalid export layout"]
            ))
        }
        isRunning = true
        defer { isRunning = false; progress = 0 }

        var outs: [URL] = []

        do {
            switch request.layout {
            case .singlesPerAngle(let angles):
                for (i, angle) in angles.enumerated() {
                    let url = tempDir.appendingPathComponent("tcv-\(UUID().uuidString)-\(angle.fileSuffix).mp4")
                    try await composer.exportSingleAngle(angle, request: request, to: url)
                    outs.append(url)
                    progress = Double(i + 1) / Double(angles.count)
                }

            case .gridCombined:
                let url = tempDir.appendingPathComponent("tcv-\(UUID().uuidString)-grid.mp4")
                try await composer.exportGrid(request: request, to: url)
                outs.append(url)
                progress = 1.0
            }
        } catch let e as AppError {
            throw e
        } catch {
            throw AppError.exportFailed(underlying: error)
        }

        return ExportResult(outputURLs: outs)
    }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(domain): add ExportJob orchestrating Composer runs"
```

---

## Task 13: EventList Feature

**Dependencies:** T9

**Files:**
- Create: `TeslaCamViewer/Features/EventList/EventListView.swift`
- Create: `TeslaCamViewer/Features/EventList/EventRowView.swift`
- Create: `TeslaCamViewer/Features/EventList/EventListViewModel.swift`
- Test: via SwiftUI Preview (no unit test — wire-up is trivial; UI test in T16 if added)

- [ ] **Step 1: Build the row view first**

Path: `TeslaCamViewer/Features/EventList/EventRowView.swift`

```swift
import SwiftUI

struct EventRowView: View {
    let event: TeslaEvent

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(timeString).font(.subheadline).foregroundStyle(.primary)
                if let meta = event.eventMetadata {
                    if let reason = meta.reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    if let city = meta.city { Text(city).font(.caption).foregroundStyle(.secondary) }
                }
                Text("\(event.availableAngles.count) 路 · \(segmentsLabel)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var thumbnail: some View {
        Group {
            if let url = event.thumbnailURL,
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                Image(uiImage: img).resizable().aspectRatio(16/9, contentMode: .fit)
            } else {
                Color.gray.opacity(0.2)
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(Image(systemName: "video").foregroundStyle(.secondary))
            }
        }
        .frame(width: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: event.startTime)
    }

    private var segmentsLabel: String {
        let secs = event.totalDuration.seconds
        if secs < 60 { return "\(Int(secs))s" }
        let m = Int(secs) / 60, s = Int(secs) % 60
        return "\(m)m\(s > 0 ? "\(s)s" : "")"
    }
}
```

- [ ] **Step 2: Build the ViewModel**

Path: `TeslaCamViewer/Features/EventList/EventListViewModel.swift`

```swift
import Observation
import Foundation

@Observable
final class EventListViewModel {
    let library: LibraryStore
    init(library: LibraryStore) { self.library = library }

    func events(for type: EventType) -> [TeslaEvent] {
        switch type {
        case .saved:  return library.savedEvents
        case .sentry: return library.sentryEvents
        case .recent: return library.recentEvents
        }
    }
}
```

- [ ] **Step 3: Build the TabView**

Path: `TeslaCamViewer/Features/EventList/EventListView.swift`

```swift
import SwiftUI

struct EventListView: View {
    @Bindable var viewModel: EventListViewModel
    let onSelect: (TeslaEvent) -> Void

    @State private var selectedTab: EventType = .saved

    var body: some View {
        TabView(selection: $selectedTab) {
            tabContent(.saved)
                .tabItem { Label("主动保存", systemImage: "square.and.arrow.down") }
                .tag(EventType.saved)
            tabContent(.sentry)
                .tabItem { Label("哨兵", systemImage: "eye") }
                .tag(EventType.sentry)
            tabContent(.recent)
                .tabItem { Label("最近", systemImage: "clock") }
                .tag(EventType.recent)
        }
    }

    @ViewBuilder
    private func tabContent(_ type: EventType) -> some View {
        let events = viewModel.events(for: type)
        if events.isEmpty {
            ContentUnavailableView("暂无事件", systemImage: "tray", description: Text(emptyHint(type)))
        } else {
            List(events) { e in
                Button { onSelect(e) } label: { EventRowView(event: e) }
                    .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func emptyHint(_ t: EventType) -> String {
        switch t {
        case .saved:  return "按喇叭可主动保存片段。"
        case .sentry: return "哨兵模式触发的片段将出现在这里。"
        case .recent: return "行车时的滚动缓冲会显示在这里。"
        }
    }
}
```

- [ ] **Step 4: Run — smoke test builds**

```bash
make build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(ui): add EventList tab view with per-type lists"
```

---

## Task 14: GridPlayer Feature

**Dependencies:** T11

**Files:**
- Create: `TeslaCamViewer/Features/GridPlayer/PlayerLayerView.swift`
- Create: `TeslaCamViewer/Features/GridPlayer/GridPlayerViewModel.swift`
- Create: `TeslaCamViewer/Features/GridPlayer/TrimBarView.swift`
- Create: `TeslaCamViewer/Features/GridPlayer/GridPlayerView.swift`

- [ ] **Step 1: Build PlayerLayerView (UIViewRepresentable)**

Path: `TeslaCamViewer/Features/GridPlayer/PlayerLayerView.swift`

```swift
import SwiftUI
import AVFoundation
import UIKit

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerLayerUIView {
        PlayerLayerUIView()
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.setPlayer(player)
    }

    final class PlayerLayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspect
            backgroundColor = .black
        }
        required init?(coder: NSCoder) { fatalError() }

        func setPlayer(_ p: AVPlayer?) {
            if playerLayer.player !== p { playerLayer.player = p }
        }
    }
}

struct MissingAngleView: View {
    let angleName: String
    var body: some View {
        ZStack {
            Color.black
            VStack {
                Image(systemName: "video.slash").foregroundStyle(.white.opacity(0.6))
                Text(angleName).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
```

- [ ] **Step 2: Build GridPlayerViewModel**

Path: `TeslaCamViewer/Features/GridPlayer/GridPlayerViewModel.swift`

```swift
import Foundation
import Observation
import CoreMedia
import AVFoundation

@Observable
final class GridPlayerViewModel {
    let event: TeslaEvent
    let playback: PlaybackController
    var gridAngles: [CameraAngle]       // 4 slots; may contain angles not in availableAngles → show MissingAngleView

    init(event: TeslaEvent, playback: PlaybackController) {
        self.event = event
        self.playback = playback
        self.gridAngles = CameraAngle.defaultGrid
    }

    func load() async {
        try? await playback.load(event: event, angles: gridAngles)
    }

    func setAngle(_ angle: CameraAngle, at index: Int) {
        guard (0..<gridAngles.count).contains(index) else { return }
        gridAngles[index] = angle
        Task { await load() }
    }
}
```

- [ ] **Step 3: Build TrimBarView**

Path: `TeslaCamViewer/Features/GridPlayer/TrimBarView.swift`

```swift
import SwiftUI
import CoreMedia

struct TrimBarView: View {
    let totalDuration: CMTime
    @Binding var trimStart: CMTime
    @Binding var trimEnd: CMTime
    let currentTime: CMTime
    let onScrub: (CMTime) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let total = max(totalDuration.seconds, 0.001)
            let startX = CGFloat(trimStart.seconds / total) * w
            let endX   = CGFloat(trimEnd.seconds   / total) * w
            let currX  = CGFloat(currentTime.seconds / total) * w

            ZStack(alignment: .topLeading) {
                // track
                Rectangle().fill(.gray.opacity(0.3)).frame(height: 6).offset(y: 28)
                // selected range
                Rectangle().fill(.blue.opacity(0.6))
                    .frame(width: max(0, endX - startX), height: 6)
                    .offset(x: startX, y: 28)
                // playhead
                Rectangle().fill(.white).frame(width: 2, height: 40).offset(x: currX)
                // left handle
                handleCircle.offset(x: startX - 10, y: 20)
                    .gesture(DragGesture().onChanged { g in
                        let clamped = min(max(0, g.location.x), endX)
                        trimStart = CMTime(seconds: Double(clamped / w) * total, preferredTimescale: 600)
                        onScrub(trimStart)
                    })
                // right handle
                handleCircle.offset(x: endX - 10, y: 20)
                    .gesture(DragGesture().onChanged { g in
                        let clamped = max(min(w, g.location.x), startX)
                        trimEnd = CMTime(seconds: Double(clamped / w) * total, preferredTimescale: 600)
                        onScrub(trimEnd)
                    })
            }
            .frame(height: 60)
        }
        .frame(height: 60)
    }

    private var handleCircle: some View {
        Circle().fill(.white).frame(width: 20, height: 20)
            .overlay(Circle().stroke(.blue, lineWidth: 2))
            .shadow(radius: 2)
    }
}
```

- [ ] **Step 4: Build GridPlayerView**

Path: `TeslaCamViewer/Features/GridPlayer/GridPlayerView.swift`

```swift
import SwiftUI
import CoreMedia

struct GridPlayerView: View {
    @Bindable var viewModel: GridPlayerViewModel
    let onExportTap: () -> Void

    @State private var trimStart: CMTime = .zero
    @State private var trimEnd: CMTime   = CMTime(seconds: 1, preferredTimescale: 600)

    var body: some View {
        VStack(spacing: 8) {
            gridView
            controls
            TrimBarView(
                totalDuration: viewModel.playback.totalDuration,
                trimStart: $trimStart,
                trimEnd: $trimEnd,
                currentTime: viewModel.playback.currentTime,
                onScrub: { t in
                    Task { try? await viewModel.playback.seek(to: t) }
                    viewModel.playback.setTrim(start: trimStart, end: trimEnd)
                }
            )
            .padding(.horizontal)

            Button("导出", action: onExportTap)
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 8)
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.playback.totalDuration) { _, newTotal in
            trimStart = .zero
            trimEnd = newTotal
        }
    }

    private var gridView: some View {
        GeometryReader { geo in
            let cellW = geo.size.width / 2
            let cellH = geo.size.height / 2
            ZStack {
                ForEach(Array(viewModel.gridAngles.enumerated()), id: \.offset) { idx, angle in
                    cell(for: angle, index: idx, size: CGSize(width: cellW, height: cellH))
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .background(.black)
    }

    @ViewBuilder
    private func cell(for angle: CameraAngle, index: Int, size: CGSize) -> some View {
        let row = index / 2, col = index % 2
        Group {
            if viewModel.event.availableAngles.contains(angle),
               let player = viewModel.playback.player(for: angle) {
                PlayerLayerView(player: player)
            } else {
                MissingAngleView(angleName: angleLabel(angle))
            }
        }
        .frame(width: size.width, height: size.height)
        .position(x: CGFloat(col) * size.width + size.width / 2,
                  y: CGFloat(row) * size.height + size.height / 2)
        .overlay(alignment: .topLeading) {
            Text(angleLabel(angle))
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.black.opacity(0.6)).foregroundStyle(.white)
                .cornerRadius(4)
                .padding(4)
                .position(x: CGFloat(col) * size.width + 40,
                          y: CGFloat(row) * size.height + 14)
        }
    }

    private var controls: some View {
        HStack(spacing: 24) {
            Button { Task { try? await viewModel.playback.seek(to: CMTime(seconds: max(0, viewModel.playback.currentTime.seconds - 5), preferredTimescale: 600)) } } label: {
                Image(systemName: "gobackward.5")
            }
            Button {
                if viewModel.playback.isPlaying { viewModel.playback.pause() } else { viewModel.playback.play() }
            } label: {
                Image(systemName: viewModel.playback.isPlaying ? "pause.fill" : "play.fill").font(.title)
            }
            Button { Task { try? await viewModel.playback.seek(to: CMTime(seconds: min(viewModel.playback.totalDuration.seconds, viewModel.playback.currentTime.seconds + 5), preferredTimescale: 600)) } } label: {
                Image(systemName: "goforward.5")
            }
        }
    }

    private func angleLabel(_ a: CameraAngle) -> String {
        switch a {
        case .front: return "前"
        case .back: return "后"
        case .leftRepeater: return "左后"
        case .rightRepeater: return "右后"
        case .leftPillar: return "左柱"
        case .rightPillar: return "右柱"
        }
    }
}
```

- [ ] **Step 5: Build check**

Same `xcodebuild build` command as before. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(ui): add GridPlayer with 4-up AVPlayerLayers and TrimBar"
```

---

## Task 15: GridConfig + ExportSheet Features

**Dependencies:** T12, T14

**Files:**
- Create: `TeslaCamViewer/Features/GridConfig/GridConfigSheet.swift`
- Create: `TeslaCamViewer/Features/ExportSheet/ExportSheetViewModel.swift`
- Create: `TeslaCamViewer/Features/ExportSheet/ExportSheetView.swift`
- Create: `TeslaCamViewer/Features/ExportSheet/PhotoLibrarySaver.swift`

### 15a. GridConfigSheet

- [ ] **Step 1: Write view**

Path: `TeslaCamViewer/Features/GridConfig/GridConfigSheet.swift`

```swift
import SwiftUI

struct GridConfigSheet: View {
    let available: Set<CameraAngle>
    @Binding var current: [CameraAngle]
    let onDismiss: () -> Void

    private let allAngles = CameraAngle.allCases

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<4, id: \.self) { idx in
                    Section(header: Text("格 \(idx + 1)")) {
                        ForEach(allAngles, id: \.self) { angle in
                            HStack {
                                Text(label(angle))
                                    .foregroundStyle(available.contains(angle) ? .primary : .secondary)
                                Spacer()
                                if current.indices.contains(idx), current[idx] == angle {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard current.indices.contains(idx) else { return }
                                current[idx] = angle
                            }
                        }
                    }
                }
            }
            .navigationTitle("网格配置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: onDismiss) } }
        }
    }

    private func label(_ a: CameraAngle) -> String {
        switch a {
        case .front: return "前 Front"
        case .back: return "后 Back"
        case .leftRepeater: return "左后视镜"
        case .rightRepeater: return "右后视镜"
        case .leftPillar: return "左 B 柱"
        case .rightPillar: return "右 B 柱"
        }
    }
}
```

### 15b. PhotoLibrarySaver

- [ ] **Step 2: Implement Photo library helper**

Path: `TeslaCamViewer/Features/ExportSheet/PhotoLibrarySaver.swift`

```swift
import Foundation
import Photos

enum PhotoLibrarySaver {
    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw AppError.photoLibraryDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetCreationRequest.forAsset()
                .addResource(with: .video, fileURL: url, options: nil)
        }
    }
}
```

### 15c. ExportSheetViewModel

- [ ] **Step 3: Implement ViewModel**

Path: `TeslaCamViewer/Features/ExportSheet/ExportSheetViewModel.swift`

```swift
import Foundation
import Observation
import CoreMedia

@Observable
final class ExportSheetViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case grid, singles
        var id: String { rawValue }
        var label: String { self == .grid ? "四宫格合成" : "多视角独立" }
    }

    var mode: Mode = .grid
    var selectedAngles: Set<CameraAngle>
    var watermarkPosition: ExportRequest.WatermarkPosition
    var isRunning = false
    var resultURLs: [URL] = []
    var error: AppError?

    @ObservationIgnored let event: TeslaEvent
    @ObservationIgnored let gridAngles: [CameraAngle]
    @ObservationIgnored let trim: TrimRange
    @ObservationIgnored private let exportJob: ExportJob

    init(
        event: TeslaEvent,
        gridAngles: [CameraAngle],
        trim: TrimRange,
        defaultWatermark: ExportRequest.WatermarkPosition,
        exportJob: ExportJob
    ) {
        self.event = event
        self.gridAngles = gridAngles
        self.trim = trim
        self.watermarkPosition = defaultWatermark
        self.selectedAngles = Set(gridAngles)
        self.exportJob = exportJob
    }

    func run() async {
        isRunning = true
        defer { isRunning = false }
        let layout: ExportRequest.Layout = switch mode {
        case .grid:    .gridCombined(angles: gridAngles)
        case .singles: .singlesPerAngle(angles: Array(selectedAngles))
        }
        let request = ExportRequest(event: event, layout: layout, range: trim, watermarkPosition: watermarkPosition)
        do {
            let result = try await exportJob.run(request)
            resultURLs = result.outputURLs
            // Attempt to save each to Photos; ignore permission failure and fall through to share.
            for u in resultURLs {
                try? await PhotoLibrarySaver.save(u)
            }
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .exportFailed(underlying: error)
        }
    }
}
```

### 15d. ExportSheetView

- [ ] **Step 4: Implement View**

Path: `TeslaCamViewer/Features/ExportSheet/ExportSheetView.swift`

```swift
import SwiftUI

struct ExportSheetView: View {
    @Bindable var viewModel: ExportSheetViewModel
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("布局") {
                    Picker("布局", selection: $viewModel.mode) {
                        ForEach(ExportSheetViewModel.Mode.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                }
                if viewModel.mode == .singles {
                    Section("选择视角") {
                        ForEach(CameraAngle.allCases, id: \.self) { a in
                            Toggle(label(a), isOn: Binding(
                                get: { viewModel.selectedAngles.contains(a) },
                                set: { on in
                                    if on { viewModel.selectedAngles.insert(a) }
                                    else  { viewModel.selectedAngles.remove(a) }
                                })
                            )
                            .disabled(!viewModel.event.availableAngles.contains(a))
                        }
                    }
                }
                Section("水印") {
                    Picker("位置", selection: $viewModel.watermarkPosition) {
                        Text("左下").tag(ExportRequest.WatermarkPosition.bottomLeft)
                        Text("右下").tag(ExportRequest.WatermarkPosition.bottomRight)
                        Text("左上").tag(ExportRequest.WatermarkPosition.topLeft)
                        Text("右上").tag(ExportRequest.WatermarkPosition.topRight)
                    }
                }
                if viewModel.isRunning {
                    ProgressView("导出中…")
                } else if !viewModel.resultURLs.isEmpty {
                    Section("完成") {
                        Text("已保存到相册（若有权限）。点击下方按钮再分享一次。")
                        Button("分享") { present(urls: viewModel.resultURLs) }
                    }
                }
                if let err = viewModel.error {
                    Section { Text(err.errorDescription ?? "导出失败").foregroundStyle(.red) }
                }
            }
            .navigationTitle("导出")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭", action: onDismiss) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始导出") { Task { await viewModel.run() } }
                        .disabled(viewModel.isRunning)
                }
            }
        }
    }

    private func label(_ a: CameraAngle) -> String {
        switch a {
        case .front: return "前 Front"
        case .back: return "后 Back"
        case .leftRepeater: return "左后视镜"
        case .rightRepeater: return "右后视镜"
        case .leftPillar: return "左 B 柱"
        case .rightPillar: return "右 B 柱"
        }
    }

    private func present(urls: [URL]) {
        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        let vc = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        var presenter = root
        while let p = presenter.presentedViewController { presenter = p }
        presenter.present(vc, animated: true)
        #endif
    }
}
```

- [ ] **Step 5: Build check**

Same `xcodebuild build`. Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(ui): add ExportSheet and GridConfig views"
```

---

## Task 16: Root + FolderPicker + Settings + Wire-up

**Dependencies:** T9, T10, T13, T14, T15

**Files:**
- Create: `TeslaCamViewer/App/AppDependencies.swift`
- Create: `TeslaCamViewer/Features/Root/RootView.swift`
- Create: `TeslaCamViewer/Features/FolderPicker/FolderPickerView.swift`
- Create: `TeslaCamViewer/Features/Settings/SettingsView.swift`
- Create: `TeslaCamViewer/UI/ErrorBanner.swift`
- Modify: `TeslaCamViewer/App/TeslaCamViewerApp.swift`

- [ ] **Step 1: Implement AppDependencies (DI)**

Path: `TeslaCamViewer/App/AppDependencies.swift`

```swift
import Foundation

@MainActor
final class AppDependencies {
    let settings: SettingsStore
    let bookmarks: BookmarkStoreProtocol
    let scanner: ScannerProtocol
    let library: LibraryStore
    let playback: PlaybackController
    let exportJob: ExportJob

    init() {
        self.settings = SettingsStore()
        self.bookmarks = BookmarkStore()
        self.scanner = TeslaCamScanner()
        self.library = LibraryStore(scanner: scanner, settings: settings)
        self.playback = PlaybackController(player: MultiAVPlayer())
        self.exportJob = ExportJob(composer: AVComposer())
    }
}
```

- [ ] **Step 2: Implement FolderPickerView**

Path: `TeslaCamViewer/Features/FolderPicker/FolderPickerView.swift`

```swift
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FolderPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        vc.allowsMultipleSelection = false
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coord { Coord(onPick: onPick) }

    final class Coord: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let u = urls.first { onPick(u) }
        }
    }
}
```

- [ ] **Step 3: Implement SettingsView**

Path: `TeslaCamViewer/Features/Settings/SettingsView.swift`

```swift
import SwiftUI

struct SettingsView: View {
    @Bindable var settingsStore: SettingsStore
    let onReselectFolder: () -> Void

    var body: some View {
        Form {
            Section(header: Text("Recent 分块间隔"),
                    footer: Text("超过此间隔的分钟文件会被切为新事件。")) {
                HStack {
                    Text("\(settingsStore.settings.recentGapThresholdSeconds / 60) 分钟")
                        .monospacedDigit()
                    Slider(
                        value: Binding(
                            get: { Double(settingsStore.settings.recentGapThresholdSeconds) },
                            set: { settingsStore.settings.recentGapThresholdSeconds = Int($0) }
                        ),
                        in: Double(AppSettings.minRecentGapSeconds) ... Double(AppSettings.maxRecentGapSeconds),
                        step: 60
                    )
                }
            }
            Section("水印默认位置") {
                Picker("默认位置", selection: $settingsStore.settings.defaultWatermarkPosition) {
                    Text("左下").tag(ExportRequest.WatermarkPosition.bottomLeft)
                    Text("右下").tag(ExportRequest.WatermarkPosition.bottomRight)
                    Text("左上").tag(ExportRequest.WatermarkPosition.topLeft)
                    Text("右上").tag(ExportRequest.WatermarkPosition.topRight)
                }
            }
            Section("TeslaCam 文件夹") {
                Button("重新选择文件夹", role: .destructive, action: onReselectFolder)
            }
        }
        .navigationTitle("设置")
    }
}
```

- [ ] **Step 4: Implement ErrorBanner**

Path: `TeslaCamViewer/UI/ErrorBanner.swift`

```swift
import SwiftUI

struct ErrorBanner: View {
    let error: AppError
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(error.errorDescription ?? "").font(.subheadline).bold()
            if let hint = error.recoverySuggestion {
                Text(hint).font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.15))
        .foregroundStyle(.red)
        .cornerRadius(8)
        .padding(.horizontal)
    }
}
```

- [ ] **Step 5: Implement RootView**

Path: `TeslaCamViewer/Features/Root/RootView.swift`

```swift
import SwiftUI

struct RootView: View {
    let deps: AppDependencies

    @State private var scopedRoot: URL?
    @State private var isPickingFolder = false
    @State private var error: AppError?
    @State private var selected: TeslaEvent?
    @State private var showExport = false
    @State private var gridVM: GridPlayerViewModel?
    @State private var exportVM: ExportSheetViewModel?
    @State private var showSettings = false
    @State private var showGridConfig = false

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "gear") }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        SettingsView(settingsStore: deps.settings, onReselectFolder: reselectFolder)
                    }
                }
                .sheet(isPresented: $isPickingFolder) {
                    FolderPickerView { url in
                        isPickingFolder = false
                        Task { await onPickedFolder(url) }
                    }
                }
                .navigationDestination(item: $selected) { event in
                    gridScreen(event: event)
                }
        }
        .task { await bootstrap() }
    }

    @ViewBuilder
    private var content: some View {
        if let err = error {
            VStack {
                ErrorBanner(error: err)
                Button("选择 TeslaCam 文件夹") { isPickingFolder = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if scopedRoot == nil {
            VStack(spacing: 16) {
                Image(systemName: "externaldrive.badge.plus").font(.largeTitle)
                Text("请选择 TeslaCam 文件夹开始").font(.title3)
                Button("选择文件夹") { isPickingFolder = true }
                    .buttonStyle(.borderedProminent)
            }.padding()
        } else {
            let vm = EventListViewModel(library: deps.library)
            EventListView(viewModel: vm, onSelect: { selected = $0 })
                .navigationTitle("TeslaCam")
        }
    }

    @ViewBuilder
    private func gridScreen(event: TeslaEvent) -> some View {
        VStack {
            if let gvm = gridVM {
                GridPlayerView(viewModel: gvm, onExportTap: {
                    exportVM = ExportSheetViewModel(
                        event: event,
                        gridAngles: gvm.gridAngles,
                        trim: gvm.playback.trim,
                        defaultWatermark: deps.settings.settings.defaultWatermarkPosition,
                        exportJob: deps.exportJob
                    )
                    showExport = true
                })
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showGridConfig = true } label: { Image(systemName: "square.grid.2x2") }
                    }
                }
                .sheet(isPresented: $showGridConfig) {
                    GridConfigSheet(
                        available: event.availableAngles,
                        current: Binding(get: { gvm.gridAngles }, set: { gvm.gridAngles = $0 }),
                        onDismiss: { showGridConfig = false }
                    )
                }
                .sheet(isPresented: $showExport) {
                    if let evm = exportVM {
                        ExportSheetView(viewModel: evm, onDismiss: { showExport = false })
                    }
                }
            } else {
                ProgressView().task {
                    gridVM = GridPlayerViewModel(event: event, playback: deps.playback)
                }
            }
        }
    }

    // MARK: - actions

    private func bootstrap() async {
        guard deps.bookmarks.hasBookmark else { return }
        do {
            let url = try deps.bookmarks.resolve()
            await onPickedFolder(url, alreadyBookmarked: true)
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .bookmarkStale
        }
    }

    private func onPickedFolder(_ url: URL, alreadyBookmarked: Bool = false) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if !alreadyBookmarked && !scoped { /* nothing */ } }
        do {
            if !alreadyBookmarked { try deps.bookmarks.save(url: url) }
            try await deps.library.load(root: url)
            scopedRoot = url
            error = nil
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .notTeslaCamFolder
        }
    }

    private func reselectFolder() {
        deps.bookmarks.clear()
        scopedRoot = nil
        showSettings = false
        isPickingFolder = true
    }
}
```

- [ ] **Step 6: Wire into App**

Replace `TeslaCamViewer/App/TeslaCamViewerApp.swift`:

```swift
import SwiftUI

@main
struct TeslaCamViewerApp: App {
    @State private var deps = AppDependencies()

    var body: some Scene {
        WindowGroup { RootView(deps: deps) }
    }
}
```

- [ ] **Step 7: Build + run a full test sweep**

```bash
make test 2>&1 | tail -20
```

Expected: xcbeautify reports `Test Succeeded` with all integration + unit tests passing.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(ui): wire Root, FolderPicker, Settings, ErrorBanner into full app flow"
```

---

## Task 17: Simulator Install + Launch Verification

**Dependencies:** T16

**Files:**
- Verify: `TeslaCamViewer/Info.plist` was regenerated by `make generate` with the Photo-library keys from `project.yml` (T1 already wrote them)

**Why:** Now that the app is feature-complete, exercise the full install-launch-quit loop from the CLI. We don't need to touch the project in Xcode; `make run` drives the simulator end-to-end.

- [ ] **Step 1: Verify the generated Info.plist has the expected keys**

```bash
/usr/libexec/PlistBuddy -c "Print :NSPhotoLibraryAddUsageDescription" TeslaCamViewer/Info.plist
/usr/libexec/PlistBuddy -c "Print :NSPhotoLibraryUsageDescription"    TeslaCamViewer/Info.plist
```

Expected for both: the string `用于把导出的行车记录仪视频保存到相册。`.

If either prints `Does Not Exist` the project.yml was not applied — run `make generate` again.

- [ ] **Step 2: Install the built app on the simulator**

```bash
make install
```

Expected: the Simulator.app opens showing the booted iPhone 17, and the app icon appears on its Home screen. (xcbeautify output ends with `Build Succeeded`, then `simctl install booted ...` prints no output on success.)

- [ ] **Step 3: Launch the app with log streaming**

```bash
make launch
```

Expected: The app appears on screen, `Text("TeslaCamViewer")` placeholder (if testing a fresh build) or the real RootView (after T16) is visible. `--console-pty` streams `NSLog` / `os_log` output to the terminal. `Ctrl-C` detaches.

- [ ] **Step 4: Drop a fixture folder into the simulator for interactive test**

```bash
# Copy one fixture to the shared simulator location
FIXTURE="TeslaCamViewerTests/Fixtures/fixture-6cam-saved/TeslaCam"
DEVICE_ID=$(xcrun simctl list devices booted | awk -F'[()]' '/iPhone/ {print $2; exit}')
SIM_SHARED="$HOME/Library/Developer/CoreSimulator/Devices/$DEVICE_ID/data/Media/DCIM-ImportedTeslaCam"
mkdir -p "$SIM_SHARED"
cp -R "$FIXTURE" "$SIM_SHARED/"
xcrun simctl openurl booted "file://$SIM_SHARED"
echo "In the simulator's Files app, browse to the shared volume to pick TeslaCam."
```

(This step doesn't assert automatically — it prepares the environment so you can tap through the app and verify flows.)

- [ ] **Step 5: Manual checklist inside the simulator**

- [ ] Tap "选择文件夹" → Files app → navigate to the fixture's `TeslaCam` folder → tap to select
- [ ] Saved tab shows one event (2024-07-15); thumbnail and time visible
- [ ] Switch to 哨兵 and 最近 tabs → both empty (expected for this fixture)
- [ ] Tap the Saved event → grid plays with 4 visible angles, both front/back and both repeaters
- [ ] Drag left handle → range highlight shrinks from left
- [ ] Drag right handle → range highlight shrinks from right
- [ ] Tap 导出 → sheet opens, "四宫格合成" is selected → tap "开始导出"
- [ ] First time: permission dialog for Photos → allow → export succeeds → Photos app contains the grid MP4
- [ ] **Watermark verification (device only — simulator skips this path):** Play back the exported MP4 and verify the timestamp watermark appears in the bottom-left corner advancing each second, and for the grid export verify each cell has its angle label ("前 Front", "后 Back", etc.). The `AVComposer` build-guards watermark attachment with `#if !targetEnvironment(simulator)` because `AVVideoCompositionCoreAnimationTool` hits an XPC sandbox violation on the iOS simulator; this is Apple's limitation, not a code defect.

- [ ] **Step 6: Commit if any project.yml tweaks were required**

```bash
git diff --quiet || git commit -am "chore: finalize simulator-install flow"
```

---

## Task 18: End-to-End Smoke

**Dependencies:** T17

- [ ] **Step 1: Run full test suite**

```bash
make test 2>&1 | tail -30
```

Expected: xcbeautify prints `Test Succeeded`. Coverage data is gathered automatically (see `gatherCoverageData: true` in `project.yml`). To view:

```bash
xcrun xccov view --report \
  "$(find build/Logs/Test -name '*.xcresult' | head -1)" 2>&1 | head -40
```

- [ ] **Step 2: Physical-device smoke (manual checklist)**

On a real iPhone/iPad with a Tesla USB-C adapter and a real TeslaCam drive (if accessible):

- [ ] Launch app
- [ ] Tap "选择文件夹" → navigate Files to the USB drive → pick `TeslaCam`
- [ ] Events list populates; switch between 主动保存 / 哨兵 / 最近 tabs
- [ ] Open Settings → slide Recent threshold → watch Recent tab re-chunk live
- [ ] Open a Saved event → grid plays 4 angles in sync
- [ ] Drag trim handles → selected range highlights
- [ ] Tap 导出 → choose 四宫格 → "开始导出" → completes and is added to Photos
- [ ] Repeat export → choose 多视角独立 → pick 2 angles → 2 files produced
- [ ] Pull USB adapter → relaunch app → bookmark stale error offers reselect

- [ ] **Step 3: Commit final touches if any**

```bash
git status
# Commit any readme / polish tweaks noticed during smoke testing
```

---

## Appendix: Common Command Reference

All commands assume `cwd = /Users/shanehou/Developer/Projects/TeslaCamViewer`. Targets come from the top-level `Makefile` created in T1.

| Task | Command |
|---|---|
| Regenerate Xcode project | `make generate` |
| Build only | `make build` |
| All tests | `make test` |
| One test class | `make test-only TESTS=CameraAngleTests` |
| One test method | `make test-only TESTS=CameraAngleTests/test_fileSuffix_mapsEachAngleToTeslaNaming` |
| Boot simulator | `make boot` |
| Install .app onto booted simulator | `make install` |
| Launch (streams logs) | `make launch` |
| Full simulator round-trip | `make run` |
| List available simulators | `xcrun simctl list devices available \| grep iPhone` |
| Clean build artefacts | `make clean` |

If `iPhone 17` isn't available in `xcrun simctl list devices available`, edit the `SIMULATOR` variable at the top of the `Makefile` to whatever is.

---

## Self-Review Notes (addressed inline)

During writing this plan, the following pitfalls were caught and fixed inline:

1. **LibraryStore task loop** — first draft leaked a `@MainActor` Task that never re-registered observation tracking; fixed by re-calling `withObservationTracking` each iteration.
2. **Grid composition transform** — first draft lost layer transforms when inserting the trimmed range; fixed by capturing per-layer transforms and re-applying them on the trimmed tracks.
3. **TrimRange invariant** — "end exclusive" vs "end inclusive" — fixed to treat `end` as the inclusive final time, and collapse with ≥ 1s minimum duration.
4. **Fixture file discovery** — use folder reference (blue folder) in Xcode so `Bundle.url(forResource:"Fixtures/...")` resolves at test time.
5. **Export file type** — confirmed `.mp4` output + `AVAssetExportPresetHighestQuality` produces H.264 compatible with Photos import.
