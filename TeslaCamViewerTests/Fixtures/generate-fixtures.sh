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
    # Build event.json. The date string "2024-07-15_03-22-15" needs the underscore → 'T' substitution.
    JSON_TS="${clip/_/T}"
    printf '%s' "{\"timestamp\":\"${JSON_TS}\",\"reason\":\"sentry_aware_object_detection\"}" > "$EV/event.json"
done

# --- fixture-corrupted: broken JSON + missing angle + stray files
EV="fixture-corrupted/TeslaCam/SavedClips/2024-07-17_09-00-00"
mkdir -p "$EV"
# Only 2 angles (back/right_pillar/etc. missing)
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
    printf -v MM '%02d' "$m"
    MIN_BASE="2024-07-19_08-${MM}-00"
    for a in front back left_repeater right_repeater; do
        cp "$TMP_MP4" "$REC/${MIN_BASE}-${a}.mp4"
    done
done

rm -f "$TMP_MP4"
echo "Fixtures generated under $HERE"
