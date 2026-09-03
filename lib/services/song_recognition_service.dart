import 'dart:async';
import 'dart:developer' as developer;
import 'package:permission_handler/permission_handler.dart';
import 'package:shazam_identifier/shazam_identifier.dart';

/// Service responsible for identifying ambient music using the open-source
/// Shazam STFT peak-matching algorithm (zero API keys needed).
class SongRecognitionService {
  static final SongRecognitionService _instance = SongRecognitionService._internal();
  static SongRecognitionService get instance => _instance;

  final MusicRecognitionService _recognitionService = MusicRecognitionService();

  SongRecognitionService._internal();

  Stream<RecognitionStatus> get statusStream => _recognitionService.recognitionStatus;
  RecognitionStatus get currentStatus => _recognitionService.currentStatus;

  /// Check and request microphone permission
  Future<bool> ensurePermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;

    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  /// Start 6-second ambient music listening & recognition flow
  Future<RecognitionStatus> recognize() async {
    final hasPerm = await ensurePermission();
    if (!hasPerm) {
      return RecognitionStatus.error("Mikrofon izni verilmedi.");
    }

    try {
      developer.log("Starting song recognition session...", name: "SongRecognitionService");
      return await _recognitionService.recognize();
    } catch (e) {
      developer.log("Recognition error: $e", name: "SongRecognitionService");
      return RecognitionStatus.error(e.toString());
    }
  }

  /// Reset recognition status back to ready
  void reset() {
    _recognitionService.reset();
  }

  /// Dispose resources
  void dispose() {
    _recognitionService.dispose();
  }
}
