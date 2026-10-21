# Submission readiness audit — 21 October 2026

Verdict: **not yet cleared for store submission**. This audit replaces the older blanket completion claims in README. A successful APK is build evidence; it does not establish full editing, export, store-policy or device compatibility.

## Implemented in this pass

- Explicit arm64-v8a/x86_64 target options in the Windows release script, consistent with CI.
- Correct Flutter/Android export method-channel name. Regression covers service start, progress clamping and completion.
- Correct mediaProcessing foreground service on API 35+, dataSync on API 29–34. Notification action returns to the editor; it no longer pretends stopping the service cancels the engine.
- Project search, no-results state, load failure/retry, and clearing a recovered load error.
- Charcoal workbench surfaces; separated project, transport and viewer controls; visible Export action; constrained project title and format metadata.
- All editing panels accessible in a scrollable phone sheet. Phone portrait, landscape and tablet layout regressions.
- Project aspect ratio in the preview and safe-zone overlay. Frame step follows project FPS.
- Removed decorative zebra stripes, disconnected edit-mode switches, and a freeze-frame action that only split a clip.
- Preserve timeline duration after editor initialization.
- Main export uses the existing audio/video muxer instead of silently dropping timeline audio. Bounded audio chunks, output-rate resampling and silence across gaps. Real FFmpeg regression checks video/audio streams and decoded audible samples at 48 kHz.

## Verification ledger

| Gate | Evidence / remaining requirement |
| --- | --- |
| Local APK reproduction | Fails verifyRustEngineFreshness: x86_64 engine library missing. Do not bypass this guard or use legacy FFmpegKit libraries. |
| Baseline GitHub Android packaging | Run 38451800135 Android job succeeded at 107ea3a3; overall pipeline failed. Historical, not validation of this pass. |
| Focused Flutter regressions | 27 passed before font replacement; final rerun recorded below when available. |
| Rust library check | Local no-FFmpeg cargo check passed; does not test media codecs. |
| Full Rust suite | Baseline has 112 test compilation errors from stale API calls and test implementations. Must be repaired; do not disable tests to claim a green pipeline. |
| Dart analysis | Baseline 1218 diagnostics, including warnings and style/deprecation findings. Requires cleanup and a fresh run. |
| Native FFmpeg export | New audible export regression must pass with FFmpeg enabled; no-FFmpeg tests cannot establish encoding correctness. |
| Fonts | Four checked-in TTFs were invalid 12-byte placeholders. Replace with official licensed files and verify glyph rendering. |
| APK / AAB final | Build exact committed source, inspect supported ABIs, all native ELF alignment, ZIP alignment and signer. |
| Device | Samsung SM-S901U available via ADB. Installation, launch, import, trim, undo, save/reopen, audible export, cancellation and Gallery save require final verification. |

## Remaining submission blockers

1. **Release identity and signing** — owner-controlled upload key, verified release-signed AAB, store listing and versioning. Test artifacts may be debug-signed and must be labelled accordingly.
2. **Public policy and support details** — a public privacy-policy URL, real support contact, Data safety and content-rating declarations. The existing in-app disclosure explicitly says these are missing. Do not invent an owner identity or claim publication.
3. **Core media acceptance** — compare edited preview against exported output for video, photographs, text, transforms, effects, transitions, speed, audio volume/mute and save/reopen. Test long exports, cancellation, low storage, missing files and lifecycle interruption. New muxing does not establish complete effect parity.
4. **Green quality gates** — full Rust test compilation, clippy, formatting and Flutter analysis. The build job is independent of these checks; a passing build must not be described as a passing pipeline.
5. **16 KB runtime** — inspect every packaged native library and APK ZIP alignment, then launch and export on a 16 KB Android device/emulator. Android documentation: https://developer.android.com/guide/practices/page-sizes
6. **Foreground service lifecycle** — correct type is implemented; API 35 timeout handling, long background export, notification permission denial and process recreation still need device checks. Guidance: https://developer.android.com/about/versions/15/changes/foreground-service-types
7. **Capability honesty** — cloud integrations, transcription, stabilization, tracking, hardware status, HDR and other advanced controls require individual end-to-end evidence before store claims. Experimental flags are not proof of functionality.
8. **Photo product scope** — current product edits still images in a video timeline. A complete standalone photo editor needs image output, non-destructive adjustments, crop/rotate, color management and metadata handling. Do not market a complete photo editor before that workflow exists and is verified.
9. **Accessibility and localization** — test 200% text scale, TalkBack labels, focus order, minimum tap targets, contrast, light/system theme consistency, RTL and all advertised languages. Many existing strings are still hardcoded English.
10. **Codec/container support** — verify each offered codec on actual hardware and valid audio/container combinations, rather than assuming FFmpeg compilation guarantees available encoders.

## UI direction

Use the user's actual media as the visual focus. Neutral layered panels, one restrained accent, consistent 48 px actions, precise numerical typography and a quiet inspector establish hierarchy. Keep project actions above transport, viewer tools outside the image, and clip operations next to the timeline. Tablets expose media/viewer/inspector; phones expose the same tools through a scrollable sheet. Canvas presets are named honestly rather than represented as finished creative templates. Avoid decorative metrics, false save indicators and unsupported tools.

The next photo workspace should share this chrome and inspector, with an image canvas and history/layers replacing the video transport and timeline. It needs its own export and editing implementation before it can be offered as a mode.
