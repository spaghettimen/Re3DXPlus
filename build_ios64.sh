#!/bin/sh
# Build WMMT.app for arm64 iOS (modern iPhones/iPads) with the system Xcode toolchain.
#
# The arm64 port of build.sh, kept as a separate script so the original armv7/iOS 6
# path is untouched. Differences from build.sh:
#   - -arch arm64 and the modern iphoneos SDK: no theos, no patched iPhoneOS 9.3 SDK.
#   - Deployment target IOS_MIN (default 16.0) instead of 6.0.
#   - The two Objective-C files are manual retain/release, so they get -fno-objc-arc
#     (the original only avoided ARC because iOS 6 had no ARC runtime).
#   - gk_ios.m (GameKit's GKSession, gone from modern SDKs) is replaced by gk.c,
#     the stub the Android build already uses: Bluetooth versus is lost, the UDP
#     network versus in net.c/vs_host.c is untouched.
#   - No ldid: the app is ad-hoc signed, and an on-device signer (ksign etc.)
#     re-signs it on the phone. No GameKit framework is linked.
#   - A minimal LaunchScreen.storyboard is bundled so modern iOS doesn't run the
#     app letterboxed/scaled (see templates/LaunchScreen.storyboard).
#
# Usage: ./build_ios64.sh [ipa]
#   (no arg)  build build64/WMMT.app only.
#   ipa       also pack build64/WMMT3DX-1.0-arm64.ipa. Game data from data/ is
#             included when it has been prepared (same file list as build.sh's
#             ipa step); when data/ is absent or incomplete, a binary-only IPA
#             is packed instead and ./inject_data.sh adds the data afterwards.
#             Game data must never be committed to a public repo; on CI the
#             binary-only IPA is the expected output.
# Env: IOS_MIN (default 16.0).
set -e
cd "$(dirname "$0")"
IOS_MIN="${IOS_MIN:-16.0}"
APP=build64/WMMT.app
rm -rf "$APP" && mkdir -p "$APP" build64/obj
CC="xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=$IOS_MIN"
# the recompiled arcade physics (2.8 MB of generated C) only rebuilds when it changes
if [ ! -f build64/obj/phys_rc.o ] || [ src/phys/phys_rc.c -nt build64/obj/phys_rc.o ]; then
  echo "compiling the arcade physics (takes a minute)..."
  $CC -O2 -ffp-contract=off -DRC_FPT=double -w -c src/phys/phys_rc.c -o build64/obj/phys_rc.o
fi
# the Objective-C files, kept manual retain/release (warnings expected from legacy APIs)
$CC -O2 -std=gnu99 -fno-objc-arc -w -c src/main.m -o build64/obj/main.o
$CC -O2 -std=gnu99 -fno-objc-arc -w -c src/sound_ios.m -o build64/obj/sound_ios.o
$CC -O2 -std=gnu99 -Wall -Wno-unused-function -DRC_FPT=double \
  src/app.c src/render.c src/hud.c src/car.c src/sound.c src/anm.c src/menu.c src/lights.c src/spark.c src/net.c src/vs_host.c src/title.c src/gk.c \
  src/phys/rc_runtime.c build64/obj/phys_rc.o build64/obj/main.o build64/obj/sound_ios.o -o "$APP/WMMT" \
  -framework UIKit -framework Foundation -framework OpenGLES -framework QuartzCore \
  -framework AVFoundation -framework AudioToolbox -framework CoreMedia -framework CoreMotion -lz
cat > "$APP/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>WMMT</string>
  <key>CFBundleIdentifier</key><string>com.wmmt.port</string>
  <key>CFBundleName</key><string>WMMT3DX</string>
  <key>CFBundleDisplayName</key><string>湾岸3DX+携带版</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleIconFiles</key><array>
    <string>Icon-1024.png</string>
    <string>Icon-72.png</string><string>Icon-72@2x.png</string><string>Icon-76.png</string><string>Icon-76@2x.png</string>
    <string>Icon-Small-50.png</string><string>Icon-Small-50@2x.png</string><string>Icon-Small.png</string><string>Icon-Small@2x.png</string></array>
  <key>MinimumOSVersion</key><string>$IOS_MIN</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UILaunchStoryboardName</key><string>LaunchScreen</string>
  <key>UIStatusBarHidden</key><true/>
  <key>UIRequiresPersistentWiFi</key><false/>
  <key>UISupportedInterfaceOrientations</key><array>
    <string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
  <key>UIInterfaceOrientation</key><string>UIInterfaceOrientationLandscapeRight</string>
