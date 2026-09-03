import 'dart:async';
import 'dart:io';
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

  static Future<void> executeDownload({
    required DownloadTask task,
    required AppSettings settings,
    required Function() onUpdate,
  }) async {
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
                name.endsWith('.tmp')) {
              try { entity.deleteSync(); } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }

  static Future<StreamInfo?> _downloadDirectStream({
    required YoutubeExplode yt,
    required List<StreamInfo> streamCandidates,
    required File targetFile,
    required DownloadTask task,
    required Function() onUpdate,
    double progressStart = 0.0,
    double progressWeight = 1.0,
  }) async {
    int consecutiveAdaptiveFailures = 0;

    for (int i = 0; i < streamCandidates.length; i++) {
      final streamInfo = streamCandidates[i];
      if (task.status == DownloadStatus.cancelled) break;

      final isMuxed = streamInfo is MuxedStreamInfo || streamInfo.tag == 18 || streamInfo.tag == 22;

      // ⚡ FAST-JUMP TO MUXED:
      // Eğer ilk 2 tekil adaptif akış (audioOnly veya videoOnly) 403 veya timeout verirse,
      // YouTube bu IP'de DASH akışlarını kısıtlamıştır. Geri kalan adayları 4'er sn bekletmeden
      // doğrudan güvenli Muxed akışına (itag 18 / 22) zıpla! (10-12s bekleme 1-2s'ye düşer)
      if (!isMuxed && consecutiveAdaptiveFailures >= 2) {
        final muxedIndex = streamCandidates.indexWhere(
          (s) => s is MuxedStreamInfo || s.tag == 18 || s.tag == 22,
        );
        if (muxedIndex > i) {
          AppLogger.warn(_tag, '⚡ DASH akışları kısıtlandı ($consecutiveAdaptiveFailures ardışık hata), doğrudan Muxed akışına (itag=${streamCandidates[muxedIndex].tag}) atlanıyor!');
          i = muxedIndex - 1; // döngü bir sonraki adımda muxedIndex'e geçer
          consecutiveAdaptiveFailures = 0;
          continue;
        }
      }

      final expectedBytes = streamInfo.size.totalBytes;
      AppLogger.info(_tag, '🚀 Stream deneniyor: itag=${streamInfo.tag}, ${streamInfo.size.totalMegaBytes.toStringAsFixed(1)} MB (${streamInfo.container.name})');

      // ⚡ Hızlı Ön Denetim (~25ms): YouTube bu akış için 403 Forbidden veya kısıtlama koydu mu?
      try {
        final client = http.Client();
        final preReq = http.Request('GET', streamInfo.url);
        preReq.headers['Range'] = 'bytes=0-524288';
        final preRes = await client
            .send(preReq)
            .timeout(const Duration(milliseconds: 700));
        unawaited(preRes.stream.drain().catchError((_) => null));
        client.close();

        if (preRes.statusCode != 206 && preRes.statusCode != 200) {
          AppLogger.warn(_tag,
              '⛔ itag=${streamInfo.tag} YouTube tarafından engellendi (${preRes.statusCode}), sonraki alternatife geçiliyor (~25ms)');
          if (!isMuxed) consecutiveAdaptiveFailures++;
          continue;
        }
      } catch (_) {
        // Ön denetim ağ zaman aşımı verirse normal akışla devam et
      }

      if (targetFile.existsSync()) {
        try { targetFile.deleteSync(); } catch (_) {}
      }

      IOSink? sink;
      StreamSubscription<List<int>>? rawSub;
      final stopwatch = Stopwatch()..start();
      int downloaded = 0;
      int bytesSinceLastTick = 0;
      int lastTickMs = 0;

      // Mobil ağ şartlarına uyarlanmış güvenli watchdog: İlk bağlantı 6 sn, hareketsizlik 18 sn limit
      const initialConnectLimit = Duration(seconds: 6);
      const activeInactivityLimit = Duration(seconds: 18);
      Timer? watchdog;
      bool timedOut = false;
      final proxyCtrl = StreamController<List<int>>();

      try {
        sink = targetFile.openWrite(mode: FileMode.writeOnly);

        // Doğrudan YoutubeExplode üzerinden tek parça akış al
        final rawStream = yt.videos.streamsClient.get(streamInfo);

        watchdog = Timer(initialConnectLimit, () {
          if (!proxyCtrl.isClosed) {
            timedOut = true;
            proxyCtrl.addError(TimeoutException(
                'Akış başlangıç zaman aşımı (${initialConnectLimit.inSeconds}s, itag=${streamInfo.tag})'));
            proxyCtrl.close();
            try { rawSub?.cancel(); } catch (_) {}
          }
        });

        rawSub = rawStream.listen(
          (chunk) {
            watchdog?.cancel();
            watchdog = Timer(activeInactivityLimit, () {
              if (!proxyCtrl.isClosed) {
                timedOut = true;
                proxyCtrl.addError(TimeoutException(
                    '${activeInactivityLimit.inSeconds}s hareketsizlik (itag=${streamInfo.tag})'));
                proxyCtrl.close();
                try { rawSub?.cancel(); } catch (_) {}
              }
            });
            if (!proxyCtrl.isClosed) proxyCtrl.add(chunk);
          },
          onError: (e) {
            if (!proxyCtrl.isClosed) {
              proxyCtrl.addError(e);
              proxyCtrl.close();
              try { rawSub?.cancel(); } catch (_) {}
            }
          },
          onDone: () {
            watchdog?.cancel();
            if (!proxyCtrl.isClosed) proxyCtrl.close();
          },
          cancelOnError: true,
        );

        await for (final chunk in proxyCtrl.stream) {
          if (task.status == DownloadStatus.cancelled) break;

          sink.add(chunk);
          downloaded += chunk.length;
          bytesSinceLastTick += chunk.length;

          final elapsedMs = stopwatch.elapsedMilliseconds;
          if (elapsedMs - lastTickMs >= 450 || (expectedBytes > 0 && downloaded >= expectedBytes)) {
            final deltaSec = (elapsedMs - lastTickMs) / 1000.0;
            if (deltaSec > 0) {
              final currentSpeedMbps = (bytesSinceLastTick / (1024 * 1024)) / deltaSec;
              task.speed = '${currentSpeedMbps.toStringAsFixed(1)} MB/s';
              bytesSinceLastTick = 0;
              lastTickMs = elapsedMs;

              if (expectedBytes > 0) {
                final remBytes = expectedBytes - downloaded;
                final remSec = currentSpeedMbps > 0
                    ? (remBytes / (1024 * 1024)) / currentSpeedMbps
                    : 0.0;
                task.eta = remSec > 60
                    ? '${(remSec / 60).toInt()}m ${(remSec % 60).toInt()}s'
                    : '${remSec.toInt()}s';
              }
            }

            // Always use actual downloaded bytes for progress — not manifest expectedBytes
            // because DASH manifests may report compressed size (webm container metadata)
            final displayTotal = expectedBytes > 0 ? expectedBytes : downloaded + 1;
            final subFraction = (downloaded / displayTotal).clamp(0.0, 1.0);
            task.progress = (progressStart + subFraction * progressWeight).clamp(0.0, 1.0);
            task.sizeInfo = expectedBytes > 0
                ? '${(downloaded / (1024 * 1024)).toStringAsFixed(1)} MB / ${(expectedBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                : '${(downloaded / (1024 * 1024)).toStringAsFixed(1)} MB indirildi';
            onUpdate();

            // Yield to event loop so UI thread and audio playback get CPU time
            await Future.delayed(Duration.zero);
          }
        }

        watchdog?.cancel();
        try { await rawSub.cancel(); } catch (_) {}
        rawSub = null;
        await sink.flush();
        await sink.close();
        sink = null;
        stopwatch.stop();

        // Validate: file must exist and have meaningful data
        final diskSize = targetFile.existsSync() ? targetFile.lengthSync() : 0;
        if (diskSize > 0 && task.status != DownloadStatus.cancelled) {
          task.progress = (progressStart + progressWeight).clamp(0.0, 1.0);
          task.sizeInfo = '${(diskSize / (1024 * 1024)).toStringAsFixed(1)} MB / ${(diskSize / (1024 * 1024)).toStringAsFixed(1)} MB';
          onUpdate();
          AppLogger.success(_tag, '✅ itag=${streamInfo.tag} tamamlandı: ${(diskSize / (1024 * 1024)).toStringAsFixed(1)} MB disk');
          return streamInfo;
        } else if (timedOut) {
          if (!isMuxed) consecutiveAdaptiveFailures++;
          AppLogger.warn(_tag, '⏰ itag=${streamInfo.tag} zaman aşımına uğradı, sıradakine geçiliyor');
        } else {
          if (!isMuxed) consecutiveAdaptiveFailures++;
          AppLogger.warn(_tag, '⚠ itag=${streamInfo.tag} indirme doğrulama başarısız ($diskSize bytes), sıradakine geçiliyor');
        }
      } catch (e) {
        if (!isMuxed) consecutiveAdaptiveFailures++;
        watchdog?.cancel();
        try { await rawSub?.cancel(); } catch (_) {}
        rawSub = null;
        AppLogger.warn(_tag, '⚠ Stream hatası (itag=${streamInfo.tag}): $e');
        if (sink != null) {
          try { await sink.close(); } catch (_) {}
          sink = null;
        }
        if (targetFile.existsSync() && targetFile.lengthSync() == 0) {
          try { targetFile.deleteSync(); } catch (_) {}
        }
      } finally {
        watchdog?.cancel();
        try { await rawSub?.cancel(); } catch (_) {}
        rawSub = null;
        if (!proxyCtrl.isClosed) {
          try { proxyCtrl.close(); } catch (_) {}
        }
        if (sink != null) {
          try { await sink.close(); } catch (_) {}
          sink = null;
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
        AppLogger.warn(_tag, 'Client manifest hatası: $e, temiz bağımsız istemci deneniyor...');
        final cleanYt = YoutubeExplode();
        try {
          manifest = await cleanYt.videos.streamsClient.getManifest(videoId);
          yt.close();
          yt = cleanYt; // Temiz istemci oturumu devralsın
        } catch (e2) {
          cleanYt.close();
          rethrow;
        }
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
              artFile.writeAsBytesSync(res.bodyBytes);
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
        // Eğer kullanıcı 720p, 360p veya Otomatik seçtiyse ve YouTube'da hazır tek parça (video + ses)
        // muxed akış bulunuyorsa (itag 22 720p veya itag 18 360p), ayrı ses indirip birleştirme
        // yapmadan TEK PARÇA olarak 2 saniyede doğrudan indirilir!
        MuxedStreamInfo? singlePartMuxed;
        if (!isWebmRequested) {
          if (q.contains('720')) {
            singlePartMuxed = manifest.muxed.where((s) => s.qualityLabel.contains('720')).firstOrNull;
          } else if (q.contains('360')) {
            singlePartMuxed = manifest.muxed.where((s) => s.qualityLabel.contains('360')).firstOrNull;
          } else if (q == 'auto' || q.isEmpty) {
            singlePartMuxed = manifest.muxed.isNotEmpty ? manifest.muxed.withHighestBitrate() : null;
          }
        }

        if (singlePartMuxed != null) {
          AppLogger.info(_tag, '⚡ Hazır tek parça video bulundu: itag=${singlePartMuxed.tag} (${singlePartMuxed.qualityLabel}), doğrudan tek parça indiriliyor...');
          final finalVideoPath = '$outputDirPath/$sanitizedTitle.mp4';
          final tempDir = await getTemporaryDirectory();
          final tempPath = '${tempDir.path}/${sanitizedTitle}_${DateTime.now().millisecondsSinceEpoch}.tmp';
          final tFile = File(tempPath);
          final downloadedMuxed = await _downloadDirectStream(
            yt: yt,
            streamCandidates: [singlePartMuxed],
            targetFile: tFile,
            task: task,
            onUpdate: onUpdate,
          );
          if (downloadedMuxed != null && tFile.existsSync() && tFile.lengthSync() > 1024) {
            _safeMoveFile(tFile, finalVideoPath);
            task.filePath = finalVideoPath;
            task.status = DownloadStatus.completed;
            task.progress = 1.0;
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
        if (isWebmRequested) {
          // WebM / VP9 öncelikli sıralama
          allVideos.sort((a, b) {
            if (a.container.name == 'webm' && b.container.name != 'webm') return -1;
            if (a.container.name != 'webm' && b.container.name == 'webm') return 1;
            return b.bitrate.compareTo(a.bitrate);
          });
        } else {
          // MP4 / AVC öncelikli sıralama
          allVideos.sort((a, b) {
            if (a.container.name == 'mp4' && b.container.name != 'mp4') return -1;
            if (a.container.name != 'mp4' && b.container.name == 'mp4') return 1;
            return b.bitrate.compareTo(a.bitrate);
          });
        }

        if (q == 'auto' || q.isEmpty) {
          // AUTO: En yüksek çözünürlük ve bitrate akışları en başta
          videoCandidates.addAll(allVideos);
        } else {
          int parseTargetHeight(String query) {
            if (query.contains('4320') || query.contains('8k')) return 4320;
            if (query.contains('2160') || query.contains('4k')) return 2160;
            if (query.contains('1440') || query.contains('2k')) return 1440;
            if (query.contains('1080')) return 1080;
            if (query.contains('720')) return 720;
            if (query.contains('480')) return 480;
            if (query.contains('360')) return 360;
            if (query.contains('240')) return 240;
            if (query.contains('144')) return 144;
            return -1;
          }

          int getStreamHeight(VideoStreamInfo s) {
            final match = RegExp(r'(\d+)p').firstMatch(s.qualityLabel);
            if (match != null) {
              return int.tryParse(match.group(1)!) ?? 0;
            }
            return 0;
          }

          final targetHeight = parseTargetHeight(q);
          if (targetHeight > 0) {
            // 1. Tam eşleşen çözünürlük (Örn: 480p)
            final exact = allVideos
                .where((s) => getStreamHeight(s) == targetHeight)
                .toList()
              ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
            videoCandidates.addAll(exact);

            // 2. En yakın ALT çözünürlük (Örn: 480p videoda yoksa 360p, 240p)
            // Bu kullanıcının kotasını korur ve 480p isteyen kullanıcıya zorla 4K/1080p indirmez!
            final lower = allVideos
                .where((s) => getStreamHeight(s) > 0 && getStreamHeight(s) < targetHeight)
                .toList()
              ..sort((a, b) {
                final diffA = (targetHeight - getStreamHeight(a)).abs();
                final diffB = (targetHeight - getStreamHeight(b)).abs();
                if (diffA != diffB) return diffA.compareTo(diffB);
                return b.bitrate.compareTo(a.bitrate);
              });
            videoCandidates.addAll(lower);

            // 3. Alt çözünürlük yoksa en yakın ÜST (Örn: 720p - 4K değil!)
            final higher = allVideos
                .where((s) => getStreamHeight(s) > targetHeight)
                .toList()
              ..sort((a, b) {
                final diffA = (getStreamHeight(a) - targetHeight).abs();
                final diffB = (getStreamHeight(b) - targetHeight).abs();
                if (diffA != diffB) return diffA.compareTo(diffB);
                return b.bitrate.compareTo(a.bitrate);
              });
            videoCandidates.addAll(higher);
          } else {
            videoCandidates.addAll(allVideos);
          }
        }

        if (videoCandidates.isEmpty && manifest.muxed.isNotEmpty) {
          final muxedStream = manifest.muxed.withHighestBitrate();
          final finalVideoPath = '$outputDirPath/$sanitizedTitle.mp4';
          final tempDir = await getTemporaryDirectory();
          final tempPath = '${tempDir.path}/${sanitizedTitle}_${DateTime.now().millisecondsSinceEpoch}.tmp';
          final tFile = File(tempPath);
          final downloadedMuxed = await _downloadDirectStream(
            yt: yt,
            streamCandidates: [muxedStream],
            targetFile: tFile,
            task: task,
            onUpdate: onUpdate,
          );
          if (downloadedMuxed != null && tFile.existsSync()) {
            _safeMoveFile(tFile, finalVideoPath);
            task.filePath = finalVideoPath;
            task.status = DownloadStatus.completed;
            task.progress = 1.0;
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
        final tempVideoPath = '${tempDir.path}/${sanitizedTitle}_vtmp.${chosenVideo.container.name}';
        final tempAudioPath = audioStreamInfo != null
            ? '${tempDir.path}/${sanitizedTitle}_atmp.${audioStreamInfo.container.name}'
            : '';

        final vFile = File(tempVideoPath);
        final aFile = audioStreamInfo != null ? File(tempAudioPath) : null;

        // A. Video Akışını İndir (%0 -> %90)
        task.speed = 'Video akışı indiriliyor (${chosenVideo.qualityLabel})...';
        onUpdate();
        final downloadedVideoStream = await _downloadDirectStream(
          yt: yt,
          streamCandidates: videoCandidates,
          targetFile: vFile,
          task: task,
          onUpdate: onUpdate,
          progressStart: 0.0,
          progressWeight: 0.90,
        );

        if (downloadedVideoStream == null || task.status == DownloadStatus.cancelled) {
          if (vFile.existsSync()) try { vFile.deleteSync(); } catch (_) {}

          // 🛡️ Adaptif video akışları engellendiyse (örneğin YouTube rate-limiting),
          // hazır tek parça Muxed akışına (720p/360p) düşerek indirmeyi başarıyla kurtar!
          if (manifest.muxed.isNotEmpty && task.status != DownloadStatus.cancelled) {
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
              _safeMoveFile(vFile, fallbackVideoPath);
              task.filePath = fallbackVideoPath;
              task.status = DownloadStatus.completed;
              task.progress = 1.0;
              _cleanupResidualFiles(outputDirPath, sanitizedTitle);
              _scanFileOnAndroid(fallbackVideoPath);
              yt.close();
              return true;
            }
          }

          yt.close();
          return false;
        }

        // B. Ses Akışını İndir (%90 -> %98)
        if (aFile != null && audioCandidates.isNotEmpty) {
          task.speed = 'Ses akışı indiriliyor (HQ)...';
          onUpdate();
          final downloadedAudioStream = await _downloadDirectStream(
            yt: yt,
            streamCandidates: audioCandidates,
            targetFile: aFile,
            task: task,
            onUpdate: onUpdate,
            progressStart: 0.90,
            progressWeight: 0.08,
          );

          if (downloadedAudioStream == null || task.status == DownloadStatus.cancelled) {
            if (vFile.existsSync()) try { vFile.deleteSync(); } catch (_) {}
            if (aFile.existsSync()) try { aFile.deleteSync(); } catch (_) {}
            yt.close();
            return false;
          }

          // C. MUX Video + Audio
          task.status = DownloadStatus.converting;
          task.progress = 0.98;
          task.speed = 'Ses & Video Birleştiriliyor (${chosenVideo.qualityLabel})...';
          onUpdate();

          // Android Donanım MediaMuxer (Arka plan thread'inde çalışır, UI donmaz)
          final muxSuccess = await NativeMediaMuxer.muxVideoAndAudio(
            videoPath: tempVideoPath,
            audioPath: tempAudioPath,
            outputPath: finalVideoPath,
          );

          if (muxSuccess && File(finalVideoPath).existsSync()) {
            if (vFile.existsSync()) try { vFile.deleteSync(); } catch (_) {}
            if (aFile.existsSync()) try { aFile.deleteSync(); } catch (_) {}
            task.filePath = finalVideoPath;
            task.status = DownloadStatus.completed;
            task.progress = 1.0;
            task.speed = 'Done';
            _cleanupResidualFiles(outputDirPath, sanitizedTitle);
            _scanFileOnAndroid(finalVideoPath);
            AppLogger.success(_tag, '🎬 Video birleştirme tamamlandı: $finalVideoPath');
            yt.close();
            return true;
          }
        }

        // Eğer muxing gereksizse veya doğrudan oynatılabilirse
        if (vFile.existsSync() && vFile.lengthSync() > 0) {
          _safeMoveFile(vFile, finalVideoPath);
          task.filePath = finalVideoPath;
          task.status = DownloadStatus.completed;
          task.progress = 1.0;
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

  static void _safeMoveFile(File source, String destination) {
    try {
      final destFile = File(destination);
      if (destFile.existsSync()) {
        try {
          destFile.deleteSync();
        } catch (_) {}
      }
      source.renameSync(destination);
    } catch (_) {
      try {
        source.copySync(destination);
        try { source.deleteSync(); } catch (_) {}
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

