# Android FFmpeg Build and Release Notes

EDITORS-PRO builds FFmpeg from the official 7.1.5 source release for Android. The build script verifies the upstream signature, builds shared libraries for `arm64-v8a` and `x86_64`, enables JNI-backed Android MediaCodec, and explicitly disables GPL, nonfree, and LGPLv3-only components. Do not replace this build with an unreviewed FFmpeg Kit or full-GPL archive.

On Windows with Docker Desktop, run:

```powershell
.\scripts\build_ffmpeg_android.ps1
```

The script keeps generated libraries under the ignored `engine/ffmpeg-android-lgpl` directory. The Rust engine build must set `FFMPEG_DIR` to that directory. The APK build copies the corresponding ABI libraries into Android `jniLibs` after preserving any existing libraries in the local legacy backup directory.

## Licensing and distribution

- FFmpeg is distributed under LGPL 2.1 or later in this configuration. The app links to shared libraries and registers an FFmpeg notice in its Open Source Notices screen.
- Distributors must provide the exact corresponding FFmpeg source, build instructions, any local modifications, and the applicable license text with the app distribution. The official source archive and this repository's build script are the provenance record; a working public source offer/link still has to be provided for each release.
- Keep FFmpeg attribution in the app's open-source notices and mention FFmpeg in applicable EULA/terms. Do not prohibit reverse engineering of the LGPL library.
- This FFmpeg configuration does not include `libx264` or `libx265`; Android H.264, HEVC, VP9, and AV1 exports request the device's MediaCodec implementation. Encoder availability and codec patent/licensing obligations vary by device and jurisdiction and require separate release review.
- A debug-signed APK is for testing only. Play submission still requires a user-controlled upload key, complete store listing and policy declarations, and review of all codec patent, privacy, and third-party license obligations.
