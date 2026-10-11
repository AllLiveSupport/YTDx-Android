import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'app_logger.dart';

class AudioConverter {
  static const String _tag = 'AudioConverter';

  /// Converts or remuxes [inputPath] to [outputPath] based on [targetFormat] and [quality].
  /// Supports:
  /// - MP3: 320k, 192k, 128k via libmp3lame
  /// - M4A: 256k, 128k via AAC stream copy or AAC encoding
  /// - Opus: 160k, 70k via Opus stream copy or libopus encoding
  static Future<bool> convertAudio({
    required String inputPath,
    required String outputPath,
    required String targetFormat,
    required String quality,
    bool isSourceWebm = false,
  }) async {
    final inputFile = File(inputPath);
    if (!inputFile.existsSync() || inputFile.lengthSync() == 0) {
      AppLogger.error(_tag, 'Girdi dosyası mevcut değil veya boş: $inputPath');
      return false;
    }

    final format = targetFormat.toLowerCase().trim();
    final q = quality.toLowerCase().trim();

    // Safe CPU Concurrency: Limit FFmpeg threads so it NEVER starves the Flutter UI & Android OS.
    // Leaves at least 1-2 CPU cores 100% free for 90 FPS Flutter rendering.
    final safeThreads = (Platform.numberOfProcessors > 2) ? 2 : 1;

    AppLogger.info(
      _tag,
      '🔄 Ses Dönüştürme Başlatılıyor: $format ($q, kaynakWebm=$isSourceWebm, threads=$safeThreads) -> $outputPath',
    );

    // Ensure parent directory of outputPath exists
    final outParent = File(outputPath).parent;
    if (!outParent.existsSync()) {
      try {
        outParent.createSync(recursive: true);
      } catch (e) {
        AppLogger.error(_tag, 'Hedef klasör oluşturulamadı: $e');
        return false;
      }
    }

    // If destination already exists, remove it before FFmpeg writes to it
    final destFile = File(outputPath);
    if (destFile.existsSync()) {
      try {
        destFile.deleteSync();
      } catch (_) {}
    }

    List<String> args;

    if (format == 'mp3') {
      int bitrate = 320;
      if (q.contains('192')) {
        bitrate = 192;
      } else if (q.contains('128')) {
        bitrate = 128;
      }
      args = [
        '-y',
        '-threads', '$safeThreads',
        '-i', inputPath,
        '-vn',
        '-c:a', 'libmp3lame',
        '-b:a', '${bitrate}k',
        '-ar', '44100',
        outputPath,
      ];
    } else if (format == 'opus') {
      int bitrate = q.contains('70') ? 70 : 160;
      if (isSourceWebm) {
        // Kaynak zaten WebM/Opus olduğunda akış kopyalama (stream copy) en hızlı ve kayıpsızdır (< 0.1s)
        args = [
          '-y',
          '-i', inputPath,
          '-vn',
          '-c:a', 'copy',
          outputPath,
        ];
      } else {
        // Kaynak MP4/Muxed (AAC) olduğunda -c:a copy başarısız olur; doğrudan libopus ile kodla
        args = [
          '-y',
          '-threads', '$safeThreads',
          '-i', inputPath,
          '-vn',
          '-c:a', 'libopus',
          '-b:a', '${bitrate}k',
          outputPath,
        ];
      }
    } else {
      // M4A / AAC
      if (!isSourceWebm) {
        // Kaynak zaten MP4/AAC olduğunda kayıpsız stream copy (< 0.1s)
        args = [
          '-y',
          '-i', inputPath,
          '-vn',
          '-c:a', 'copy',
          outputPath,
        ];
      } else {
        // Kaynak WebM/Opus ise AAC olarak kodla
        int bitrate = q.contains('128') ? 128 : 256;
        args = [
          '-y',
          '-threads', '$safeThreads',
          '-i', inputPath,
          '-vn',
          '-c:a', 'aac',
          '-b:a', '${bitrate}k',
          outputPath,
        ];
      }
    }

    AppLogger.info(_tag, 'FFmpeg Argümanları: ${args.join(' ')}');

    try {
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode) &&
          destFile.existsSync() &&
          destFile.lengthSync() > 1024) {
        AppLogger.success(
          _tag,
          '✅ Dönüştürme başarılı: $outputPath (${(destFile.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB)',
        );
        return true;
      }

