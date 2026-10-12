package com.editorspro.editors_pro

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
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

                            val channelConfig = if (channels == 1)
                                AudioFormat.CHANNEL_OUT_MONO
                            else
                                AudioFormat.CHANNEL_OUT_STEREO

                            val bufferSize = AudioTrack.getMinBufferSize(
                                sampleRate,
                                channelConfig,
                                AudioFormat.ENCODING_PCM_FLOAT
                            )

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

                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INIT_ERROR", e.message, null)
                        }
                    }

                    "writeSamples" -> {
                        try {
                            val bytes = call.argument<ByteArray>("samples")
                            if (bytes != null && audioTrack != null) {
                                val floatBuffer = ByteBuffer.wrap(bytes)
                                    .order(ByteOrder.LITTLE_ENDIAN)
                                val floatArray = FloatArray(bytes.size / 4)
                                floatBuffer.asFloatBuffer().get(floatArray)

                                audioTrack?.write(floatArray, 0, floatArray.size, AudioTrack.WRITE_NON_BLOCKING)
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("WRITE_ERROR", e.message, null)
                        }
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
                            audioTrack?.stop()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("STOP_ERROR", e.message, null)
                        }
                    }

                    "seekTo" -> {
                        try {
                            audioTrack?.stop()
                            audioTrack?.flush()
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
                            audioTrack?.stop()
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
        MethodChannel(messenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
