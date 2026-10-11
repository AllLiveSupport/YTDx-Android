package com.alllivesupport.ytdx.aura_app

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

class DownloadForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "ytdx_turbo_download_channel"
        const val CHANNEL_NAME = "YTDx Studio İndirmeler"
        const val NOTIFICATION_ID = 90210

        const val ACTION_START = "com.alllivesupport.ytdxstudio.ACTION_START"
        const val ACTION_UPDATE = "com.alllivesupport.ytdxstudio.ACTION_UPDATE"
        const val ACTION_STOP = "com.alllivesupport.ytdxstudio.ACTION_STOP"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_PROGRESS = "extra_progress"
        const val EXTRA_SPEED = "extra_speed"
        const val EXTRA_INDETERMINATE = "extra_indeterminate"

        fun start(context: Context, title: String) {
            val intent = Intent(context, DownloadForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun update(context: Context, title: String, progress: Int, speed: String, indeterminate: Boolean = false) {
            val intent = Intent(context, DownloadForegroundService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_PROGRESS, progress)
                putExtra(EXTRA_SPEED, speed)
                putExtra(EXTRA_INDETERMINATE, indeterminate)
            }
            context.startService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, DownloadForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }

    private var notificationManager: NotificationManager? = null

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "İndirme başlatılıyor..."
                val notification = buildNotification(title, 0, "", true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            }
            ACTION_UPDATE -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "İndiriliyor..."
                val progress = intent.getIntExtra(EXTRA_PROGRESS, 0)
                val speed = intent.getStringExtra(EXTRA_SPEED) ?: ""
                val indeterminate = intent.getBooleanExtra(EXTRA_INDETERMINATE, false)
                val notification = buildNotification(title, progress, speed, indeterminate)
                notificationManager?.notify(NOTIFICATION_ID, notification)
            }
            ACTION_STOP -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "YTDx Studio kesintisiz indirme ve bildirim kanalı"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            notificationManager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(
        title: String,
        progress: Int,
        speed: String,
        indeterminate: Boolean
    ): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
            )
        } else null

        val contentText = if (speed.isNotEmpty()) {
            if (indeterminate) speed else "$progress% • $speed"
        } else {
            if (indeterminate) "İşleniyor..." else "$progress%"
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)

        if (pendingIntent != null) {
            builder.setContentIntent(pendingIntent)
        }

        if (indeterminate) {
            builder.setProgress(100, 0, true)
        } else {
            builder.setProgress(100, progress.coerceIn(0, 100), false)
        }

        return builder.build()
    }
}
