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
