import 'dart:async';
import 'package:flutter/services.dart';
import 'app_logger.dart';

typedef ShareUrlCallback = void Function(String url);

class ShareIntentService {
  static const String _tag = 'ShareIntentService';
  static const MethodChannel _channel = MethodChannel('com.alllivesupport.ytdxstudio/share');

  static ShareUrlCallback? onUrlReceived;
  static bool _isListening = false;

  static void init({required ShareUrlCallback callback}) {
    onUrlReceived = callback;

    if (!_isListening) {
      _isListening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onSharedText') {
          final text = call.arguments as String?;
          _handleSharedText(text);
        }
      });
    }

    _checkInitialShare();
  }

  static Future<void> _checkInitialShare() async {
    try {
      final initialText = await _channel.invokeMethod<String>('getInitialSharedText');
      if (initialText != null && initialText.isNotEmpty) {
        _handleSharedText(initialText);
      }
    } catch (e) {
      AppLogger.warn(_tag, 'İlk paylaşılan metin okunamadı: $e');
    }
  }

  static void _handleSharedText(String? rawText) {
    if (rawText == null || rawText.trim().isEmpty) return;

    // Extract first URL found in text
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
    final match = urlRegex.firstMatch(rawText);
    final url = match != null ? match.group(0) : rawText.trim();

    if (url != null && url.isNotEmpty) {
      AppLogger.info(_tag, '📲 Paylaşım menüsünden bağlantı alındı: $url');
      onUrlReceived?.call(url);
    }
  }
}
