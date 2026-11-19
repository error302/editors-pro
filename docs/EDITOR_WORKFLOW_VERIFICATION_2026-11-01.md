# Editors Pro workflow verification — 1 November 2026

This records the current working tree. It is separate from store-submission approval and from verification of every advanced feature in the existing app.

## Implemented

- Durable, atomic media-library copying, including Android content URIs and stream-only provider files. Empty/unavailable/unsupported files fail without publishing a partial copy. Picker cancellation and project switches cannot attach late selections to another project. Back waits for an accepted import to finish before saving.
- Eight native looks: Clean, Cinematic, Vintage, Dramatic, Cool, Warm, Noir and Soft Film. Intensity, bypass, reset and atomic undo preserve manual adjustments. Catalog/UI values come from the native engine.
- Text content, embedded font faces, size, colour and normalized position share the persisted native contract. Inspector selection hydration, pending-edit save barriers and paused-frame invalidation are covered.
- Photos/video use composed project frames. The renderer fits images into the project canvas, blends visible layers and text, and shares its output with export. Invalidated in-flight frames cannot refill the paused cache.
- Native timeline save precedes database metadata updates. Save/open/delete serialize; missing saved timelines fail visibly. Snapshot restore and duplication preserve actual saved edits and independent database ownership.
- Project cards show saved-timeline covers. A separate player renders approximately 480p/12fps and up to the first 10 seconds, with audio and a duration label. Private preview engines leave the active project and undo history alone. Cache manifests validate timeline/source fingerprints and artifact hashes.
- Audio output retains partially accepted Android writes in a bounded queue. AAC planar frames initialize both channels and padding; decoding excludes allocation padding and aligns stereo trims.

## Verified evidence

| Scope | Result |
| --- | --- |
| Full Flutter suite | **341 passed**, `flutter test --no-pub`; log `build/feature-audit/flutter-full-tests-final.log`. Includes realistic provider-stream/import-navigation tests and composed-image cache regressions. |
| Dart analysis | Integrated analysis and the final scoped preview/LUT analysis reported no errors or warnings; style infos remain. |
| Native host targets, no FFmpeg | Canvas composition 3, filter looks 4, text workflow 3, saved render-state 3, isolated preview/clone workflow 1, stereo trim alignment 1 and still-image persistence 1 passed (16 total). This does not establish encoding on Windows. |
| Native Android codecs | **5 passed** on Samsung SM-S901U / Android 15, ARM64, using the rebuilt FFmpeg libraries. Includes WAV 44.1→48kHz resampling, distinct stereo AAC round-trip with uneven chunks/final padding, invalid-PCM rejection, and a real photo/song/red-text/Noir save-reload → H.264/AAC export → cover/playable-preview workflow. Log `build/feature-audit/android-audio-tests.log`. |
| Independent output inspection | Android output pulled to `build/feature-audit/android-native-media-output/`. Local ffprobe confirms H.264 320×180 plus AAC stereo 48kHz, 1.002 seconds. A decoded video frame visibly contains the grayscale image and red “Editors Pro” title. Local FFmpeg comparison against the saved cover measured SSIM 0.997828 after YUV420 conversion. Tone checks verify distinct channels in both export and preview. This fixture does not prove all export profiles. |
| Android MP3 codec probe | The exact packaged ARM64 FFmpeg libraries decoded the owned 3-second MP3 fixture to 132,300 frames at 44.1kHz stereo, all finite; left/right RMS 0.024344. `build/feature-audit/android-mp3-probe.json`. This is codec evidence, not an Android picker UI test. |
| Current APK | Built and installed with `adb install -r` on Samsung SM-S901U / Android 15. Existing project cards remained visible. All 26 packaged native libraries and APK ZIP entries passed 16KB alignment checks; signature matched the previously installed debug certificate. Testing APK: `build/app/outputs/flutter-apk/editors-pro-effects-previews-test-20261101.apk`, 115,074,014 bytes; SHA256 `5E6BB814D04C1B57A9F192A0E529944BDFB87A2A8EE79AA681068FCD97E6A8EC`. This is debug-signed, not a store upload artifact. |
| Android app UI | Completed on the final testing APK using only `QA_Workflows_20261101`: normal PNG and MP3 pickers → durable library/timeline clips → native Noir look → custom Inter Bold text changed from size 72/white to size 157/red → save → activity recreation and cold reopen retaining the edit → refreshed cover and playable preview with pause/resume/close → 720p H.264 export → successful Gallery save. Screenshots are in `build/feature-audit/device-*.png`. Delayed home navigation, tab selection loss and unbounded phone Inspector scrolling were reproduced and fixed with regressions. |
| Actual app output | `/sdcard/Movies/EDITORS-PRO/export_1793486925566.mp4`, copied to `build/feature-audit/qa-app-export.mp4`: 651,415 bytes, H.264 1280×720 at 30fps, AAC 44.1kHz stereo, 5.015 seconds. Independently decoded picture retains Noir and large red title. Audio RMS −34.516dB, zero NaNs/Infs. The fixture has sound for its three-second source followed by silence. Probe/audio logs and decoded PNG are beside the file. |
| Android player correction | A physical 854×480 texture preview exposed a green crop edge, while an isolated engine-generated file decoded cleanly with local FFmpeg (`stride-preview.mp4` / `stride-frame.png`). API 34+ previews now use the plugin native SurfaceView; older Android retains its existing texture fallback because of documented platform-view issues. Same-device playback, pause/resume, close/disposal and reopen were verified cleanly. Other Android versions/vendors remain a compatibility-matrix requirement. The final red-title/Noir preview also refreshed correctly, and the phone was left on its completed project card. |

## Limits

System Back from the export screen closed the activity in this run; relaunch and cold project reopen retained the saved edit. Its return-navigation UX remains a follow-up.

The photo workflow is a still-image clip in a video timeline, not a standalone photo-export product. Non-1× pitch-corrected audio preview is not implemented. Full Rust library tests retain older compilation failures and have not been relabelled green by selected integration targets. Store signing, policy declarations, every advertised codec/profile, 16KB runtime hardware, long exports, cancellation and background lifecycle require their own evidence. See `SUBMISSION_READINESS.md` for the historical submission audit and `monetisation-plan.md` for the proposal; no billing has been added.

The native Android test directory is retained under `/data/local/tmp/editors-pro-audio-qa-20261101-004721`. UI fixtures are separately named in `/sdcard/Download/EditorsPro-QA-20261101/`. Existing user projects must remain untouched.