</dict></plist>
PL
plutil -convert binary1 "$APP/Info.plist"
if [ -f templates/LaunchScreen.storyboard ]; then
  cp templates/LaunchScreen.storyboard "$APP/"
else
  echo "warning: templates/LaunchScreen.storyboard missing; modern iOS may run the app scaled"
fi
# icons are best-effort: the icon source lives outside the repo (tools/make_icon.py)
if [ -d data/icon ]; then
  cp data/icon/Icon-*.png "$APP/" 2>/dev/null || true
fi
# ad-hoc sign; an on-device signer re-signs with the installer's certificate
codesign --force --sign - "$APP" 2>/dev/null || echo "note: ad-hoc signing skipped (sign on device)"
echo "built $(pwd)/$APP"

if [ "$1" = "ipa" ]; then
  mkdir -p data/carconfig
  for f in tokyo.wpk tokyo_night.wpk sky.wpk sky_night.wpk arrows.wpk arrows_night.wpk arrows.names \
           lights.wpk lights.bin neon.wpk fd3s.wpk hud.bin navi.bin meters.bin phys.img menu.bin minicourse.wpk intro.mp4 playdemo.mp4 tutorial.mp4; do
    if [ -f data/$f ]; then cp data/$f "$APP/"; fi
  done
  for c in oosaka hakone nagoya fukuoka; do
    for f in data/$c.wpk data/${c}_night.wpk data/sky_$c.wpk data/sky_${c}_night.wpk data/arrows_$c.wpk \
             data/arrows_${c}_night.wpk data/arrows_$c.names data/lights_$c.bin data/navi_$c.bin; do
      if [ -f $f ]; then cp $f "$APP/"; fi
    done
  done
  mkdir -p "$APP/traffic" "$APP/carconfig" "$APP/cars" "$APP/sound/bgm" "$APP/sound/engine"
  if [ -d data/traffic ]; then cp data/traffic/*.wpk "$APP/traffic/" 2>/dev/null || true; fi
  if [ -d data/carconfig ]; then cp data/carconfig/*.txt "$APP/carconfig/" 2>/dev/null || true; fi
  if [ -d data/cars ]; then cp data/cars/* "$APP/cars/" 2>/dev/null || true; fi
  if [ -d data/chara ]; then mkdir -p "$APP/chara" && cp data/chara/*.wpk "$APP/chara/" 2>/dev/null || true; { cp data/chara/*.ao "$APP/chara/" 2>/dev/null || true; }; fi
  if [ -d data/wheels ]; then mkdir -p "$APP/wheels" && cp data/wheels/*.wpk "$APP/wheels/" 2>/dev/null || true; fi
  if [ -d data/vinyl ]; then mkdir -p "$APP/vinyl" && cp data/vinyl/*.vpk "$APP/vinyl/" 2>/dev/null || true; fi
  if [ -d data/sound/bgm ]; then cp data/sound/bgm/*.m4a "$APP/sound/bgm/" 2>/dev/null || true; fi
  if [ -d data/sound ]; then cp data/sound/*.wav "$APP/sound/" 2>/dev/null || true; fi
  if [ -d data/sound/engine ]; then cp data/sound/engine/*.wav "$APP/sound/engine/" 2>/dev/null || true; fi
  if [ -d data/rtmovie ]; then mkdir -p "$APP/rtmovie" && cp -R data/rtmovie/* "$APP/rtmovie/" 2>/dev/null || true; fi
  rm -rf build64/ipa && mkdir -p build64/ipa/Payload && cp -R "$APP" build64/ipa/Payload/
  (cd build64/ipa && rm -f "../WMMT3DX-1.0-arm64.ipa" && zip -qry -1 "../WMMT3DX-1.0-arm64.ipa" Payload)
  rm -rf build64/ipa
  echo "packed $(pwd)/build64/WMMT3DX-1.0-arm64.ipa ($(du -h "build64/WMMT3DX-1.0-arm64.ipa" | cut -f1))"
  if [ ! -f "$APP/tokyo.wpk" ]; then
    echo "note: binary-only IPA (no game data found in data/) — add it with:"
    echo "  ./inject_data.sh build64/WMMT3DX-1.0-arm64.ipa data [original-data-dir]"
    echo "before signing on device (the app looks for tokyo.wpk in its bundle)"
  fi
fi
