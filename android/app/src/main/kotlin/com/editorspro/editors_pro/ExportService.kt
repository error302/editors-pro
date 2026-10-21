package com.editorspro.editors_pro

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/// Foreground service that keeps the export running even when the
/// app is minimized. Android allows foreground services to continue
/// executing when the app is in the background, which is essential
/// for video encoding operations that can take minutes.
///
/// The service shows a notification with export progress that updates
/// in real-time. Tapping the notification returns the user to the app.
class ExportService : Service() {

    companion object {
        const val CHANNEL_ID = "editors_pro_export"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.editorspro.editors_pro.EXPORT_START"
        const val ACTION_UPDATE_PROGRESS = "com.editorspro.editors_pro.EXPORT_PROGRESS"
        const val ACTION_COMPLETE = "com.editorspro.editors_pro.EXPORT_COMPLETE"
        const val ACTION_CANCEL = "com.editorspro.editors_pro.EXPORT_CANCEL"

        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_STAGE = "stage"
        const val EXTRA_FILE_PATH = "file_path"
        const val EXTRA_FILE_SIZE = "file_size"

        /// Start the export foreground service.
        fun start(context: Context) {
            val intent = Intent(context, ExportService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /// Update the export progress notification.
        fun updateProgress(context: Context, progress: Int, stage: String) {
            val intent = Intent(context, ExportService::class.java).apply {
                action = ACTION_UPDATE_PROGRESS
                putExtra(EXTRA_PROGRESS, progress)
                putExtra(EXTRA_STAGE, stage)
            }
            context.startService(intent)
        }

        /// Signal export completion and stop the foreground service.
        fun complete(context: Context, filePath: String, fileSize: String) {
            val intent = Intent(context, ExportService::class.java).apply {
                action = ACTION_COMPLETE
                putExtra(EXTRA_FILE_PATH, filePath)
                putExtra(EXTRA_FILE_SIZE, fileSize)
            }
            context.startService(intent)
        }

        /// Cancel the export and stop the service.
        fun cancel(context: Context) {
            val intent = Intent(context, ExportService::class.java).apply {
                action = ACTION_CANCEL
            }
            context.startService(intent)
        }
    }

    private var currentProgress: Int = 0
    private var currentStage: String = "Preparing"

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                currentProgress = 0
                currentStage = "Preparing"
                if (Build.VERSION.SDK_INT >= 35) {
                    startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING)
                } else if (Build.VERSION.SDK_INT >= 29) {
                    startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
                } else {
                    startForeground(NOTIFICATION_ID, buildNotification())
                }
            }
            ACTION_UPDATE_PROGRESS -> {
                currentProgress = intent.getIntExtra(EXTRA_PROGRESS, 0)
                currentStage = intent.getStringExtra(EXTRA_STAGE) ?: "Encoding"
                updateNotification()
            }
            ACTION_COMPLETE -> {
                val filePath = intent.getStringExtra(EXTRA_FILE_PATH) ?: ""
                val fileSize = intent.getStringExtra(EXTRA_FILE_SIZE) ?: ""
                showCompleteNotification(filePath, fileSize)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_CANCEL -> {
                showCancelledNotification()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /// Create the notification channel for Android 8.0+ (API 26+).
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Video Export",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows progress when exporting videos"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    /// Build the progress notification.
    private fun buildNotification(): Notification {
        // Intent to open the app when notification is tapped
        val contentIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = contentIntent?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("EDITORS-PRO")
            .setContentText("$currentStage — $currentProgress%")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setProgress(100, currentProgress, false)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            // Cancellation belongs to the export engine in the editor. Stopping
            // only this notification service would leave encoding running.
            .addAction(android.R.drawable.ic_menu_view, "Open editor", pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    /// Update the notification with current progress.
    private fun updateNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    /// Show a completion notification (not ongoing — can be dismissed).
    private fun showCompleteNotification(filePath: String, fileSize: String) {
        val manager = getSystemService(NotificationManager::class.java)

        val contentIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = contentIntent?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Export Complete")
            .setContentText("File saved ($fileSize)")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        manager.notify(NOTIFICATION_ID + 1, notification)
    }

    /// Show a cancelled notification.
    private fun showCancelledNotification() {
        val manager = getSystemService(NotificationManager::class.java)

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Export Cancelled")
            .setContentText("The export was cancelled")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        manager.notify(NOTIFICATION_ID + 1, notification)
    }
}
