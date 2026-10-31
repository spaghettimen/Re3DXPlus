# iOS arm64 port (modern iPhones/iPads)

`build_ios64.sh` is the arm64 counterpart of `build.sh`, kept separate so the
original armv7/iOS 6 path is untouched. Nothing in the game itself changed:
there is no architecture-specific code in `src/` (no assembly, no NEON), and
the whole core already compiles and runs on arm64 — the Android build proves
it with the same sources and the same physics flags.

## What changed versus build.sh

- `-arch arm64` with the modern iphoneos SDK: no theos, no patched
  iPhoneOS 9.3 SDK. Deployment target is `IOS_MIN` (default 16.0).
- `main.m` and `sound_ios.m` are manual retain/release, so they get
  `-fno-objc-arc`. (The original only avoided ARC because iOS 6 had no ARC
  runtime.)
- `gk_ios.m` is replaced by `gk.c`, the stub the Android build already
  uses. Bluetooth versus is lost; the UDP network versus in `net.c` /
  `vs_host.c` is untouched.
- No `ldid`, no GameKit framework. The app is ad-hoc signed; an on-device
  signer re-signs it with the installer's certificate.
- `templates/LaunchScreen.storyboard` is bundled and referenced as
  `UILaunchStoryboardName`, so modern iOS doesn't run the app letterboxed
  or scaled. `UIDeviceFamily` is iPhone + iPad.
- Icons are best-effort from `data/icon/` (the icon source lives outside
  the repo). A proper 1024px AppIcon is polish, not a blocker.

## Why the screen should just work

`app_init` takes the real framebuffer size and the layout stays 1024x768,
centered, via `app_wide`: wider screens see more at the sides, and touch
coordinates are mapped from the actual screen size. So a tall modern iPhone
gets the centered 4:3 HUD (clear of the notch) with extra course view at
the edges. Rendering defaults to 1x points; native resolution is already an
in-game OPTION screen setting (the RESOLUTION option, `menu_state.hires`),
not a code change.

## Building

Needs macOS + Xcode (no theos, no old SDK):

```
./build_ios64.sh       # build64/WMMT.app only
./build_ios64.sh ipa   # also build64/WMMT3DX-1.0-arm64.ipa
```

## CI (GitHub Actions)

`.github/workflows/ios64.yml` runs `build_ios64.sh ipa` on a macos-15
runner and uploads the IPA as an artifact. The runner has everything the
build needs (Xcode, plutil, afconvert); no secrets, no theos setup.

## Game data (never commit it)

The IPA step includes `data/` when it has been prepared (same file list
as `build.sh`'s ipa step). On CI there is no data, so the artifact is a
binary-only IPA. Add the data locally, then sign on device:

```
./inject_data.sh build64/WMMT3DX-1.0-arm64.ipa data [original-data-dir]
```

`data/` is the tree the pack tools produce (`tools/gen_from_original.sh
--phys`, `tools/stage/pack_*.py`, `prepare_sound.sh`, `prepare_bgm.sh`,
`prepare_movie.sh`). The optional third argument is the
`Wangan Midnight Maximum Tune 3DX+ (Japan)` folder, used only for
`rtmovie/table+trail` and `carconfig/ytConfig*.txt` when they aren't in
`data/` already. `inject_data.sh` warns if `tokyo.wpk` or `phys.img` is
missing: without `tokyo.wpk` in the bundle the app falls back to the
jailbreak-only `/var/mobile/Media/wmmt` path and fails to start.

Data prep itself is not Mac-bound: the Python tools run anywhere,
`prepare_movie.sh` needs an ffmpeg with the Bink decoder (mainline
ffmpeg), and `prepare_bgm.sh`'s `afconvert` can be swapped for
`ffmpeg -c:a aac` on Linux.

## Known limitations / watch items

- No Bluetooth versus (see above). UDP network versus works.
- OpenGL ES is deprecated since iOS 12 but still links and runs on
  current iOS. If Apple ever removes it, the fallback is the Android
  `vkgl` route via Metal — a much bigger project, not this port.
- `UIAlertView` in `main.m` is deprecated; it still compiles, but if a
  future SDK removes it, swap that one call for `UIAlertController`.
- Untested on a real phone: this machine has no macOS toolchain, so the
  first CI run is the smoke test. On-device unknowns are touch feel on a
  tall screen and performance at native resolution.