      // If stream copy failed for Opus or M4A (e.g., codec mismatch with container), fall back to re-encoding
      if (format == 'opus') {
        int bitrate = q.contains('70') ? 70 : 160;
        AppLogger.warn(_tag, 'Stream copy başarısız, libopus ile yeniden kodlanıyor...');
        final fallbackArgs = [
          '-y',
          '-threads', '$safeThreads',
          '-i', inputPath,
          '-vn',
          '-c:a', 'libopus',
          '-b:a', '${bitrate}k',
          outputPath,
        ];
        final fallbackSession = await FFmpegKit.executeWithArguments(fallbackArgs);
        final fbCode = await fallbackSession.getReturnCode();
        if (ReturnCode.isSuccess(fbCode) && destFile.existsSync() && destFile.lengthSync() > 1024) {
          AppLogger.success(_tag, '✅ Opus fallback kodlama başarılı: $outputPath');
          return true;
        }

        // Second fallback: native FFmpeg opus encoder with -strict -2
        AppLogger.warn(_tag, 'libopus başarısız, native opus (-strict -2) deneniyor...');
        final nativeOpusArgs = [
          '-y',
          '-threads', '$safeThreads',
          '-i', inputPath,
          '-vn',
          '-c:a', 'opus',
          '-strict', '-2',
          '-b:a', '${bitrate}k',
          outputPath,
        ];
        final nativeSession = await FFmpegKit.executeWithArguments(nativeOpusArgs);
        final natCode = await nativeSession.getReturnCode();
        if (ReturnCode.isSuccess(natCode) && destFile.existsSync() && destFile.lengthSync() > 1024) {
          AppLogger.success(_tag, '✅ Native Opus kodlama başarılı: $outputPath');
          return true;
        }
      } else if (format == 'm4a') {
        int bitrate = q.contains('128') ? 128 : 256;
        AppLogger.warn(_tag, 'Stream copy başarısız, aac ile yeniden kodlanıyor...');
        final fallbackArgs = [
          '-y',
          '-threads', '$safeThreads',
          '-i', inputPath,
          '-vn',
          '-c:a', 'aac',
          '-b:a', '${bitrate}k',
          outputPath,
        ];
        final fallbackSession = await FFmpegKit.executeWithArguments(fallbackArgs);
        final fbCode = await fallbackSession.getReturnCode();
        if (ReturnCode.isSuccess(fbCode) && destFile.existsSync() && destFile.lengthSync() > 1024) {
          AppLogger.success(_tag, '✅ AAC fallback kodlama başarılı: $outputPath');
          return true;
        }
      }

      final output = await session.getOutput();
      AppLogger.error(_tag, '❌ FFmpeg başarısız oldu (kod: ${returnCode?.getValue()}). Çıktı:\n$output');
      return false;
    } catch (e) {
      AppLogger.error(_tag, '❌ AudioConverter istisnası: $e');
      return false;
    }
  }

  /// Merges video and audio files using FFmpeg stream copy (-c copy) or adaptive fallback.
  /// Works for both MP4 (H.264/AAC) and WebM (VP9/Opus) with zero video quality loss.
  static Future<bool> muxVideoAndAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    final vFile = File(videoPath);
    final aFile = File(audioPath);
    if (!vFile.existsSync() || !aFile.existsSync()) {
      AppLogger.error(_tag, 'muxVideoAndAudio: Girdi dosyaları eksik.');
      return false;
    }

    final destFile = File(outputPath);
    if (destFile.existsSync()) {
      try { destFile.deleteSync(); } catch (_) {}
    }

    final safeThreads = (Platform.numberOfProcessors > 2) ? 2 : 1;
    final isWebm = outputPath.toLowerCase().endsWith('.webm') || outputPath.toLowerCase().endsWith('.mkv');

    // 1. Strateji: Kayıpsız ve anında doğrudan Stream Copy (-map 0:v:0 -map 1:a:0 -c copy)
    final copyArgs = [
      '-y',
      '-threads', '$safeThreads',
      '-i', videoPath,
      '-i', audioPath,
      '-map', '0:v:0',
      '-map', '1:a:0',
      '-c:v', 'copy',
      '-c:a', 'copy',
      outputPath,
    ];

    AppLogger.info(_tag, '🎬 FFmpeg Video+Audio Mux başlatılıyor (Strateji 1 - Copy): ${copyArgs.join(' ')}');
    try {
      final session = await FFmpegKit.executeWithArguments(copyArgs);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode) &&
          destFile.existsSync() &&
          destFile.lengthSync() > 1024) {
        AppLogger.success(_tag, '✅ FFmpeg stream copy başarılı: $outputPath (${(destFile.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB)');
        return true;
      }
      final output = await session.getOutput();
      AppLogger.warn(_tag, '⚠ FFmpeg stream copy çıkış kodu: ${returnCode?.getValue()}, çıktı: $output');
    } catch (e) {
      AppLogger.warn(_tag, '⚠ FFmpeg stream copy hatası: $e');
    }

    // 2. Strateji (Yedek): Konteyner veya codec uyumsuzluğunda akıllı ses transcode ile kurtarma
    AppLogger.warn(_tag, '⚠ FFmpeg stream copy başarısız oldu, codec uyumlu ses kodlama devreye giriyor...');
    if (destFile.existsSync()) {
      try { destFile.deleteSync(); } catch (_) {}
    }

    final fallbackArgs = isWebm
        ? [
            '-y',
            '-threads', '$safeThreads',
            '-i', videoPath,
            '-i', audioPath,
            '-map', '0:v:0',
            '-map', '1:a:0',
            '-c:v', 'copy',
            '-c:a', 'libopus',
            '-b:a', '160k',
            outputPath,
          ]
        : [
            '-y',
            '-threads', '$safeThreads',
            '-i', videoPath,
            '-i', audioPath,
            '-map', '0:v:0',
            '-map', '1:a:0',
            '-c:v', 'copy',
            '-c:a', 'aac',
            '-b:a', '192k',
            outputPath,
          ];

    AppLogger.info(_tag, '🎬 FFmpeg Video+Audio Mux başlatılıyor (Strateji 2 - Fallback): ${fallbackArgs.join(' ')}');
    try {
      final session = await FFmpegKit.executeWithArguments(fallbackArgs);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode) &&
          destFile.existsSync() &&
          destFile.lengthSync() > 1024) {
        AppLogger.success(_tag, '✅ FFmpeg yedek mux başarılı: $outputPath (${(destFile.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB)');
        return true;
      }
      final output = await session.getOutput();
      AppLogger.error(_tag, '❌ FFmpeg yedek mux başarısız: ${returnCode?.getValue()}, çıktı: $output');
      return false;
    } catch (e) {
      AppLogger.error(_tag, '❌ FFmpeg mux hatası: $e');
      return false;
    }
  }
}
