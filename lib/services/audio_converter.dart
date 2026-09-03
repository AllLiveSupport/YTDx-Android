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

    AppLogger.info(
      _tag,
      '🔄 Ses Dönüştürme Başlatılıyor: $format ($q, kaynakWebm=$isSourceWebm) -> $outputPath',
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
        // Kaynak zaten WebM/Opus olduğunda akış kopyalama (stream copy) en hızlı ve kayıpsızdır
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
        // Kaynak zaten MP4/AAC olduğunda kayıpsız stream copy
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
}
