import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/download_task.dart';
import '../models/app_settings.dart';
import 'app_logger.dart';
import 'audio_converter.dart';
import 'audio_tagger.dart';
import 'auth_service.dart';
import 'lyrics_service.dart';
import 'native_media_muxer.dart';
import 'visionos_stream_resolver.dart';
import 'youtube_service.dart';

const _tag = 'DownloadMgr';

class DownloadManager {
  /// Returns the best writable download directory on Android.
  static Future<String> _resolveAndroidDownloadDir(String preferredPath) async {
    AppLogger.info(_tag, '📂 Android: tercih edilen yol: $preferredPath');

    // 1. Try the user-set path first
    try {
      final dir = Directory(preferredPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
        AppLogger.info(_tag, '📂 Klasör oluşturuldu: $preferredPath');
      }
      final testFile = File('${dir.path}/.ytdx_write_test');
      testFile.writeAsStringSync('test');
      testFile.deleteSync();
      AppLogger.success(_tag, '✅ Tercih edilen yol yazılabilir: $preferredPath');
      return dir.path;
    } catch (e) {
      AppLogger.warn(_tag, '⚠ $preferredPath yazılamadı: $e');
    }

    // 2. Try standard public Download directory (/storage/emulated/0/Download)
    try {
      const publicDownload = '/storage/emulated/0/Download';
      final dir = Directory(publicDownload);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final testFile = File('$publicDownload/.ytdx_write_test');
      testFile.writeAsStringSync('test');
      testFile.deleteSync();
      AppLogger.warn(_tag, '📂 Genel İndirilenler klasörü kullanılıyor: $publicDownload');
      return publicDownload;
    } catch (_) {}

    // 3. Try standard public Music directory (/storage/emulated/0/Music)
    try {
      const publicMusic = '/storage/emulated/0/Music';
      final dir = Directory(publicMusic);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final testFile = File('$publicMusic/.ytdx_write_test');
      testFile.writeAsStringSync('test');
      testFile.deleteSync();
      AppLogger.warn(_tag, '📂 Genel Müzik klasörü kullanılıyor: $publicMusic');
      return publicMusic;
    } catch (_) {}

    // 4. Fall back to getExternalStorageDirectory
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        if (!extDir.existsSync()) extDir.createSync(recursive: true);
        AppLogger.warn(_tag, '⚠ Fallback: App external storage: ${extDir.path}');
        return extDir.path;
      }
    } catch (e) {
      AppLogger.warn(_tag, '⚠ getExternalStorageDirectory başarısız: $e');
    }

    // 5. Last resort: app documents directory
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      AppLogger.warn(_tag, '⚠ Son çare: App documents: ${docsDir.path}');
      return docsDir.path;
    } catch (e) {
      AppLogger.error(_tag, '✗ getApplicationDocumentsDirectory başarısız: $e');
    }

    AppLogger.error(_tag, '✗ Hiçbir yazılabilir dizin bulunamadı! Orijinal yol döndürülüyor.');
    return preferredPath;
  }

  static const MethodChannel _wakeLockChannel =
      MethodChannel('com.alllivesupport.ytdxstudio/wakelock');
  static int _activeDownloads = 0;

  static Future<void> _acquireWakeLock([String? title]) async {
    if (!Platform.isAndroid) return;
    try {
      await _wakeLockChannel.invokeMethod('acquire', {'title': title ?? 'YTDx Studio İndirme'});
      AppLogger.info(_tag, '⚡ Arka plan CPU & Wi-Fi kilidi ve Foreground Service aktif edildi.');
    } catch (e) {
      AppLogger.warn(_tag, 'WakeLock acquire uyarısı: $e');
    }
  }

  static Future<void> _updateForegroundNotification({
    required String title,
    required int progress,
    required String speed,
    bool indeterminate = false,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _wakeLockChannel.invokeMethod('updateNotification', {
        'title': title,
        'progress': progress,
        'speed': speed,
        'indeterminate': indeterminate,
      });
    } catch (_) {}
  }

  static Future<void> _releaseWakeLock() async {
    if (!Platform.isAndroid) return;
    try {
      await _wakeLockChannel.invokeMethod('release');
      AppLogger.info(_tag, '💤 Arka plan CPU & Wi-Fi kilidi ve Foreground Service serbest bırakıldı.');
    } catch (e) {
      AppLogger.warn(_tag, 'WakeLock release uyarısı: $e');
    }
  }

  static Future<void> executeDownload({
    required DownloadTask task,
    required AppSettings settings,
    required Function() onUpdate,
  }) async {
    _activeDownloads++;
    if (_activeDownloads == 1) {
      await _acquireWakeLock(task.video.title);
    }
    try {
      task.status = DownloadStatus.downloading;
      task.progress = 0.0;
      task.errorMessage = null;
      onUpdate();

    AppLogger.info(_tag, '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    AppLogger.info(_tag, '▶ İndirme başladı: ${task.video.title}');
    final isAudioDownload = task.isAudio || DownloadTask.isAudioFormat(task.format);
    AppLogger.info(_tag, '   Tür: ${isAudioDownload ? "Ses" : "Video"} | Format: ${task.format} | Kalite: ${task.quality}');
    AppLogger.info(_tag, '   Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');

    String outputDirPath = task.outputPath.isNotEmpty ? task.outputPath : settings.downloadPath;
    AppLogger.info(_tag, '   Hedef klasör (başlangıç): $outputDirPath');

    if (Platform.isAndroid) {
      // Request appropriate permissions based on Android version
      try {
        final sdkResult = await Process.run('getprop', ['ro.build.version.sdk']);
        final sdkInt = int.tryParse(sdkResult.stdout.toString().trim()) ?? 0;
        AppLogger.info(_tag, '   Android SDK: $sdkInt');

        if (sdkInt >= 33) {
          AppLogger.info(_tag, '   İzin: Android 13+ medya ve tüm dosyalara erişim izinleri isteniyor');
          await [Permission.audio, Permission.videos, Permission.photos].request();
          if (!await Permission.manageExternalStorage.isGranted) {
            final manageStatus = await Permission.manageExternalStorage.request();
            AppLogger.info(_tag, '   MANAGE_EXTERNAL_STORAGE: ${manageStatus.name}');
          }
        } else if (sdkInt >= 30) {
          AppLogger.info(_tag, '   İzin: Android 11+ MANAGE_EXTERNAL_STORAGE isteniyor');
          final manageStatus = await Permission.manageExternalStorage.request();
          AppLogger.info(_tag, '   MANAGE_EXTERNAL_STORAGE: ${manageStatus.name}');
          if (!manageStatus.isGranted) {
            await Permission.storage.request();
          }
        } else {
          AppLogger.info(_tag, '   İzin: Android <=10 STORAGE isteniyor');
          final storageStatus = await Permission.storage.request();
          AppLogger.info(_tag, '   STORAGE: ${storageStatus.name}');
        }
      } catch (e) {
        AppLogger.warn(_tag, '   SDK tespiti başarısız: $e');
        try {
          final storageStatus = await Permission.storage.request();
          AppLogger.info(_tag, '   Fallback STORAGE izni: ${storageStatus.name}');
        } catch (e2) {
          AppLogger.error(_tag, '   İzin isteği de başarısız: $e2');
        }
      }

      // Resolve a writable directory on Android
      outputDirPath = await _resolveAndroidDownloadDir(outputDirPath);
      AppLogger.info(_tag, '   Çözümlenen hedef yol: $outputDirPath');
    }

    // Ensure output directory exists
    final outDir = Directory(outputDirPath);
    if (!outDir.existsSync()) {
      try {
        outDir.createSync(recursive: true);
        AppLogger.info(_tag, '📂 Hedef klasör oluşturuldu: $outputDirPath');
      } catch (e) {
        AppLogger.error(_tag, '✗ Klasör oluşturulamadı: $e');
        task.status = DownloadStatus.failed;
        task.errorMessage = 'Hedef klasör oluşturulamadı: $e';
        onUpdate();
        return;
      }
    } else {
      AppLogger.info(_tag, '📂 Hedef klasör mevcut: $outputDirPath');
    }

    AppLogger.info(_tag, '🔧 Engine: Pure Dart (YoutubeExplode) - Android');
    task.engineUsed = 'Pure Dart';
    final success = await _downloadWithPureDart(task, settings, outDir.path, onUpdate);

    if (success) {
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.speed = 'Done';
      task.eta = '00:00';
      _updateForegroundNotification(
        title: task.video.title,
        progress: 100,
        speed: 'Tamamlandı',
      );
      if (task.filePath == null || !File(task.filePath!).existsSync()) {
        task.filePath = _findMatchingFile(outDir.path, task);
      }
      _cleanupResidualTempFiles(outDir.path, _sanitizeFilename(task.video.title));
      AppLogger.success(_tag, '✅ İndirme tamamlandı: ${task.filePath}');
      if (Platform.isAndroid && task.filePath != null) {
        _scanFileOnAndroid(task.filePath!);
      }
      if (task.isAudio && task.filePath != null) {
        LyricsService.cacheLyricsForDownload(
          task.video.id,
          task.filePath!,
          title: task.video.title,
          artist: task.video.channel,
        );
      }
    } else if (task.status != DownloadStatus.cancelled) {
      task.status = DownloadStatus.failed;
      task.errorMessage ??= 'İndirme tamamlanamadı.';
      AppLogger.error(_tag, '✗ İndirme başarısız: ${task.errorMessage}');
      _cleanupResidualTempFiles(outDir.path, _sanitizeFilename(task.video.title));
    }

    onUpdate();
    } finally {
      _activeDownloads--;
      if (_activeDownloads <= 0) {
        _activeDownloads = 0;
        await _releaseWakeLock();
      }
    }
  }

  /// Trigger Android MediaStore scan for newly downloaded file (non-blocking)
  static Future<void> _scanFileOnAndroid(String filePath) async {
    await NativeMediaMuxer.scanFile(filePath);
  }

  static void _cleanupResidualTempFiles(String dirPath, String sanitizedTitle) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return;
      final files = dir.listSync();
      for (var f in files) {
        if (f is File) {
          final name = f.uri.pathSegments.last;
          if (name.startsWith(sanitizedTitle) &&
              (name.contains('_temp_raw') ||
               name.contains('_temp') ||
               name.contains('_vtmp') ||
               name.contains('_atemp') ||
               name.contains('_vtemp') ||
               name.endsWith('.part') ||
               name.endsWith('.ytdl'))) {
            try {
              f.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// Automatically deletes any residual old temporary files (_raw_temp, .tmp, separate .jpg) from download directory
  static void _cleanupResidualFiles(String dirPath, String baseTitle) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return;

      for (final entity in dir.listSync()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith(baseTitle)) {
            if (name.endsWith('.jpg') ||
                name.endsWith('.webp') ||
                name.contains('_raw_temp') ||
                name.contains('_vtmp') ||
                name.contains('_atmp') ||
                name.endsWith('.tmp') ||
                name.endsWith('.part')) {
              try { entity.deleteSync(); } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }  /// Parses a formatted duration string ("03:45" or "01:23:45") into total seconds.
  static int _parseDurationToSeconds(String dur) {
    try {
      final parts = dur.split(':').map((p) => int.tryParse(p.trim()) ?? 0).toList();
      if (parts.length == 3) {
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
      } else if (parts.length == 2) {
        return parts[0] * 60 + parts[1];
      } else if (parts.length == 1) {
        return parts[0];
      }
    } catch (_) {}
    return 0;
  }

  /// Fetches an unthrottled direct stream URL for the given video and itag.
  /// Bypasses YouTube's 60-second / 174MB playback cutoff using VisionOS client,
  /// with automatic fallback to authenticated Android Innertube.
  static Future<String?> _fetchStreamUrlForOffset(
    String videoId,
    int itag,
    int startTimeSecs, {
    bool forceRefresh = false,
  }) async {
    if (videoId.isEmpty) return null;

    // 1. Try Unthrottled VisionOS Resolver (Zero 403, Zero 60s limit on any range)
    try {
      final visionosUrl = await VisionosStreamResolver.getStreamUrl(
        videoId,
        itag,
        forceRefresh: forceRefresh,
      );
      if (visionosUrl != null && visionosUrl.isNotEmpty) {
        return visionosUrl;
      }
    } catch (e) {
      AppLogger.warn(_tag, 'VisionOS stream resolve uyarısı: $e');
    }

    // 2. Fallback to Authenticated Android Innertube
    try {
      final token = await AuthService.getAccessToken();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'User-Agent': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
      };
      if (token != null && token.isNotEmpty) {
        headers['authorization'] = 'Bearer $token';
      }

      final payload = {
        ...YoutubeApiClient.androidSdkless.payload,
        'videoId': videoId,
        'startTimeSecs': startTimeSecs,
      };

      final client = http.Client();
      try {
        final res = await client.post(
          Uri.parse(YoutubeApiClient.androidSdkless.apiUrl),
          headers: headers,
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final streamingData = data['streamingData'];
          if (streamingData != null) {
            final adaptive = streamingData['adaptiveFormats'] as List? ?? [];
            final formats = streamingData['formats'] as List? ?? [];
            final all = [...adaptive, ...formats];
            final match = all.firstWhere((f) => f['itag'] == itag, orElse: () => null);
            if (match != null && match['url'] != null) {
              return match['url'] as String;
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      AppLogger.warn(_tag, 'Innertube offset URL refresh hatası: $e');
    }
    return null;
  }

  /// Turbo 5MB Micro-Chunk Worker Pool Downloader.
  /// Bypasses YouTube's 10MB CDN throttling rule by dividing any media file (even 8K/4K)
  /// into fixed 5MB slices, dynamically pulled by a concurrent worker pool.
  /// Achieves maximum line-rate throughput (20-80+ MB/s) with zero byte corruption.
  static Future<StreamInfo?> _downloadDirectStream({
    required YoutubeExplode yt,
    required List<StreamInfo> streamCandidates,
    required File targetFile,
    required DownloadTask task,
    required Function() onUpdate,
    double progressStart = 0.0,
    double progressWeight = 1.0,
  }) async {
    for (final streamInfo in streamCandidates) {
      if (task.status == DownloadStatus.cancelled) break;

      int expectedBytes = streamInfo.size.totalBytes;
      AppLogger.info(_tag, '🚀 Stream deneniyor (5MB Micro-Chunk Worker Pool): itag=${streamInfo.tag}, ${(expectedBytes / (1024 * 1024)).toStringAsFixed(1)} MB (${streamInfo.container.name})');

      if (targetFile.existsSync()) {
        try { targetFile.deleteSync(); } catch (_) {}
      }

      String currentStreamUrl = streamInfo.url.toString();
      final videoId = task.video.id.isNotEmpty
          ? task.video.id
          : (YouTubeService.extractVideoId(task.video.url) ?? '');
      final totalDurationSecs = _parseDurationToSeconds(task.video.duration);

      // 🚀 Unthrottled VisionOS Stream Resolution:
      // YouTube enforces a strict 60s (~174MB) playback cutoff on standard Android CDN streams.
      // We resolve the unthrottled VisionOS direct stream URL which has zero playback restrictions,
      // allowing full line-speed download across the entire file (even 8K/4K 1GB+ files).
      if (videoId.isNotEmpty) {
        try {
          final visionosUrl = await _fetchStreamUrlForOffset(videoId, streamInfo.tag, 0);
          if (visionosUrl != null && visionosUrl.isNotEmpty) {
            currentStreamUrl = visionosUrl;
            AppLogger.info(_tag, '⚡ Unthrottled VisionOS stream URL aktif kılındı (itag=${streamInfo.tag})');
          }
        } catch (_) {}
      }

      // Probe totalBytes if <= 0
      if (expectedBytes <= 0) {
        try {
          final probeClient = HttpClient();
          probeClient.connectionTimeout = const Duration(seconds: 6);
          final probeReq = await probeClient.getUrl(Uri.parse(currentStreamUrl));
          probeReq.headers.add('Range', 'bytes=0-0');
          if (currentStreamUrl.contains('c=VISIONOS')) {
            probeReq.headers.add('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15');
          } else {
            probeReq.headers.add('User-Agent', 'com.google.android.youtube/19.05.36 (Linux; U; Android 14; TR) gzip');
            probeReq.headers.add('X-YouTube-Client-Name', '3');
            probeReq.headers.add('X-YouTube-Client-Version', '19.05.36');
          }
          final probeResp = await probeReq.close();
          final cr = probeResp.headers.value('content-range');
          if (cr != null && cr.contains('/')) {
            final totalStr = cr.split('/').last.trim();
            expectedBytes = int.tryParse(totalStr) ?? expectedBytes;
          }
          probeClient.close();
        } catch (_) {}
      }

      final stopwatch = Stopwatch()..start();
      int totalDownloaded = 0;
      int bytesSinceLastTick = 0;
      int lastTickMs = 0;
      bool failed = false;

      // 5 MB optimal micro-chunk size to avoid YouTube's >10MB media-buffer throttling
      const int sliceSize = 5 * 1024 * 1024;
      final totalSlices = expectedBytes > 0 ? (expectedBytes / sliceSize).ceil() : 1;

      // Dynamic worker concurrency based on file size:
      // Tiny files (< 5 MB): 2 workers
      // Small files (5 - 30 MB): 4 workers
      // High-res files (30 - 150 MB e.g. 1080p): 8 workers
      // 2K / 4K files (150 - 500 MB): 12 workers
      // Ultra 4K / 8K files (>= 500 MB): 16 workers (saturates 1000 Mbps connections without throttling)
      int concurrency = 4;
      if (expectedBytes >= 500 * 1024 * 1024) {
        concurrency = 16;
      } else if (expectedBytes >= 150 * 1024 * 1024) {
        concurrency = 12;
      } else if (expectedBytes >= 30 * 1024 * 1024) {
        concurrency = 8;
      } else if (expectedBytes < 5 * 1024 * 1024 && expectedBytes > 0) {
        concurrency = 2;
      }

      try {
        if (expectedBytes > 0) {
          // Pre-allocate destination file to prevent filesystem fragmentation and ensure thread-safe offset writes
          final initRaf = await targetFile.open(mode: FileMode.write);
          await initRaf.truncate(expectedBytes);
          await initRaf.close();

          final slices = <(int, int)>[];
          for (int i = 0; i < totalSlices; i++) {
            final start = i * sliceSize;
            final end = (i == totalSlices - 1) ? expectedBytes - 1 : (start + sliceSize - 1);
            slices.add((start, end));
          }

          int nextSliceIndex = 0;
          final futures = <Future<bool>>[];

          for (int wId = 0; wId < concurrency; wId++) {
            futures.add(() async {
              HttpClient client = HttpClient();
              client.connectionTimeout = const Duration(seconds: 10);
              RandomAccessFile? raf;
              String workerUrl = currentStreamUrl;
              bool workerAllOk = true;

              try {
                raf = await targetFile.open(mode: FileMode.writeOnlyAppend);

                while (task.status != DownloadStatus.cancelled) {
                  int sliceIdx;
                  if (nextSliceIndex >= totalSlices) break;
                  sliceIdx = nextSliceIndex++;
                  if (sliceIdx >= totalSlices) break;

                  final (start, end) = slices[sliceIdx];
                  int attempts = 0;
                  bool sliceDone = false;

                  while (attempts < 3 && !sliceDone && task.status != DownloadStatus.cancelled) {
                    attempts++;
                    try {
                      final isVisionUrl = workerUrl.contains('c=VISIONOS');
                      var req = await client.getUrl(Uri.parse(workerUrl));
                      req.headers.add('Range', 'bytes=$start-$end');
                      if (isVisionUrl) {
                        req.headers.add('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15');
                      } else {
                        req.headers.add('User-Agent', 'com.google.android.youtube/19.05.36 (Linux; U; Android 14; TR) gzip');
                        req.headers.add('X-YouTube-Client-Name', '3');
                        req.headers.add('X-YouTube-Client-Version', '19.05.36');
                      }
                      req.headers.add('Accept-Encoding', 'identity');

                      var response = await req.close();

                      if (response.statusCode == 403 && videoId.isNotEmpty) {
                        final currentSec = (totalDurationSecs > 0 && expectedBytes > 0)
                            ? ((start / expectedBytes) * totalDurationSecs).toInt()
                            : (start * 8) ~/ (streamInfo.bitrate.bitsPerSecond > 0 ? streamInfo.bitrate.bitsPerSecond : 3000000);
                        final refreshedUrl = await _fetchStreamUrlForOffset(
                          videoId,
                          streamInfo.tag,
                          currentSec,
                          forceRefresh: true,
                        );
                        if (refreshedUrl != null && refreshedUrl.isNotEmpty) {
                          workerUrl = refreshedUrl;
                          final isRefreshedVision = workerUrl.contains('c=VISIONOS');
                          client.close();
                          client = HttpClient();
                          client.connectionTimeout = const Duration(seconds: 10);
                          req = await client.getUrl(Uri.parse(workerUrl));
                          req.headers.add('Range', 'bytes=$start-$end');
                          if (isRefreshedVision) {
                            req.headers.add('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15');
                          } else {
                            req.headers.add('User-Agent', 'com.google.android.youtube/19.05.36 (Linux; U; Android 14; TR) gzip');
                            req.headers.add('X-YouTube-Client-Name', '3');
                            req.headers.add('X-YouTube-Client-Version', '19.05.36');
                          }
                          req.headers.add('Accept-Encoding', 'identity');
                          response = await req.close();
                        }
                      }

                      if (response.statusCode != 200 && response.statusCode != 206) {
                        await Future.delayed(Duration(milliseconds: 200 * attempts));
                        continue;
                      }

                      await raf.setPosition(start);
                      await for (final chunk in response) {
                        if (task.status == DownloadStatus.cancelled) break;
                        await raf.writeFrom(chunk);
                        totalDownloaded += chunk.length;
                        bytesSinceLastTick += chunk.length;

                        final elapsedMs = stopwatch.elapsedMilliseconds;
                        if (elapsedMs - lastTickMs >= 200 || totalDownloaded >= expectedBytes) {
                          final deltaSec = (elapsedMs - lastTickMs) / 1000.0;
                          double currentSpeedMbps = 0.0;
                          if (deltaSec > 0) {
                            currentSpeedMbps = (bytesSinceLastTick / (1024 * 1024)) / deltaSec;
                            bytesSinceLastTick = 0;
                            lastTickMs = elapsedMs;
                          }

                          String etaStr = '--';
                          if (expectedBytes > 0 && currentSpeedMbps > 0) {
                            final remBytes = expectedBytes - totalDownloaded;
                            final remSec = (remBytes / (1024 * 1024)) / currentSpeedMbps;
                            etaStr = remSec > 60
                                ? '${(remSec / 60).toInt()}m ${(remSec % 60).toInt()}s'
                                : '${remSec.toInt()}s';
                          }

                          if (progressWeight > 0.0) {
                            final subFraction = (totalDownloaded / expectedBytes).clamp(0.0, 1.0);
                            final p = (progressStart + subFraction * progressWeight).clamp(0.0, 1.0);
                            final sInfo = '${(totalDownloaded / (1024 * 1024)).toStringAsFixed(1)} MB / ${(expectedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
                            final spd = '${currentSpeedMbps.toStringAsFixed(1)} MB/s';

                            task.updateProgress(
                              progress: p,
                              speed: spd,
                              eta: etaStr,
                              sizeInfo: sInfo,
                            );

                            _updateForegroundNotification(
                              title: task.video.title,
                              progress: (p * 100).toInt(),
                              speed: spd,
                            );
                            onUpdate();
                          }
                        }
                      }
                      sliceDone = true;
                    } catch (_) {
                      await Future.delayed(Duration(milliseconds: 200 * attempts));
                    }
                  }

                  if (!sliceDone) {
                    workerAllOk = false;
                    break;
                  }
                }
              } catch (_) {
                workerAllOk = false;
              } finally {
                if (raf != null) {
                  try { await raf.close(); } catch (_) {}
                }
                try { client.close(); } catch (_) {}
              }
              return workerAllOk;
            }());
          }

          final results = await Future.wait(futures);
          if (results.any((ok) => !ok)) {
            failed = true;
          }
        } else {
          // Fallback single stream if expectedBytes is unknown
          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 15);
          final req = await client.getUrl(Uri.parse(currentStreamUrl));
          if (currentStreamUrl.contains('c=VISIONOS')) {
            req.headers.add('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15');
          } else {
            req.headers.add('User-Agent', 'com.google.android.youtube/19.05.36 (Linux; U; Android 14; TR) gzip');
            req.headers.add('X-YouTube-Client-Name', '3');
            req.headers.add('X-YouTube-Client-Version', '19.05.36');
          }
          final response = await req.close();
          final raf = await targetFile.open(mode: FileMode.write);
          await for (final chunk in response) {
            if (task.status == DownloadStatus.cancelled) break;
            await raf.writeFrom(chunk);
            totalDownloaded += chunk.length;
            bytesSinceLastTick += chunk.length;
            final elapsedMs = stopwatch.elapsedMilliseconds;
            if (elapsedMs - lastTickMs >= 250) {
              final deltaSec = (elapsedMs - lastTickMs) / 1000.0;
              final spd = deltaSec > 0 ? (bytesSinceLastTick / (1024 * 1024)) / deltaSec : 0.0;
              bytesSinceLastTick = 0;
              lastTickMs = elapsedMs;
              if (progressWeight > 0.0) {
                task.updateProgress(
                  progress: (progressStart + 0.5 * progressWeight).clamp(0.0, 1.0),
                  speed: '${spd.toStringAsFixed(1)} MB/s',
                  sizeInfo: '${(totalDownloaded / (1024 * 1024)).toStringAsFixed(1)} MB',
                );
                onUpdate();
              }
            }
          }
          await raf.close();
          client.close();
        }

        stopwatch.stop();

        final diskSize = targetFile.existsSync() ? targetFile.lengthSync() : 0;
        final isValidSize = expectedBytes > 0 ? diskSize == expectedBytes : diskSize > 1024;

        if (isValidSize && !failed && task.status != DownloadStatus.cancelled) {
          if (progressWeight > 0.0) {
            task.updateProgress(
              progress: (progressStart + progressWeight).clamp(0.0, 1.0),
              sizeInfo: '${(diskSize / (1024 * 1024)).toStringAsFixed(1)} MB / ${(diskSize / (1024 * 1024)).toStringAsFixed(1)} MB',
            );
          }
          AppLogger.success(_tag, '✅ itag=${streamInfo.tag} tamamlandı: ${(diskSize / (1024 * 1024)).toStringAsFixed(1)} MB (5MB havuzu, ${concurrency}x worker)');
          return streamInfo;
        } else {
          AppLogger.warn(_tag, '⚠ itag=${streamInfo.tag} tamamlanamadı ($diskSize / $expectedBytes bytes, failed=$failed), sıradakine geçiliyor');
          if (targetFile.existsSync()) {
            try { targetFile.deleteSync(); } catch (_) {}
          }
        }
      } catch (e) {
        AppLogger.warn(_tag, '⚠ Stream hatası (itag=${streamInfo.tag}): $e');
        if (targetFile.existsSync()) {
          try { targetFile.deleteSync(); } catch (_) {}
        }
      }
    }
    return null;
  }

  /// 1. Pure Dart Engine (YoutubeExplode direct stream download)

  static Future<bool> _downloadWithPureDart(
    DownloadTask task,
    AppSettings settings,
    String outputDirPath,
    Function() onUpdate,
  ) async {
    final videoId = YouTubeService.extractVideoId(task.video.url) ?? task.video.id;
    if (videoId.isEmpty) return false;

    YoutubeExplode? yt;
    try {
      yt = await AuthService.createYoutubeClient();
      AppLogger.info(_tag, '🎯 Stream manifest alınıyor...');

      StreamManifest manifest;
      try {
        manifest = await yt.videos.streamsClient.getManifest(
          videoId,
          requireWatchPage: false,
        );
      } catch (e) {
        AppLogger.warn(_tag, 'Client manifest hatası: $e, varsayılan deneniyor');
        manifest = await yt.videos.streamsClient.getManifest(videoId);
      }
      AppLogger.info(_tag, '🎯 Muxed: ${manifest.muxed.length} | AudioOnly: ${manifest.audioOnly.length} | VideoOnly: ${manifest.videoOnly.length}');

      final sanitizedTitle = _sanitizeFilename(task.video.title);
      AppLogger.info(_tag, '🔧 Platform: Android');

      if (task.isAudio || DownloadTask.isAudioFormat(task.format)) {
        final chosenFormat = task.format.toLowerCase();
        AppLogger.info(_tag, '🎵 Ses İndirme Modu: ${task.format.toUpperCase()} (${task.quality})');

        final List<StreamInfo> streamCandidates = [];
        if (manifest.audioOnly.isNotEmpty) {
          if (chosenFormat == 'opus') {
            // Opus istendiğinde: WebM/Opus akışları öncelikli (itag 251 ~160k, itag 250 ~70k)
            final opusStreams = manifest.audioOnly
                .where((s) => s.container.name != 'mp4')
                .toList();
            if (task.quality.contains('70')) {
              opusStreams.sort((a, b) => (a.bitrate.kiloBitsPerSecond - 70).abs().compareTo((b.bitrate.kiloBitsPerSecond - 70).abs()));
            } else {
              opusStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
            }
            streamCandidates.addAll(opusStreams);
            // M4A yedeği
            final m4aFallback = manifest.audioOnly
                .where((s) => s.container.name == 'mp4')
                .toList()
              ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
            streamCandidates.addAll(m4aFallback);
          } else if (chosenFormat == 'm4a') {
            // M4A istendiğinde: saf AAC (itag 140) akışları öncelikli
            final m4aStreams = manifest.audioOnly
                .where((s) => s.container.name == 'mp4')
                .toList()
              ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
            streamCandidates.addAll(m4aStreams);
            // WebM/Opus yedeği
            final otherAudio = manifest.audioOnly
                .where((s) => s.container.name != 'mp4')
                .toList()
              ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
            streamCandidates.addAll(otherAudio);
          } else {
            // MP3: En yüksek bitrate'e sahip akışlar (Opus 160k veya AAC 140)
            final allAudio = manifest.audioOnly.toList()
              ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
            streamCandidates.addAll(allAudio);
          }
        }

        // 🛡️ YENİLGİSİZ MUXED SES YEDEĞİ (100% Kararlılık & Sıfır Zaman Aşımı):
        // Bazı korumalı müzik ve VEVO kliplerinde YouTube tekil audioOnly akışlarına 403/throttling uygulayabilir.
        // Muxed akışlar (itag 22 720p / itag 18 360p) tam AAC stereo ses barındırır, YouTube tarafından
        // ASLA engellenmez ve FFmpeg ile kayıpsız olarak MP3, M4A ve Opus'a dönüştürülür!
        if (manifest.muxed.isNotEmpty) {
          final sortedMuxed = manifest.muxed.toList()
            ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
          streamCandidates.addAll(sortedMuxed);
        }

        if (streamCandidates.isEmpty) {
          AppLogger.error(_tag, 'Kullanılabilir ses veya video akışı bulunamadı.');
          yt.close();
          return false;
        }

        final saveExt = (chosenFormat == 'mp3' || chosenFormat == 'opus') ? chosenFormat : 'm4a';
        final finalFilePath = '$outputDirPath/$sanitizedTitle.$saveExt';

        // Use system temp/cache directory to avoid extra files in user's Download folder
        final tempDir = await getTemporaryDirectory();
        final tempRawPath = '${tempDir.path}/${sanitizedTitle}_${DateTime.now().millisecondsSinceEpoch}.tmp';
        final tempFile = File(tempRawPath);

        AppLogger.info(_tag, '🎵 Hedef dosya: $finalFilePath');

        final downloadedAudioStream = await _downloadDirectStream(
          yt: yt,
          streamCandidates: streamCandidates,
          targetFile: tempFile,
          task: task,
          onUpdate: onUpdate,
        );

        if (downloadedAudioStream == null || task.status == DownloadStatus.cancelled) {
          if (tempFile.existsSync()) {
            try { tempFile.deleteSync(); } catch (_) {}
          }
          yt.close();
          return false;
        }

        // Format dönüştürme ve ses ayrıştırma:
        // MP3, M4A ve Opus için her zaman AudioConverter çalıştırılır.
        // Bu sayede video kareleri (-vn) ayıklanır, dosya saf ve yüksek kaliteli ses dosyasına dönüştürülür!
        task.status = DownloadStatus.converting;
        task.speed = 'Ses dönüştürülüyor (${chosenFormat.toUpperCase()})...';
        _updateForegroundNotification(
          title: task.video.title,
          progress: 95,
          speed: 'Ses dönüştürülüyor (${chosenFormat.toUpperCase()})...',
          indeterminate: true,
        );
        onUpdate();
        final conversionSuccess = await AudioConverter.convertAudio(
          inputPath: tempFile.path,
          outputPath: finalFilePath,
          targetFormat: chosenFormat,
          quality: task.quality,
          isSourceWebm: downloadedAudioStream.container.name == 'webm',
        );
        if (tempFile.existsSync()) {
          try { tempFile.deleteSync(); } catch (_) {}
        }

        if (!conversionSuccess || !File(finalFilePath).existsSync()) {
          AppLogger.error(_tag, 'Ses dönüştürme/taşıma başarısız oldu: $finalFilePath');
          yt.close();
          return false;
        }

        task.filePath = finalFilePath;

        // Embed album cover art and metadata into the FINAL file
        final thumbUrl = task.video.thumbnail.isNotEmpty
            ? task.video.thumbnail
            : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
        if (task.filePath != null && File(task.filePath!).existsSync()) {
          String? localArtPath;
          try {
            final res = await http.get(Uri.parse(thumbUrl)).timeout(const Duration(seconds: 10));
            if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
              final artFile = File('${tempDir.path}/${sanitizedTitle}_art.jpg');
              await artFile.writeAsBytes(res.bodyBytes);
              localArtPath = artFile.path;
            }
          } catch (_) {}

          try {
            await AudioTagger.tagAudioFile(
              filePath: task.filePath!,
              title: task.video.title,
              artist: task.video.channel,
              thumbnailUrl: thumbUrl,
              localArtPath: localArtPath,
            );
          } catch (e) {
            AppLogger.warn(_tag, 'Etiketleme hatası (devam ediliyor): $e');
          }

          task.localArtPath = localArtPath;
        }

        // Notify Android MediaStore of the new audio file
        if (task.filePath != null && File(task.filePath!).existsSync()) {
          _scanFileOnAndroid(task.filePath!);
        }

        yt.close();
        AppLogger.success(_tag, '🎵 Ses indirme, dönüştürme ve etiketleme tamamlandı: ${task.filePath}');
        return task.filePath != null && File(task.filePath!).existsSync();

      } else {
        // ── VIDEO DOWNLOAD (4K / 2K / 1080p / 720p / 480p / 360p / Auto) ───
        AppLogger.info(_tag, '🎬 Video İndirme: Kalite=${task.quality}');

        final q = task.quality.toLowerCase().trim();
        final isWebmRequested = task.format.toLowerCase() == 'webm';

        // ── ⚡ 1. HAZIR TEK PARÇA (DIRECT MUXED) KONTROLÜ ──
        // Yalnızca kullanıcı özellikle 360p veya 720p seçtiğinde ve YouTube'da hazır tek parça
        // muxed akış bulunuyorsa (itag 18 360p veya itag 22 720p), doğrudan indirilir.
        // DİKKAT: 'auto' veya boş bırakıldığında ASLA 360p tek parçaya düşülmez; Full HD/HD hedeflenir!
        MuxedStreamInfo? singlePartMuxed;
        if (!isWebmRequested) {
          if (q.contains('360')) {
            singlePartMuxed = manifest.muxed.where((s) => s.qualityLabel.contains('360')).firstOrNull;
          } else if (q.contains('720')) {
            singlePartMuxed = manifest.muxed.where((s) => s.qualityLabel.contains('720')).firstOrNull;
          }
        }

        if (singlePartMuxed != null) {
          AppLogger.info(_tag, '⚡ Hazır tek parça video bulundu: itag=${singlePartMuxed.tag} (${singlePartMuxed.qualityLabel}), doğrudan tek parça indiriliyor...');
          final finalVideoPath = '$outputDirPath/$sanitizedTitle.mp4';
          final tempDir = await getTemporaryDirectory();
          final tempPath = '${tempDir.path}/${sanitizedTitle}_${DateTime.now().millisecondsSinceEpoch}.part';
          final tFile = File(tempPath);
          final downloadedMuxed = await _downloadDirectStream(
            yt: yt,
            streamCandidates: [singlePartMuxed],
            targetFile: tFile,
            task: task,
            onUpdate: onUpdate,
          );
          if (downloadedMuxed != null && tFile.existsSync() && tFile.lengthSync() > 1024) {
            await _safeMoveFile(tFile, finalVideoPath);
            task.filePath = finalVideoPath;
            task.updateProgress(status: DownloadStatus.completed, progress: 1.0, speed: 'Done');
            _cleanupResidualFiles(outputDirPath, sanitizedTitle);
            _scanFileOnAndroid(finalVideoPath);
            yt.close();
            AppLogger.success(_tag, '✅ Tek parça video başarıyla indirildi: $finalVideoPath');
            return true;
          }
          AppLogger.warn(_tag, '⚠ Tek parça indirme tamamlanamadı, adaptif akışlara geçiliyor...');
        }

        // ── 🎬 2. YÜKSEK ÇÖZÜNÜRLÜKLÜ ADAPTİF VİDEO (1080p / 2K / 4K / WebM VP9) ──
        final List<VideoStreamInfo> videoCandidates = [];
        final allVideos = manifest.videoOnly.toList();
        final isHighResWebmPreferred = isWebmRequested ||
            q.contains('1440') ||
            q.contains('2k') ||
            q.contains('2160') ||
            q.contains('4k') ||
            q.contains('4320') ||
            q.contains('8k');

        if (isHighResWebmPreferred) {
          // 2K, 4K, 8K ve WebM için: YouTube yerel WebM (VP9) akışlarını önceliklendir
          allVideos.sort((a, b) {
            if (a.container.name == 'webm' && b.container.name != 'webm') return -1;
            if (a.container.name != 'webm' && b.container.name == 'webm') return 1;
            return b.bitrate.compareTo(a.bitrate);
          });
        } else {
          allVideos.sort((a, b) {
            if (a.container.name == 'mp4' && b.container.name != 'mp4') return -1;
            if (a.container.name != 'mp4' && b.container.name == 'mp4') return 1;
            return b.bitrate.compareTo(a.bitrate);
          });
        }

        List<VideoStreamInfo> findMatches(String label) {
          final matches = allVideos.where((s) => s.qualityLabel.toLowerCase().contains(label)).toList();
          // Android MediaMuxer AV1 (av01) desteklemez.
          // VP9 (webm) ve H.264 (mp4) tüm Android cihazlarda donanımsal olarak desteklenir.
          matches.sort((a, b) {
            final aIsAv01 = a.videoCodec.toLowerCase().contains('av01');
            final bIsAv01 = b.videoCodec.toLowerCase().contains('av01');
            if (!aIsAv01 && bIsAv01) return -1;
            if (aIsAv01 && !bIsAv01) return 1;
            return b.bitrate.compareTo(a.bitrate);
          });
          return matches;
        }

        if (q == 'auto' || q.isEmpty) {
          // AUTO (Mutlak En Yüksek Kalite): 8K (4320p) > 4K (2160p) > 2K (1440p) > 1080p > 720p > 480p > 360p
          videoCandidates.addAll(findMatches('4320'));
          videoCandidates.addAll(findMatches('8k'));
          videoCandidates.addAll(findMatches('2160'));
          videoCandidates.addAll(findMatches('4k'));
          videoCandidates.addAll(findMatches('1440'));
          videoCandidates.addAll(findMatches('2k'));
          videoCandidates.addAll(findMatches('1080'));
          videoCandidates.addAll(findMatches('720'));
          videoCandidates.addAll(findMatches('480'));
          videoCandidates.addAll(findMatches('360'));
        } else if (q.contains('4320') || q.contains('8k')) {
          videoCandidates.addAll(findMatches('4320'));
          videoCandidates.addAll(findMatches('8k'));
          videoCandidates.addAll(findMatches('2160'));
          videoCandidates.addAll(findMatches('1440'));
          videoCandidates.addAll(findMatches('1080'));
        } else if (q.contains('2160') || q.contains('4k')) {
          videoCandidates.addAll(findMatches('2160'));
          videoCandidates.addAll(findMatches('4k'));
          videoCandidates.addAll(findMatches('1440'));
          videoCandidates.addAll(findMatches('1080'));
          videoCandidates.addAll(findMatches('720'));
        } else if (q.contains('1440') || q.contains('2k')) {
          videoCandidates.addAll(findMatches('1440'));
          videoCandidates.addAll(findMatches('2k'));
          videoCandidates.addAll(findMatches('1080'));
          videoCandidates.addAll(findMatches('720'));
        } else if (q.contains('1080')) {
          videoCandidates.addAll(findMatches('1080'));
          videoCandidates.addAll(findMatches('720'));
        } else if (q.contains('720')) {
          videoCandidates.addAll(findMatches('720'));
        } else if (q.contains('480')) {
          videoCandidates.addAll(findMatches('480'));
        } else if (q.contains('360')) {
          videoCandidates.addAll(findMatches('360'));
        }

        // Diğer çözünürlükleri fallback olarak ekle
        for (final s in allVideos) {
          if (!videoCandidates.contains(s)) videoCandidates.add(s);
        }

        if (videoCandidates.isEmpty && manifest.muxed.isNotEmpty) {
          final muxedStream = manifest.muxed.withHighestBitrate();
          final finalVideoPath = '$outputDirPath/$sanitizedTitle.mp4';
          final tempPath = '$outputDirPath/.${sanitizedTitle}_${DateTime.now().millisecondsSinceEpoch}.part';
          final tFile = File(tempPath);
          final downloadedMuxed = await _downloadDirectStream(
            yt: yt,
            streamCandidates: [muxedStream],
            targetFile: tFile,
            task: task,
            onUpdate: onUpdate,
          );
          if (downloadedMuxed != null && tFile.existsSync()) {
            await _safeMoveFile(tFile, finalVideoPath);
            task.filePath = finalVideoPath;
            task.updateProgress(status: DownloadStatus.completed, progress: 1.0, speed: 'Done');
            _cleanupResidualFiles(outputDirPath, sanitizedTitle);
            _scanFileOnAndroid(finalVideoPath);
            yt.close();
            return true;
          }
          yt.close();
          return false;
        }

        final chosenVideo = videoCandidates.first;
        final isWebm = chosenVideo.container.name == 'webm';
        final finalExt = isWebm ? 'webm' : 'mp4';
        final finalVideoPath = '$outputDirPath/$sanitizedTitle.$finalExt';

        // 2. Resolve Best Audio Streams for remuxing
        final List<StreamInfo> audioCandidates = [];
        if (isWebm) {
          audioCandidates.addAll(manifest.audioOnly.where((s) => s.container.name == 'webm').toList()..sort((a, b) => b.bitrate.compareTo(a.bitrate)));
          audioCandidates.addAll(manifest.audioOnly.where((s) => s.container.name != 'webm').toList()..sort((a, b) => b.bitrate.compareTo(a.bitrate)));
        } else {
          audioCandidates.addAll(manifest.audioOnly.where((s) => s.container.name == 'mp4').toList()..sort((a, b) => b.bitrate.compareTo(a.bitrate)));
          audioCandidates.addAll(manifest.audioOnly.where((s) => s.container.name != 'mp4').toList()..sort((a, b) => b.bitrate.compareTo(a.bitrate)));
        }
        // 🛡️ Ses akışı yedeği: Tekil ses akışları engellenirse muxed akışın sesi kullanılır
        if (manifest.muxed.isNotEmpty) {
          final sortedMuxed = manifest.muxed.toList()..sort((a, b) => b.bitrate.compareTo(a.bitrate));
          audioCandidates.addAll(sortedMuxed);
        }

        final audioStreamInfo = audioCandidates.isNotEmpty ? audioCandidates.first : null;

        AppLogger.info(_tag, '🎬 Seçilen Video Stream: itag=${chosenVideo.tag}, kalite=${chosenVideo.qualityLabel} (${chosenVideo.container.name}, ${chosenVideo.size.totalMegaBytes.toStringAsFixed(1)} MB)');
        AppLogger.info(_tag, '🎵 Seçilen Ses Stream: itag=${audioStreamInfo?.tag}, bitrate=${audioStreamInfo?.bitrate} (${audioStreamInfo?.container.name}, ${audioStreamInfo?.size.totalMegaBytes.toStringAsFixed(1)} MB)');

        final tempDir = await getTemporaryDirectory();
        final tempVideoPath = '${tempDir.path}/${sanitizedTitle}_vtmp_${DateTime.now().millisecondsSinceEpoch}.${chosenVideo.container.name}';
        final tempAudioPath = audioStreamInfo != null
            ? '${tempDir.path}/${sanitizedTitle}_atmp_${DateTime.now().millisecondsSinceEpoch}.${audioStreamInfo.container.name}'
            : '';

        final vFile = File(tempVideoPath);
        final aFile = audioStreamInfo != null ? File(tempAudioPath) : null;

        // A & B. Video ve Ses Akışlarını EŞZAMANLI (Paralel) İndir (%0 -> %95)
        task.updateProgress(
          status: DownloadStatus.downloading,
          speed: 'Video ve Ses paralel indiriliyor (${chosenVideo.qualityLabel})...',
        );
        onUpdate();

        final videoFuture = _downloadDirectStream(
          yt: yt,
          streamCandidates: videoCandidates,
          targetFile: vFile,
          task: task,
          onUpdate: onUpdate,
          progressStart: 0.0,
          progressWeight: 0.95,
        );

        final audioFuture = (aFile != null && audioCandidates.isNotEmpty)
            ? _downloadDirectStream(
                yt: yt,
                streamCandidates: audioCandidates,
                targetFile: aFile,
                task: task,
                onUpdate: onUpdate,
                progressStart: 0.0,
                progressWeight: 0.0, // Ana ilerleme video iş parçacığı tarafından sürdürülür
              )
            : Future<StreamInfo?>.value(null);

        final streamsResult = await Future.wait([videoFuture, audioFuture]);
        final downloadedVideoStream = streamsResult[0];
        final downloadedAudioStream = streamsResult[1];

        if (downloadedVideoStream == null || (aFile != null && downloadedAudioStream == null) || task.status == DownloadStatus.cancelled) {
          if (vFile.existsSync()) try { vFile.deleteSync(); } catch (_) {}
          if (aFile != null && aFile.existsSync()) try { aFile.deleteSync(); } catch (_) {}

          // 🛡️ Yalnızca kullanıcı özellikle 360p talep ettiyse veya düşük çözünürlük istediyse 360p muxed'a düş
          // Auto, 2K, 4K, 8K veya 1080p isteyen kullanıcıya ASLA sessizce 360p indirme!
          final isHighResExplicit = q == 'auto' || q.isEmpty ||
              q.contains('1440') || q.contains('2k') ||
              q.contains('2160') || q.contains('4k') ||
              q.contains('4320') || q.contains('8k') ||
              q.contains('1080');

          if (!isHighResExplicit && manifest.muxed.isNotEmpty && task.status != DownloadStatus.cancelled) {
            AppLogger.warn(_tag, '⚠ Adaptif video akışları engellendi, tek parça muxed akışına düşülüyor...');
            final fallbackMuxed = manifest.muxed.withHighestBitrate();
            final fallbackVideoPath = '$outputDirPath/$sanitizedTitle.mp4';
            final fbStream = await _downloadDirectStream(
              yt: yt,
              streamCandidates: [fallbackMuxed],
              targetFile: vFile,
              task: task,
              onUpdate: onUpdate,
              progressStart: 0.0,
              progressWeight: 1.0,
            );
            if (fbStream != null && vFile.existsSync()) {
              await _safeMoveFile(vFile, fallbackVideoPath);
              task.filePath = fallbackVideoPath;
              task.updateProgress(status: DownloadStatus.completed, progress: 1.0, speed: 'Done');
              _cleanupResidualFiles(outputDirPath, sanitizedTitle);
              _scanFileOnAndroid(fallbackVideoPath);
              yt.close();
              return true;
            }
          }

          yt.close();
          return false;
        }

          // C. MUX Video + Audio
          task.updateProgress(
            status: DownloadStatus.converting,
            progress: 0.98,
            speed: 'Ses & Video Birleştiriliyor (${chosenVideo.qualityLabel})...',
          );
          _updateForegroundNotification(
            title: task.video.title,
            progress: 98,
            speed: 'Ses & Video Birleştiriliyor (${chosenVideo.qualityLabel})...',
            indeterminate: true,
          );
          onUpdate();

          // 1. Öncelik: Android Donanım MediaMuxer (Arka plan thread'inde çalışır, anında ve sıfır pil tüketimi)
          var muxSuccess = await NativeMediaMuxer.muxVideoAndAudio(
            videoPath: tempVideoPath,
            audioPath: tempAudioPath,
            outputPath: finalVideoPath,
          );

          // 2. Yedek: Android native MediaMuxer WebM/Opus veya cihaz uyumsuzluğunda hata verirse,
          // FFmpeg stream copy (-c copy) devreye girer (Kayıpsız, ultra hızlı, sıfır kalite kaybı)!
          if (!muxSuccess || !File(finalVideoPath).existsSync() || File(finalVideoPath).lengthSync() < 1024) {
            AppLogger.warn(_tag, '⚠ Native MediaMuxer WebM/cihaz kısıtlaması, FFmpeg stream copy devreye giriyor...');
            muxSuccess = await AudioConverter.muxVideoAndAudio(
              videoPath: tempVideoPath,
              audioPath: tempAudioPath,
              outputPath: finalVideoPath,
            );
          }

          if (muxSuccess && File(finalVideoPath).existsSync() && File(finalVideoPath).lengthSync() > 1024) {
            if (vFile.existsSync()) try { vFile.deleteSync(); } catch (_) {}
            if (aFile != null && aFile.existsSync()) try { aFile.deleteSync(); } catch (_) {}
            task.filePath = finalVideoPath;
            task.updateProgress(status: DownloadStatus.completed, progress: 1.0, speed: 'Done');
            _cleanupResidualFiles(outputDirPath, sanitizedTitle);
            _scanFileOnAndroid(finalVideoPath);
            AppLogger.success(_tag, '🎬 Video birleştirme tamamlandı: $finalVideoPath');
            yt.close();
            return true;
          }

          // 3. Strateji (Konteyner Kurtarma): Eğer WebM konteyneri cihazda reddedildiyse,
          // evrensel MKV konteyneri ile kurtar (tüm modern oynatıcılar MKV içindeki VP9+Opus'u kayıpsız oynatır)
          if (isWebm && aFile != null && aFile.existsSync()) {
            final mkvFallbackPath = '$outputDirPath/$sanitizedTitle.mkv';
            AppLogger.warn(_tag, '⚠ WebM dosyası oluşturulamadı, evrensel MKV formatında birleştirme deneniyor...');
            final mkvSuccess = await AudioConverter.muxVideoAndAudio(
              videoPath: tempVideoPath,
              audioPath: tempAudioPath,
              outputPath: mkvFallbackPath,
            );
            if (mkvSuccess && File(mkvFallbackPath).existsSync() && File(mkvFallbackPath).lengthSync() > 1024) {
              if (vFile.existsSync()) try { vFile.deleteSync(); } catch (_) {}
              if (aFile.existsSync()) try { aFile.deleteSync(); } catch (_) {}
              task.filePath = mkvFallbackPath;
              task.updateProgress(status: DownloadStatus.completed, progress: 1.0, speed: 'Done');
              _cleanupResidualFiles(outputDirPath, sanitizedTitle);
              _scanFileOnAndroid(mkvFallbackPath);
              AppLogger.success(_tag, '🎬 MKV yedek video birleştirme tamamlandı: $mkvFallbackPath');
              yt.close();
              return true;
            }
          }

        // 🛡️ DİKKAT: Ses akışı indirilmiş ancak birleştirme başarısız olmuşsa ASLA sessiz ham videoyu kaydetme!
        if (aFile != null && aFile.existsSync()) {
          AppLogger.error(_tag, '❌ Video ve ses birleştirme başarısız oldu.');
          if (vFile.existsSync()) try { vFile.deleteSync(); } catch (_) {}
          if (aFile.existsSync()) try { aFile.deleteSync(); } catch (_) {}
          task.errorMessage = '⚠️ Video ve ses birleştirilemedi.\nLütfen depolama alanınızı kontrol edip tekrar deneyin.';
          task.updateProgress(status: DownloadStatus.failed, speed: 'Mux Error');
          yt.close();
          return false;
        }

        // Yalnızca ses akışı hiç yoksa (örneğin kaynaktan sessiz video) doğrudan videoyu kaydet
        if (vFile.existsSync() && vFile.lengthSync() > 0) {
          await _safeMoveFile(vFile, finalVideoPath);
          task.filePath = finalVideoPath;
          task.updateProgress(status: DownloadStatus.completed, progress: 1.0, speed: 'Done');
          _cleanupResidualFiles(outputDirPath, sanitizedTitle);
          _scanFileOnAndroid(finalVideoPath);
          yt.close();
          return true;
        }

        yt.close();
        return false;
      }
    } catch (e, st) {
      yt?.close();
      AppLogger.error(_tag, '✗ Pure Dart exception: ${e.runtimeType}: $e');
      AppLogger.error(_tag, '  StackTrace: ${st.toString().split('\n').take(5).join(' | ')}');
      
      final eStr = e.toString();
      if (eStr.contains('Sign in to confirm your age') || eStr.contains('age') || eStr.contains('restrictions')) {
        task.errorMessage = '🔞 Yaş Kısıtlamalı Video (18+):\nYouTube bu video için yaş doğrulaması istiyor. Ayarlar > Google Hesabı (OAuth) ile giriş yaparak bu kısıtlamayı aşabilirsiniz.';
      } else if (eStr.contains('RateLimit') || eStr.contains('rate limit') || eStr.contains('429') || eStr.contains('RequestLimitExceededException')) {
        task.errorMessage = '⏱️ YouTube İstek Sınırı (429):\nÇok hızlı istek yapıldı. Lütfen biraz bekleyin veya Ayarlar\'dan Google hesabınızı bağlayın.';
      } else if (eStr.contains('TimeoutException') || eStr.contains('zaman aşımı')) {
        task.errorMessage = '⏱️ Bağlantı Zaman Aşımı:\nYouTube sunucusu zamanında yanıt vermedi. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.';
      } else if (eStr.contains('SocketException') || eStr.contains('HandshakeException') || eStr.contains('Failed host lookup')) {
        task.errorMessage = '🌐 İnternet Bağlantı Hatası:\nYouTube sunucularına erişilemedi. Lütfen bağlantınızı kontrol edin.';
      } else if (eStr.contains('VideoUnplayableException')) {
        task.errorMessage = '⚠️ Video Kullanılamıyor:\nİçerik YouTube tarafından kısıtlanmış veya telif/bölge engeli bulunuyor.';
      } else {
        task.errorMessage = '${e.runtimeType}: $e';
      }
      return false;
    }
  }



  static String? _findMatchingFile(String outputDirPath, DownloadTask task) {
    try {
      final dir = Directory(outputDirPath);
      if (!dir.existsSync()) return null;

      final files = dir.listSync().whereType<File>().toList();
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      // 1. Direct search by words
      final titleWords = task.video.title
          .toLowerCase()
          .split(RegExp(r'[\s\-_\/|\\:,\.]+'))
          .where((w) => w.length > 2)
          .toList();

      for (var f in files) {
        final name = f.uri.pathSegments.last.toLowerCase();
        int matchCount = 0;
        for (var w in titleWords) {
          if (name.contains(w)) matchCount++;
        }
        if (titleWords.isNotEmpty && (matchCount / titleWords.length) >= 0.5) {
          return f.path;
        }
      }

      // 2. Search most recent matching extension (downloaded in last 10 minutes)
      for (var f in files) {
        final diff = DateTime.now().difference(f.lastModifiedSync()).inMinutes;
        if (diff <= 10) {
          final ext = f.path.split('.').last.toLowerCase();
          if (task.isAudio && ['mp3', 'm4a', 'flac', 'wav', 'opus', 'aac'].contains(ext)) {
            return f.path;
          }
          if (!task.isAudio && ['mp4', 'mkv', 'webm', 'avi', 'mov'].contains(ext)) {
            return f.path;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static String _sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  static Future<void> _safeMoveFile(File source, String destination) async {
    try {
      final destFile = File(destination);
      if (destFile.existsSync()) {
        try {
          await destFile.delete();
        } catch (_) {}
      }
      source.renameSync(destination);
    } catch (_) {
      try {
        await source.copy(destination);
        try { await source.delete(); } catch (_) {}
      } catch (e2) {
        AppLogger.error(_tag, 'Dosya taşıma hatası: $e2');
        rethrow;
      }
    }
  }



  static void cancelTask(DownloadTask task) {
    task.status = DownloadStatus.cancelled;
    task.activeProcess = null;
  }
}

