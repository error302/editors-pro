package com.editorspro.editors_pro

import android.media.MediaCodec
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/** Checks the default encoder selected by MIME, matching FFmpeg's Android path. */
object ExportCapabilitiesIntegration {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.editorspro/export_capabilities", StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
            if (call.method != "inspectSettings") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val width = call.argument<Number>("width")?.toInt() ?: 0
            val height = call.argument<Number>("height")?.toInt() ?: 0
            val fps = call.argument<Number>("fps")?.toDouble() ?: 0.0
            val bitrate = call.argument<Number>("bitrateKbps")?.toLong() ?: 0L
            val codec = call.argument<String>("codec") ?: ""
            val mime = when (codec) {
                "H.264" -> "video/avc"
                "H.265" -> "video/hevc"
                "VP9" -> "video/x-vnd.on2.vp9"
                "AV1" -> "video/av01"
                else -> null
            }
            if (mime == null || width <= 0 || height <= 0 || !fps.isFinite() || fps <= 0 ||
                bitrate <= 0 || bitrate > Int.MAX_VALUE / 1000) {
                result.error("INVALID_SETTINGS", "Invalid encoder settings", null)
                return@setMethodCallHandler
            }
            var encoder: MediaCodec? = null
            try {
                encoder = MediaCodec.createEncoderByType(mime)
                val info = encoder.codecInfo
                val video = info.getCapabilitiesForType(mime).videoCapabilities
                    ?: throw IllegalStateException("Encoder did not expose video capabilities")
                val sizeAndRate = video.areSizeAndRateSupported(width, height, fps)
                val bitrateSupported = video.bitrateRange.contains((bitrate * 1000).toInt())
                val aligned = width % video.widthAlignment == 0 && height % video.heightAlignment == 0
                val supported = sizeAndRate && bitrateSupported && aligned
                val reason = when {
                    !aligned -> "Encoder requires ${video.widthAlignment}x${video.heightAlignment} pixel alignment."
                    !sizeAndRate -> "The device encoder does not report support for ${width}x${height} at $fps fps."
                    !bitrateSupported -> "The requested bitrate is outside this encoder's supported range."
                    else -> null
                }
                result.success(mapOf(
                    "supported" to supported,
                    "encoderName" to info.name,
                    "hardwareAccelerated" to if (Build.VERSION.SDK_INT >= 29) info.isHardwareAccelerated else null,
                    "widthAlignment" to video.widthAlignment,
                    "heightAlignment" to video.heightAlignment,
                    "reason" to reason,
                ))
            } catch (error: Exception) {
                result.success(mapOf("supported" to false,
                    "reason" to "Encoder capability check failed: ${error.message ?: error.javaClass.simpleName}"))
            } finally {
                try { encoder?.release() } catch (_: Exception) { }
            }
        }
    }
}
