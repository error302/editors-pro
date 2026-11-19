package com.editorspro.editors_pro

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Bundle
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {

    companion object {
        private const val EXPORT_CHANNEL = "com.editorspro/editors_pro/export"
        private const val AUDIO_CHANNEL = "com.editorspro/audio"
        private const val STORAGE_CHANNEL = "com.editorspro/storage"
    }

    private var audioTrack: AudioTrack? = null
    private var sampleRate = 44100
    private var channels = 2
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val messenger = flutterEngine!!.dartExecutor.binaryMessenger
        ExportCapabilitiesIntegration.register(messenger)

        // Completed-export app handoffs (separate from export/storage channels).
        SocialShareIntegration.register(this, messenger)

        // Set up method channel for export foreground service
        MethodChannel(messenger, EXPORT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startExport" -> {
                        ExportService.start(this)
                        result.success(null)
                    }
                    "updateProgress" -> {
                        val progress = call.argument<Int>("progress") ?: 0
                        val stage = call.argument<String>("stage") ?: "Encoding"
                        ExportService.updateProgress(this, progress, stage)
                        result.success(null)
                    }
                    "complete" -> {
                        val filePath = call.argument<String>("filePath") ?: ""
                        val fileSize = call.argument<String>("fileSize") ?: ""
                        ExportService.complete(this, filePath, fileSize)
                        result.success(null)
                    }
                    "cancel" -> {
                        ExportService.cancel(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Set up method channel for audio playback
        MethodChannel(messenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        try {
                            sampleRate = call.argument<Int>("sampleRate") ?: 44100
                            channels = call.argument<Int>("channels") ?: 2

                            require(sampleRate > 0 && (channels == 1 || channels == 2)) { "Audio requires mono/stereo and a positive sample rate" }
                            audioTrack?.pause()
                            audioTrack?.flush()
                            audioTrack?.release()
                            audioTrack = null
                            val channelConfig = if (channels == 1)
                                AudioFormat.CHANNEL_OUT_MONO
                            else
                                AudioFormat.CHANNEL_OUT_STEREO

                            val bufferSize = AudioTrack.getMinBufferSize(
                                sampleRate,
                                channelConfig,
                                AudioFormat.ENCODING_PCM_FLOAT
                            )

                            require(bufferSize > 0) { "AudioTrack does not support this format" }
                            audioTrack = AudioTrack.Builder()
                                .setAudioAttributes(
                                    AudioAttributes.Builder()
                                        .setUsage(AudioAttributes.USAGE_MEDIA)
                                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                                        .build()
                                )
                                .setAudioFormat(
                                    AudioFormat.Builder()
                                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                                        .setSampleRate(sampleRate)
                                        .setChannelMask(channelConfig)
                                        .build()
                                )
                                .setBufferSizeInBytes(bufferSize)
                                .setTransferMode(AudioTrack.MODE_STREAM)
                                .build()

                            check(audioTrack?.state == AudioTrack.STATE_INITIALIZED) { "AudioTrack initialization failed" }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INIT_ERROR", e.message, null)
                        }
                    }

                    "writeSamples" -> {
                        try {
                            val bytes = call.argument<ByteArray>("samples")
                                ?: throw IllegalArgumentException("PCM samples are required")
                            val track = audioTrack ?: throw IllegalStateException("AudioTrack is not initialized")
                            require(bytes.size % 4 == 0) { "PCM must contain complete float32 samples" }
                            val floatArray = FloatArray(bytes.size / 4)
                            ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(floatArray)
                            require(floatArray.all { it.isFinite() }) { "PCM contains a non-finite sample" }
                            // Never block the UI thread. Dart retains and retries every
                            // unaccepted sample, including while priming before play().
                            val written = track.write(floatArray, 0, floatArray.size, AudioTrack.WRITE_NON_BLOCKING)
                            if (written < 0) result.error("WRITE_ERROR", "AudioTrack.write returned $written", null)
                            else result.success(written)
                        } catch (e: Exception) {
                            result.error("WRITE_ERROR", e.message, null)
                        }
                    }
                    "getPlaybackPositionFrames" -> {
                        val track = audioTrack
                        if (track == null) result.error("NOT_INITIALIZED", "AudioTrack is not initialized", null)
                        else result.success(track.playbackHeadPosition.toLong() and 0xffffffffL)
                    }

                    "play" -> {
                        try {
                            audioTrack?.play()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("PLAY_ERROR", e.message, null)
                        }
                    }

                    "pause" -> {
                        try {
                            audioTrack?.pause()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("PAUSE_ERROR", e.message, null)
                        }
                    }

                    "stop" -> {
                        try {
                            audioTrack?.pause()
                            audioTrack?.flush()
                            audioTrack?.stop()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("STOP_ERROR", e.message, null)
                        }
                    }

                    "seekTo" -> {
                        try {
                            val resume = audioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING
                            audioTrack?.pause()
                            audioTrack?.flush()
                            if (resume) audioTrack?.play()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SEEK_ERROR", e.message, null)
                        }
                    }

                    "setVolume" -> {
                        try {
                            val volume = call.argument<Double>("volume")?.toFloat() ?: 1.0f
                            audioTrack?.setVolume(volume.coerceIn(0.0f, 1.0f))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("VOLUME_ERROR", e.message, null)
                        }
                    }

                    "release" -> {
                        try {
                            audioTrack?.pause()
                            audioTrack?.flush()
                            audioTrack?.release()
                            audioTrack = null
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("RELEASE_ERROR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // Set up method channel for SAF/MediaStore storage integration
        MethodChannel(messenger, STORAGE_CHANNEL, StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidSdkVersion" -> result.success(Build.VERSION.SDK_INT)
                    "copyContentUriToTempFile" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString != null) {
                            val uri = android.net.Uri.parse(uriString)
                            val path = StorageIntegration.copyContentUriToTempFile(this, uri)
                            if (path != null) {
                                result.success(path)
                            } else {
                                result.error("COPY_FAILED", "Failed to copy content URI", null)
                            }
                        } else {
                            result.error("INVALID_URI", "URI argument is null", null)
                        }
                    }
                    "getFileName" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString != null) {
                            val uri = android.net.Uri.parse(uriString)
                            val name = StorageIntegration.getFileName(this, uri)
                            result.success(name)
                        } else {
                            result.error("INVALID_URI", "URI argument is null", null)
                        }
                    }
                    "getFileSize" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString != null) {
                            val uri = android.net.Uri.parse(uriString)
                            val size = StorageIntegration.getFileSize(this, uri)
                            result.success(size)
                        } else {
                            result.error("INVALID_URI", "URI argument is null", null)
                        }
                    }
                    "saveToMediaStore" -> {
                        val filePath = call.argument<String>("filePath")
                        val displayName = call.argument<String>("displayName")
                        val mimeType = call.argument<String>("mimeType") ?: "video/mp4"
                        if (filePath != null && displayName != null) {
                            val uri = StorageIntegration.saveToMediaStore(this, filePath, displayName, mimeType)
                            if (uri != null) {
                                result.success(uri.toString())
                            } else {
                                result.error("SAVE_FAILED", "Failed to save to MediaStore", null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "filePath or displayName is null", null)
                        }
                    }
                    "cleanupTempFiles" -> {
                        StorageIntegration.cleanupTempFiles(this)
                        result.success(null)
                    }
                    "getTempFilesSize" -> {
                        val size = StorageIntegration.getTempFilesSize(this)
                        result.success(size)
                    }
                    "getAvailableStorageBytes" -> {
                        val bytes = StorageIntegration.getAvailableStorageBytes()
                        result.success(bytes)
                    }
                    "deleteFromMediaStore" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString != null) {
                            val uri = android.net.Uri.parse(uriString)
                            val deleted = StorageIntegration.deleteFromMediaStore(this, uri)
                            result.success(deleted)
                        } else {
                            result.error("INVALID_URI", "URI argument is null", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onResume() {
        super.onResume()
        // Notify the engine that the activity is resuming
        // (for future: engine.pause() / engine.resume() lifecycle hooks)
    }

    override fun onPause() {
        super.onPause()
        // Notify the engine that the activity is pausing
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            audioTrack?.stop()
            audioTrack?.release()
            audioTrack = null
        } catch (_: Exception) {
            // Ignore cleanup errors
        }
    }

}
