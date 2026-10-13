# EDITORS-PRO ProGuard Rules

# Keep Rust JNI library native method names
-keepclasseswithmembernames class * {
    native <methods>;
}

# FFmpeg classes

# ExoPlayer / Media3
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }

# flutter_rust_bridge generated classes
-keep class dev.frigidbear.flutter_rust_bridge.** { *; }
-keep class * implements dev.frigidbear.flutter_rust_bridge.Generated.** { *; }

# Keep Rust engine native method names (pattern matching)
-keepclasseswithmembernames,includedescriptorclasses class * {
    *** editorsPro*(*);
}
