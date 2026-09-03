package com.alllivesupport.ytdx.aura_app

import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

class MainActivity : AudioServiceActivity() {
    private val SHARE_CHANNEL = "com.alllivesupport.ytdxstudio/share"
    private val MUXER_CHANNEL = "com.alllivesupport.ytdxstudio/muxer"
    private var sharedText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
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
                    // Run heavy media processing off the UI thread to prevent ANR ("App Not Responding")
                    Thread {
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

            val bufferSize = 8 * 1024 * 1024 // 8 MB Direct Buffer for 4K/8K HDR video frames
            val buffer = ByteBuffer.allocateDirect(bufferSize)
            val videoBufferInfo = MediaCodec.BufferInfo()
            val audioBufferInfo = MediaCodec.BufferInfo()

            var hasVideo = true
            var hasAudio = true

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
                        videoBufferInfo.presentationTimeUs = videoTime
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
                        audioBufferInfo.presentationTimeUs = audioTime
                        audioBufferInfo.flags = audioExtractor.sampleFlags
                        muxer.writeSampleData(muxerAudioTrackIndex, buffer, audioBufferInfo)
                        audioExtractor.advance()
                    }
                }
            }

            return true
        } catch (e: Exception) {
            e.printStackTrace()
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
}
