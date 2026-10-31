#!/bin/sh
# Inject prepared game data into a binary-only WMMT IPA, for signing on device
# afterwards (ksign etc.). The game data must not live in a public repo, so a
# CI-built IPA carries no data; this script puts it in locally.
#
# Usage: ./inject_data.sh <ipa> [data-dir] [original-data-dir]
#   data-dir:          default data/ — the tree the pack tools produce
#                      (tools/gen_from_original.sh, tools/stage/pack_*.py,
#                      prepare_sound.sh, prepare_bgm.sh, prepare_movie.sh).
#   original-data-dir: optional "Wangan Midnight Maximum Tune 3DX+ (Japan)"
#                      folder, used only for rtmovie/table+trail and
#                      carconfig/ytConfig*.txt when they are not in data/.
#
# Output: <ipa-basename>-withdata.ipa next to the input IPA. The input IPA is
# left untouched. tokyo.wpk must end up in the bundle: the app uses its
# presence to decide the data lives in the bundle, and falls back to the
# jailbreak-only /var/mobile/Media/wmmt path without it.
set -e
IPA="$1"
DATA="${2:-data}"
ORIG="$3"
[ -n "$IPA" ] || { echo "usage: $0 <ipa> [data-dir] [original-data-dir]" >&2; exit 1; }
[ -f "$IPA" ] || { echo "no such file: $IPA" >&2; exit 1; }
case "$IPA" in
  /*) OUT="${IPA%.ipa}-withdata.ipa" ;;
  *)  OUT="$(pwd)/${IPA%.ipa}-withdata.ipa" ;;
esac
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM
unzip -q "$IPA" -d "$WORK"
APP=$(ls -d "$WORK"/Payload/*.app | head -1)
[ -n "$APP" ] || { echo "no .app found inside $IPA" >&2; exit 1; }
for f in tokyo.wpk tokyo_night.wpk sky.wpk sky_night.wpk arrows.wpk arrows_night.wpk arrows.names \
         lights.wpk lights.bin neon.wpk fd3s.wpk hud.bin navi.bin meters.bin phys.img menu.bin minicourse.wpk intro.mp4 playdemo.mp4 tutorial.mp4; do
  if [ -f "$DATA/$f" ]; then cp "$DATA/$f" "$APP/"; fi
done
for c in oosaka hakone nagoya fukuoka; do
  for f in "$DATA/$c.wpk" "$DATA/${c}_night.wpk" "$DATA/sky_$c.wpk" "$DATA/sky_${c}_night.wpk" "$DATA/arrows_$c.wpk" \
           "$DATA/arrows_${c}_night.wpk" "$DATA/arrows_$c.names" "$DATA/lights_$c.bin" "$DATA/navi_$c.bin"; do
    if [ -f "$f" ]; then cp "$f" "$APP/"; fi
  done
done
mkdir -p "$APP/traffic" "$APP/carconfig" "$APP/cars" "$APP/sound/bgm" "$APP/sound/engine"
if [ -d "$DATA/traffic" ]; then cp "$DATA/traffic/"*.wpk "$APP/traffic/" 2>/dev/null || true; fi
if [ -d "$DATA/carconfig" ]; then cp "$DATA/carconfig/"*.txt "$APP/carconfig/" 2>/dev/null || true; fi
if [ -d "$DATA/cars" ]; then cp "$DATA/cars/"* "$APP/cars/" 2>/dev/null || true; fi
if [ -d "$DATA/chara" ]; then mkdir -p "$APP/chara" && cp "$DATA/chara/"*.wpk "$APP/chara/" 2>/dev/null || true; { cp "$DATA/chara/"*.ao "$APP/chara/" 2>/dev/null || true; }; fi
if [ -d "$DATA/wheels" ]; then mkdir -p "$APP/wheels" && cp "$DATA/wheels/"*.wpk "$APP/wheels/" 2>/dev/null || true; fi
if [ -d "$DATA/vinyl" ]; then mkdir -p "$APP/vinyl" && cp "$DATA/vinyl/"*.vpk "$APP/vinyl/" 2>/dev/null || true; fi
if [ -d "$DATA/sound/bgm" ]; then cp "$DATA/sound/bgm/"*.m4a "$APP/sound/bgm/" 2>/dev/null || true; fi
if [ -d "$DATA/sound" ]; then cp "$DATA/sound/"*.wav "$APP/sound/" 2>/dev/null || true; fi
if [ -d "$DATA/sound/engine" ]; then cp "$DATA/sound/engine/"*.wav "$APP/sound/engine/" 2>/dev/null || true; fi
if [ -d "$DATA/rtmovie" ]; then
  mkdir -p "$APP/rtmovie" && cp -R "$DATA/rtmovie/"* "$APP/rtmovie/" 2>/dev/null || true
elif [ -n "$ORIG" ] && [ -d "$ORIG/data/rtmovie" ]; then
  mkdir -p "$APP/rtmovie"
  cp -R "$ORIG/data/rtmovie/table" "$ORIG/data/rtmovie/trail" "$APP/rtmovie/" 2>/dev/null || true
fi
if [ -z "$(ls "$APP/carconfig/"*.txt 2>/dev/null)" ] && [ -n "$ORIG" ] && [ -d "$ORIG/data/carconfig" ]; then
  cp "$ORIG/data/carconfig/"ytConfig*.txt "$APP/carconfig/" 2>/dev/null || true
fi
if [ ! -f "$APP/tokyo.wpk" ]; then
  echo "warning: tokyo.wpk is not in $DATA — the app will look for its data at"
  echo "  /var/mobile/Media/wmmt (jailbreak-only) instead of the bundle and fail to start"
fi
if [ ! -f "$APP/phys.img" ]; then
  echo "warning: phys.img is not in $DATA — run tools/gen_from_original.sh --phys first"
fi
(cd "$WORK" && rm -f "$OUT" && zip -qry -1 "$OUT" Payload)
echo "packed $OUT ($(du -h "$OUT" | cut -f1))"
echo "sign it on device (ksign etc.), then install"
