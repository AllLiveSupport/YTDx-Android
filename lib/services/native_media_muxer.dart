import 'dart:io';
import 'package:flutter/services.dart';
import 'app_logger.dart';

class NativeMediaMuxer {
  static const _tag = 'NativeMediaMuxer';
  static const _channel = MethodChannel('com.alllivesupport.ytdxstudio/muxer');

  /// Combines video file (.mp4) and audio file (.m4a) into a single standard MP4 file on Android
  static Future<bool> muxVideoAndAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    if (!Platform.isAndroid) return false;

    try {
      AppLogger.info(_tag, '🎬 Native MediaMuxer başlatılıyor: $videoPath + $audioPath -> $outputPath');
      final result = await _channel.invokeMethod<bool>('muxVideoAndAudio', {
        'videoPath': videoPath,
        'audioPath': audioPath,
        'outputPath': outputPath,
      });
      if (result == true && File(outputPath).existsSync() && File(outputPath).lengthSync() > 0) {
        AppLogger.success(_tag, '✅ Native MediaMuxer başarılı! (${(File(outputPath).lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB)');
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.error(_tag, '❌ Native MediaMuxer hatası: $e');
      return false;
    }
  }

  /// Notifies Android MediaStore about newly downloaded media so it immediately shows up in gallery/music players
  static Future<void> scanFile(String filePath) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('scanFile', {'path': filePath});
    } catch (_) {}
  }
}
