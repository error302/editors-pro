package com.editorspro.editors_pro

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/**
 * Storage Access Framework (SAF) and MediaStore integration.
 *
 * Handles:
 * - Reading content URIs (from SAF file picker) into temp files the Rust engine can access
 * - Writing exported videos to MediaStore (visible in gallery/file manager)
 * - Copying between content:// URIs and file:// paths
 * - Managing temp files for engine processing
 *
 * On Android 13+ (API 33+), apps must use SAF for user-selected files
 * and MediaStore for saving output to shared storage.
 */
object StorageIntegration {

    private const val TAG = "StorageIntegration"

    // ─── Content URI to File Path ────────────────────────────────────

    /**
     * Copy a content:// URI to a temporary file that the Rust engine can access.
     *
     * The Rust engine can only read file:// paths, so we need to copy
     * content from SAF URIs to the app's cache directory.
     *
     * @param context Android context
     * @param contentUri The content:// URI from SAF
     * @return The absolute path of the temporary file, or null on error
     */
    fun copyContentUriToTempFile(context: Context, contentUri: Uri): String? {
        return try {
            val fileName = getFileName(context, contentUri) ?: "temp_media_${System.currentTimeMillis()}"
            val tempDir = File(context.cacheDir, "engine_media")
            if (!tempDir.exists()) tempDir.mkdirs()

            val tempFile = File(tempDir, fileName)
            if (tempFile.exists()) tempFile.delete()

            context.contentResolver.openInputStream(contentUri)?.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output, 8192)
                }
            }

            Log.i(TAG, "Copied content URI to temp file: ${tempFile.absolutePath}")
            tempFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy content URI to temp file: ${e.message}")
            null
        }
    }

    /**
     * Get the display name from a content URI.
     */
    fun getFileName(context: Context, uri: Uri): String? {
        var name: String? = null

        // Try querying the content resolver
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) {
                    name = cursor.getString(nameIndex)
                }
            }
        }

        // Fallback: extract from URI path
        if (name == null) {
            name = uri.lastPathSegment
        }

        return name
    }

    /**
     * Get the file size from a content URI.
     */
    fun getFileSize(context: Context, uri: Uri): Long {
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0) {
                    return cursor.getLong(sizeIndex)
                }
            }
        }
        return 0L
    }

    // ─── MediaStore Integration ──────────────────────────────────────

    /**
     * Save an exported video file to the MediaStore so it appears in
     * the gallery and file manager.
     *
     * On Android 10+ (API 29+), uses MediaStore to write directly
     * to the Movies directory. On older versions, copies to
     * Environment.DIRECTORY_MOVIES.
     *
     * @param context Android context
     * @param sourceFilePath The absolute path of the exported video file
     * @param displayName The display name for the video (e.g., "My Edit.mp4")
     * @param mimeType The MIME type (e.g., "video/mp4")
     * @return The content:// URI of the saved video, or null on error
     */
    fun saveToMediaStore(
        context: Context,
        sourceFilePath: String,
        displayName: String,
        mimeType: String = "video/mp4"
    ): Uri? {
        return try {
            val sourceFile = File(sourceFilePath)
            if (!sourceFile.exists()) {
                Log.e(TAG, "Source file does not exist: $sourceFilePath")
                return null
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+: Use MediaStore to write to Movies directory
                saveToMediaStoreApi29(context, sourceFile, displayName, mimeType)
            } else {
                // Android 9 and below: Write directly to Movies directory
                saveToMediaStoreLegacy(context, sourceFile, displayName, mimeType)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save to MediaStore: ${e.message}")
            null
        }
    }

    /**
     * Save using MediaStore on Android 10+ (API 29+).
     */
    private fun saveToMediaStoreApi29(
        context: Context,
        sourceFile: File,
        displayName: String,
        mimeType: String
    ): Uri? {
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Video.Media.MIME_TYPE, mimeType)
            put(MediaStore.Video.Media.DATE_ADDED, System.currentTimeMillis() / 1000)
            put(MediaStore.Video.Media.DATE_MODIFIED, System.currentTimeMillis() / 1000)
            put(MediaStore.Video.Media.SIZE, sourceFile.length())

            // Save to Movies/EDITORS-PRO/
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/EDITORS-PRO")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
        }

        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = context.contentResolver.insert(collection, values) ?: return null

        try {
            val output = context.contentResolver.openOutputStream(uri)
                ?: throw IOException("Could not open MediaStore output")
            val copiedBytes = output.use { stream ->
                FileInputStream(sourceFile).use { input ->
                    input.copyTo(stream, 8192)
                }
            }
            if (copiedBytes != sourceFile.length()) {
                throw IOException("MediaStore copy was incomplete")
            }

            // Clear IS_PENDING flag to make the file visible
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Video.Media.IS_PENDING, 0)
                if (context.contentResolver.update(uri, values, null, null) == 0) {
                    throw IOException("Could not publish MediaStore item")
                }
            }

            Log.i(TAG, "Saved video to MediaStore: $uri")
            return uri
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write to MediaStore: ${e.message}")
            context.contentResolver.delete(uri, null, null)
            return null
        }
    }

    /**
     * Save using legacy file system on Android 9 and below.
     */
    private fun saveToMediaStoreLegacy(
        context: Context,
        sourceFile: File,
        displayName: String,
        mimeType: String
    ): Uri? {
        val moviesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        val exportDir = File(moviesDir, "EDITORS-PRO")
        if (!exportDir.exists() && !exportDir.mkdirs()) {
            throw IOException("Could not create Movies/EDITORS-PRO")
        }

        val destFile = File(exportDir, displayName)
        try {
            val copiedBytes = FileInputStream(sourceFile).use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output, 8192)
                }
            }
            if (copiedBytes != sourceFile.length()) {
                throw IOException("MediaStore copy was incomplete")
            }
        } catch (e: Exception) {
            destFile.delete()
            throw e
        }

        // Scan the file so it appears in MediaStore
        val intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE).apply {
            data = Uri.fromFile(destFile)
        }
        context.sendBroadcast(intent)

        Log.i(TAG, "Saved video to legacy path: ${destFile.absolutePath}")
        return Uri.fromFile(destFile)
    }

    // ─── Temp File Management ────────────────────────────────────────

    /**
     * Clean up temporary files in the engine_media cache directory.
     *
     * Should be called when the engine is shut down or when the
     * app is low on memory.
     */
    fun cleanupTempFiles(context: Context) {
        val tempDir = File(context.cacheDir, "engine_media")
        if (tempDir.exists() && tempDir.isDirectory) {
            var count = 0
            tempDir.listFiles()?.forEach { file ->
                if (file.isFile && file.delete()) count++
            }
            Log.i(TAG, "Cleaned up $count temp files")
        }
    }

    /**
     * Get the total size of temporary files in the engine_media cache.
     */
    fun getTempFilesSize(context: Context): Long {
        val tempDir = File(context.cacheDir, "engine_media")
        if (!tempDir.exists() || !tempDir.isDirectory) return 0L

        return tempDir.walkTopDown()
            .filter { it.isFile }
            .map { it.length() }
            .sum()
    }

    /**
     * Get the available storage space in bytes.
     */
    fun getAvailableStorageBytes(): Long {
        val stat = android.os.StatFs(Environment.getDataDirectory().path)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            stat.availableBlocksLong * stat.blockSizeLong
        } else {
            @Suppress("DEPRECATION")
            stat.availableBlocks.toLong() * stat.blockSize.toLong()
        }
    }

    /**
     * Delete a content URI from MediaStore.
     *
     * Only works for URIs that the app created.
     */
    fun deleteFromMediaStore(context: Context, uri: Uri): Boolean {
        return try {
            val deleted = context.contentResolver.delete(uri, null, null)
            Log.i(TAG, "Deleted $deleted item(s) from MediaStore")
            deleted > 0
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete from MediaStore: ${e.message}")
            false
        }
    }
}
