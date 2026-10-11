package com.alllivesupport.ytdx.aura_app

import android.content.Context
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.PowerManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

class MainActivity : AudioServiceActivity() {
    private val SHARE_CHANNEL = "com.alllivesupport.ytdxstudio/share"
    private val MUXER_CHANNEL = "com.alllivesupport.ytdxstudio/muxer"
    private val WAKELOCK_CHANNEL = "com.alllivesupport.ytdxstudio/wakelock"
    private var sharedText: String? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    private fun acquireLocks() {
        try {
            if (wakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = powerManager?.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "YTDxStudio:DownloadWakeLock"
                )?.apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire(60 * 60 * 1000L) // 1 hour max safety timeout
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        try {
            if (wifiLock == null) {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                wifiLock = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                    wifiManager?.createWifiLock(
                        WifiManager.WIFI_MODE_FULL_LOW_LATENCY,
                        "YTDxStudio:DownloadWifiLock"
                    )
                } else {
                    @Suppress("DEPRECATION")
                    wifiManager?.createWifiLock(
                        WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                        "YTDxStudio:DownloadWifiLock"
                    )
                }?.apply {
                    setReferenceCounted(false)
                }
            }
            if (wifiLock?.isHeld != true) {
                wifiLock?.acquire()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        try {
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighRefreshRate()
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        enableHighRefreshRate()
    }

    private fun enableHighRefreshRate() {
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val display = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                    display
                } else {
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay
                }
                val modes = display?.supportedModes
                if (!modes.isNullOrEmpty()) {
                    var bestMode = modes[0]
                    for (mode in modes) {
                        if (mode.refreshRate > bestMode.refreshRate) {
                            bestMode = mode
                        }
                    }
                    val params = window.attributes
                    params.preferredDisplayModeId = bestMode.modeId
                    window.attributes = params
                }
            }
        } catch (_: Exception) {
            // Fallback gracefully on devices that do not permit display mode switching
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
        val textToSend = sharedText
        sharedText = null
        if (!textToSend.isNullOrEmpty()) {
            flutterEngine?.let {
                MethodChannel(it.dartExecutor.binaryMessenger, SHARE_CHANNEL).invokeMethod("onSharedText", textToSend)
            }
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        var text: String? = null

        if (intent.action == Intent.ACTION_SEND) {
            text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (text.isNullOrEmpty() && intent.clipData != null && intent.clipData!!.itemCount > 0) {
                text = intent.clipData!!.getItemAt(0)?.text?.toString()
            }
            if (text.isNullOrEmpty()) {
                text = intent.getStringExtra(Intent.EXTRA_SUBJECT)
            }
        } else if (intent.action == Intent.ACTION_VIEW) {
            text = intent.dataString
        }

        if (!text.isNullOrEmpty()) {
            sharedText = text
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialSharedText") {
                val current = sharedText
                sharedText = null
                result.success(current)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MUXER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "muxVideoAndAudio") {
                val videoPath = call.argument<String>("videoPath")
                val audioPath = call.argument<String>("audioPath")
                val outputPath = call.argument<String>("outputPath")

                if (videoPath != null && audioPath != null && outputPath != null) {
                    // Run heavy media processing off the UI thread with background priority
                    Thread {
                        try {
                            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
                        } catch (_: Exception) {}
                        val success = muxVideoAndAudio(videoPath, audioPath, outputPath)
                        runOnUiThread {
                            result.success(success)
                        }
                    }.start()
                } else {
                    result.error("INVALID_ARGS", "Paths cannot be null", null)
                }
            } else if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path != null) {
                    android.media.MediaScannerConnection.scanFile(context, arrayOf(path), null, null)
                    result.success(true)
                } else {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKELOCK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    acquireLocks()
                    val title = call.argument<String>("title") ?: "YTDx Studio İndirme"
                    try {
                        DownloadForegroundService.start(applicationContext, title)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                    result.success(true)
                }
                "updateNotification" -> {
                    val title = call.argument<String>("title") ?: "YTDx Studio İndiriliyor..."
                    val progress = call.argument<Int>("progress") ?: 0
                    val speed = call.argument<String>("speed") ?: ""
                    val indeterminate = call.argument<Boolean>("indeterminate") ?: false
                    try {
                        DownloadForegroundService.update(applicationContext, title, progress, speed, indeterminate)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                    result.success(true)
                }
                "release" -> {
                    releaseLocks()
                    try {
                        DownloadForegroundService.stop(applicationContext)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun muxVideoAndAudio(videoPath: String, audioPath: String, outputPath: String): Boolean {
        val videoExtractor = MediaExtractor()
        val audioExtractor = MediaExtractor()
        var muxer: MediaMuxer? = null

        try {
            videoExtractor.setDataSource(videoPath)
            audioExtractor.setDataSource(audioPath)

            val outputFormat = if (outputPath.endsWith(".webm", ignoreCase = true) || outputPath.endsWith(".mkv", ignoreCase = true)) {
                MediaMuxer.OutputFormat.MUXER_OUTPUT_WEBM
            } else {
                MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4
            }
            muxer = MediaMuxer(outputPath, outputFormat)

            // Select video track
            var videoTrackIndex = -1
            var muxerVideoTrackIndex = -1
            for (i in 0 until videoExtractor.trackCount) {
                val format = videoExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/")) {
                    videoTrackIndex = i
                    videoExtractor.selectTrack(i)
                    muxerVideoTrackIndex = muxer.addTrack(format)
                    break
                }
            }

            // Select audio track
            var audioTrackIndex = -1
            var muxerAudioTrackIndex = -1
            for (i in 0 until audioExtractor.trackCount) {
                val format = audioExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    audioExtractor.selectTrack(i)
                    muxerAudioTrackIndex = muxer.addTrack(format)
                    break
                }
            }

            if (muxerVideoTrackIndex == -1 || muxerAudioTrackIndex == -1) {
                return false
            }

            muxer.start()

            val bufferSize = 2 * 1024 * 1024 // 2 MB Direct Buffer (reduces RAM footprint on older devices while safely handling 4K frames)
            val buffer = ByteBuffer.allocateDirect(bufferSize)
            val videoBufferInfo = MediaCodec.BufferInfo()
            val audioBufferInfo = MediaCodec.BufferInfo()

            var hasVideo = true
            var hasAudio = true
            var lastVideoTimeUs = -1L
            var lastAudioTimeUs = -1L

            // Interleave video and audio samples monotonically by presentation time (sampleTime)
            while (hasVideo || hasAudio) {
                val videoTime = if (hasVideo) videoExtractor.sampleTime else Long.MAX_VALUE
                val audioTime = if (hasAudio) audioExtractor.sampleTime else Long.MAX_VALUE

                if (hasVideo && (videoTime <= audioTime || !hasAudio)) {
                    buffer.clear()
                    videoBufferInfo.offset = 0
                    videoBufferInfo.size = videoExtractor.readSampleData(buffer, 0)
                    if (videoBufferInfo.size < 0) {
                        hasVideo = false
                    } else {
                        // Monotonic timestamp guarantee (prevents -EINVAL crash on B-frames in WebM/MP4)
                        val rawPts = Math.max(0L, videoTime)
                        val finalPts = if (rawPts < lastVideoTimeUs) lastVideoTimeUs else rawPts
                        lastVideoTimeUs = finalPts

                        videoBufferInfo.presentationTimeUs = finalPts
                        videoBufferInfo.flags = videoExtractor.sampleFlags
                        muxer.writeSampleData(muxerVideoTrackIndex, buffer, videoBufferInfo)
                        videoExtractor.advance()
                    }
                } else if (hasAudio) {
                    buffer.clear()
                    audioBufferInfo.offset = 0
                    audioBufferInfo.size = audioExtractor.readSampleData(buffer, 0)
                    if (audioBufferInfo.size < 0) {
                        hasAudio = false
                    } else {
                        // Monotonic timestamp guarantee for audio track
                        val rawPts = Math.max(0L, audioTime)
                        val finalPts = if (rawPts < lastAudioTimeUs) lastAudioTimeUs else rawPts
                        lastAudioTimeUs = finalPts

                        audioBufferInfo.presentationTimeUs = finalPts
                        audioBufferInfo.flags = audioExtractor.sampleFlags
                        muxer.writeSampleData(muxerAudioTrackIndex, buffer, audioBufferInfo)
                        audioExtractor.advance()
                    }
                }
            }

            return true
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "muxVideoAndAudio failed: ${e.message}", e)
            return false
        } finally {
            try { videoExtractor.release() } catch (e: Exception) {}
            try { audioExtractor.release() } catch (e: Exception) {}
            try {
                muxer?.stop()
                muxer?.release()
            } catch (e: Exception) {}
        }
    }

    override fun onDestroy() {
        releaseLocks()
        try {
            DownloadForegroundService.stop(applicationContext)
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
