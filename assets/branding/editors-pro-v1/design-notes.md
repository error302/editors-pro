# Editors Pro logo

Created with the built-in image generation tool. The original horizontal PNG is retained as the design master.

## App integration

- `assets/icons/editors_pro_mark.png` is the transparent symbol derived from the master using the built-in image generation tool.
- `lib/core/widgets/app_brand.dart` pairs the symbol with theme-aware Inter lettering on home, splash, and welcome screens. Live text stays sharp and accessible at different screen sizes.
- `scripts/generate_brand_assets.ps1` exports five Android launcher densities and the native splash image. Adaptive icons keep the symbol within the central mask-safe area.
- Android launch backgrounds use charcoal #111214, with explicit Android 12+ launch themes.

To regenerate Android raster resources, run `./scripts/generate_brand_assets.ps1` in PowerShell on Windows.

## Verification

- Focused Flutter analysis of the four changed app files: no issues.
- Existing `test/app_test.dart` suite: 15 tests passed.
- Final formatting check: five files checked, no changes needed.
- Android resources: AAPT2 compilation and linking passed against Android API 36.
- Adaptive foreground: no pixels with alpha at least 128 outside the central 66dp safe circle at xxxhdpi.
- Initial APK attempt on 24 October stopped at the native-engine freshness guard. The missing native libraries were rebuilt on 31 October; the guard remains enabled.

## Build and phone verification - 31 October 2026

- Built FFmpeg 7.1.5 from its verified signed source for ARM64 and x86_64, then built both Rust engines with FFmpeg enabled.
- Fixed the Windows build script's cargo-ndk working directory and Clang standard-header discovery. The script selects the pinned NDK by default, preserves previous native libraries, and stages that NDK's C++ runtime instead of the old 4 KB-aligned runtime.
- Fresh optimized testing APK: `build/app/outputs/flutter-apk/editors-pro-logo-test-20261031.apk` (112240722 bytes).
- APK SHA-256: `6D61082C882FDC4F21F72390F4C2C8B5C989D7413D0922AC6D39D0C7861B01BD`.
- The APK contains both target architectures; all 26 native libraries passed architecture and 16 KB ELF checks. ZIP alignment, fonts, and APK signature verification passed.
- Bundled logo SHA-256 matches the selected source artwork: `A0E74952262E6C9FA79FEC0A8B18CF6ED5ADCD7C490454544B90D6244F8F3135`.
- The signing certificate matches the previously installed app. Installed with `adb install -r` on Samsung SM-S901U (Android 15), without clearing app data. The original first-install timestamp is retained, and the existing projects remain visible in the home-screen screenshot.
- Home-screen logo visually verified on the phone. Welcome and splash assets passed source/resource checks; their separate device capture was not completed because another activity came to the foreground.
- Fresh existing app regression suite: 15 tests passed. This is a debug-signed testing APK; store-submission readiness remains a separate gate.
- Build log: `build/branding-check/branding-apk-build.log`. APK verification: `build/branding-check/apk-verification.txt`. Device comparison: `build/branding-check/device-before.png` and `build/branding-check/device-after.png`.
- Original installed APK retained for rollback at `build/branding-check/installed-before-logo.apk`. Previous staged native libraries are retained under `engine/ffmpeg-android-lgpl/legacy-prebuilt-backup/`.

For a clean Windows build, install libclang locally with `python -m pip install --target build/native-toolchain/libclang --no-deps libclang==18.1.1`, then run `scripts/build_android_release.ps1` with `-FlutterCommand` pointing to the installed `flutter.bat` if Flutter is not on PATH. The verified build used `CARGO_BUILD_JOBS=4`.

## Symbol edit prompt

Edit the supplied Editors Pro logo into its app symbol asset. Keep exactly the same blue E / editing-strips / play-cue geometry as the source, same proportions, same blue colors and no stylistic redesign. Remove ALL typography. Output ONLY the blue E symbol, centered large on a square canvas with about 10 percent clear padding on every side, transparent background, high resolution, clean sharp edges. No tile, no shadows, no added elements.

Design direction: a blue E formed from editing strips with a forward-motion play cue, paired with a graphite EDITORS PRO wordmark. Palette informed by the current application theme.

## Generation prompt

Use case: logo-brand.
Create a finished, premium brand logo for "EDITORS PRO", a professional video editing application. Produce one beautifully resolved horizontal logo lockup on a genuinely transparent background at high resolution, with generous clear space around the whole logo.
Design: an original, compact geometric E monogram at left, constructed from three bold horizontal editing strips with one precise diagonal cut creating a subtle forward motion / play cue through negative space. The silhouette must read as a strong E first, with a memorable simple shape that would remain clear at app-icon size. Balanced, precise, expertly drawn geometry, restrained slightly softened corners, no thin decorative lines. Use the existing brand's confident blue #527FC4 with deeper #3E65A3 on one complementary face; flat solid colors, no gradient, no 3D.
Wordmark at right: exact text "EDITORS PRO", rendered in substantial custom-feeling contemporary sans-serif lettering, carefully kerned, confident medium-bold weight, refined geometric shapes, dark graphite #191B1E. EDITORS and PRO aligned on the same baseline; PRO may be a slightly lighter weight but remains equally legible. Excellent optical balance and spacing between mark and typography. The mark is approximately the height of the wordmark plus modest breathing room.
A professional creative-software identity, timeless, clear, understated and ownable. Output the actual usable clean logo asset, not a mockup, not a brand board. No extra labels, slogans, watermarks, repeated variants, registration symbols, shadows, glow, texture, camera, scissors, clapperboard, film perforations or generic double play arrows. No background rectangle or tile behind the mark. Keep all content inside the canvas with ample safe margins.

