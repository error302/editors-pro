package com.editorspro.editors_pro

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/** Opens a receiving app. A successful intent is never a publication receipt. */
class SocialShareIntegration private constructor(private val activity: Activity) {
    companion object {
        private const val CHANNEL = "com.editorspro/social_share"

        // No arbitrary package/component is accepted from the Flutter caller.
        private val targetPackages = linkedMapOf(
            "youtube" to listOf("com.google.android.youtube"),
            "tiktok" to listOf("com.zhiliaoapp.musically", "com.ss.android.ugc.trill"),
            "instagram" to listOf("com.instagram.android"),
            "facebook" to listOf("com.facebook.katana"),
            "x" to listOf("com.twitter.android"),
        )
        private val videoTypes = mapOf(
            "mp4" to "video/mp4",
            "m4v" to "video/x-m4v",
            "mov" to "video/quicktime",
            "webm" to "video/webm",
            "avi" to "video/x-msvideo",
            "mkv" to "video/x-matroska",
        )

        fun register(activity: Activity, messenger: BinaryMessenger) {
            val integration = SocialShareIntegration(activity)
            MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAvailableTargets" -> {
                        try {
                            result.success(targetPackages.keys.filter {
                                integration.resolvePackage(it, "video/*") != null
                            })
                        } catch (error: Exception) {
                            result.error("AVAILABILITY_FAILED", "Could not check video sharing apps.", null)
                        }
                    }
                    "shareVideo" -> integration.share(
                        call.argument<String>("filePath"),
                        call.argument<String>("target"),
                        call.argument<String>("caption") ?: "",
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun resolvePackage(target: String, mimeType: String): String? =
        targetPackages[target]?.firstOrNull { packageName ->
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                setPackage(packageName)
            }
            intent.resolveActivity(activity.packageManager) != null
        }

    private fun share(
        sourcePath: String?,
        target: String?,
        caption: String,
        result: MethodChannel.Result,
    ) {
        if (sourcePath.isNullOrBlank() ||
            (target != "more" && !targetPackages.containsKey(target))
        ) {
            result.error("INVALID_SHARE", "Choose a completed video and a supported app.", null)
            return
        }
        // File copying must not block the activity's UI thread.
        Thread({
            var staged: File? = null
            try {
                val source = File(sourcePath).canonicalFile
                val extension = source.extension.lowercase(java.util.Locale.ROOT)
                val mimeType = videoTypes[extension]
                    ?: throw ShareFailure("INVALID_VIDEO", "Export MP4 or another supported video format to share.")
                val shareFile = stageVideo(source, extension)
                staged = shareFile
                activity.runOnUiThread {
                    try {
                        if (activity.isFinishing || activity.isDestroyed) {
                            throw ShareFailure("ACTIVITY_UNAVAILABLE", "Return to the export screen and try again.")
                        }
                        val packageName = if (target == "more") null else {
                            resolvePackage(target!!, mimeType)
                                ?: throw ShareFailure("APP_UNAVAILABLE", "This app cannot receive the video. Use More share options.")
                        }
                        val uri = FileProvider.getUriForFile(
                            activity,
                            "${activity.packageName}.social_share.files",
                            shareFile,
                        )
                        val sendIntent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, uri)
                            if (caption.isNotEmpty()) putExtra(Intent.EXTRA_TEXT, caption)
                            clipData = ClipData.newUri(activity.contentResolver, "Video export", uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            if (packageName != null) setPackage(packageName)
                        }
                        val launchIntent = if (target == "more") {
                            Intent.createChooser(sendIntent, "Share video").apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                clipData = sendIntent.clipData
                            }
                        } else sendIntent
                        activity.startActivity(launchIntent)
                        // Keep our cache copy: receivers may read it after startActivity returns.
                        result.success("handoff_started")
                    } catch (error: Exception) {
                        shareFile.delete() // Only the unique copy created by this attempt.
                        reportFailure(result, error)
                    }
                }
            } catch (error: Exception) {
                staged?.delete()
                activity.runOnUiThread { reportFailure(result, error) }
            }
        }, "EditorsProSocialShare").start()
    }

    private fun stageVideo(source: File, extension: String): File {
        if (!source.isFile || !source.canRead() || source.length() <= 0L) {
            throw ShareFailure("INVALID_VIDEO", "The exported video is missing, empty or unreadable. Export it again.")
        }
        val sourceLength = source.length()
        val sourceModified = source.lastModified()
        val root = File(activity.cacheDir.canonicalFile, "social_share")
        // Reject a redirected cache folder; never expose or delete outside our own directory.
        if (root.canonicalFile != root.absoluteFile ||
            (!root.isDirectory && !root.mkdirs())
        ) {
            throw ShareFailure("SHARE_CACHE_UNAVAILABLE", "Could not prepare a private sharing copy.")
        }
        val temporary = File.createTempFile("share-", ".part", root)
        val completed = File(root, "${UUID.randomUUID()}.$extension")
        try {
            val copied = source.inputStream().use { input ->
                FileOutputStream(temporary).use { output ->
                    val count = input.copyTo(output)
                    output.fd.sync()
                    count
                }
            }
            if (copied <= 0L || copied != sourceLength ||
                source.length() != sourceLength || source.lastModified() != sourceModified
            ) {
                throw ShareFailure("EXPORT_CHANGED", "The video changed while preparing it. Wait for export to finish and try again.")
            }
            if (!temporary.renameTo(completed)) {
                throw ShareFailure("SHARE_COPY_FAILED", "Could not finish preparing the sharing copy.")
            }
            return completed
        } finally {
            temporary.delete() // Exact temp file created above; never the source export.
        }
    }

    private fun reportFailure(result: MethodChannel.Result, error: Exception) {
        when (error) {
            is ShareFailure -> result.error(error.code, error.message, null)
            is ActivityNotFoundException -> result.error("APP_UNAVAILABLE", "No app could open this video. Use More share options.", null)
            else -> result.error("SHARE_FAILED", "Could not open video sharing. Please try again.", null)
        }
    }

    private class ShareFailure(val code: String, message: String) : Exception(message)
}
