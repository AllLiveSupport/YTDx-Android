// ignore_for_file: prefer_initializing_formals
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'video_item.dart';

enum DownloadStatus {
  queued,
  downloading,
  converting,
  completed,
  paused,
  failed,
  cancelled,
}

class DownloadProgressData {
  final double progress;
  final String speed;
  final String eta;
  final String sizeInfo;
  final DownloadStatus status;
  final String? errorMessage;

  const DownloadProgressData({
    required this.progress,
    required this.speed,
    required this.eta,
    required this.sizeInfo,
    required this.status,
    this.errorMessage,
  });

  DownloadProgressData copyWith({
    double? progress,
    String? speed,
    String? eta,
    String? sizeInfo,
    DownloadStatus? status,
    String? errorMessage,
  }) {
    return DownloadProgressData(
      progress: progress ?? this.progress,
      speed: speed ?? this.speed,
      eta: eta ?? this.eta,
      sizeInfo: sizeInfo ?? this.sizeInfo,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class DownloadTask {
  final String id;
  final VideoItem video;
  final bool isAudio;
  final String format; // mp3, m4a, flac, mp4
  final String quality; // 320k, 256k, 1080p, 4k, auto
  final String outputPath;
  
  DownloadStatus _status;
  DownloadStatus get status => _status;
  set status(DownloadStatus val) {
    _status = val;
    progressNotifier.value = progressNotifier.value.copyWith(status: val);
  }

  double _progress;
  double get progress => _progress;
  set progress(double val) {
    _progress = val;
    progressNotifier.value = progressNotifier.value.copyWith(progress: val);
  }

  String _speed;
  String get speed => _speed;
  set speed(String val) {
    _speed = val;
    progressNotifier.value = progressNotifier.value.copyWith(speed: val);
  }

  String _eta;
  String get eta => _eta;
  set eta(String val) {
    _eta = val;
    progressNotifier.value = progressNotifier.value.copyWith(eta: val);
  }

  String _sizeInfo;
  String get sizeInfo => _sizeInfo;
  set sizeInfo(String val) {
    _sizeInfo = val;
    progressNotifier.value = progressNotifier.value.copyWith(sizeInfo: val);
  }

  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  set errorMessage(String? val) {
    _errorMessage = val;
    progressNotifier.value = progressNotifier.value.copyWith(errorMessage: val);
  }

  String? filePath;
  String? localArtPath; // Local cached thumbnail path for offline/lock screen notification
  String engineUsed; // 'yt-dlp (Auto/Fast)', 'pytubefix', 'Pure Dart'
  Process? activeProcess;

  late final ValueNotifier<DownloadProgressData> progressNotifier;

  static bool isAudioFormat(String format) {
    final f = format.toLowerCase().trim();
    return f == 'mp3' ||
        f == 'm4a' ||
        f == 'opus' ||
        f == 'ogg' ||
        f == 'flac' ||
        f == 'wav' ||
        f == 'aac';
  }

  DownloadTask({
    required this.id,
    required this.video,
    required bool isAudio,
    required this.format,
    required this.quality,
    required this.outputPath,
    DownloadStatus status = DownloadStatus.queued,
    double progress = 0.0,
    String speed = '0 KB/s',
    String eta = '--',
    String sizeInfo = '0 MB / 0 MB',
    this.filePath,
    this.localArtPath,
    String? errorMessage,
    this.engineUsed = 'yt-dlp',
    this.activeProcess,
  })  : isAudio = isAudio || isAudioFormat(format),
        _status = status,
        _progress = progress,
        _speed = speed,
        _eta = eta,
        _sizeInfo = sizeInfo,
        _errorMessage = errorMessage {
    progressNotifier = ValueNotifier<DownloadProgressData>(
      DownloadProgressData(
        progress: _progress,
        speed: _speed,
        eta: _eta,
        sizeInfo: _sizeInfo,
        status: _status,
        errorMessage: _errorMessage,
      ),
    );
  }

  void updateProgress({
    double? progress,
    String? speed,
    String? eta,
    String? sizeInfo,
    DownloadStatus? status,
    String? errorMessage,
  }) {
    if (progress != null) _progress = progress;
    if (speed != null) _speed = speed;
    if (eta != null) _eta = eta;
    if (sizeInfo != null) _sizeInfo = sizeInfo;
    if (status != null) _status = status;
    if (errorMessage != null) _errorMessage = errorMessage;
    progressNotifier.value = DownloadProgressData(
      progress: _progress,
      speed: _speed,
      eta: _eta,
      sizeInfo: _sizeInfo,
      status: _status,
      errorMessage: _errorMessage,
    );
  }

  bool get isRunning => status == DownloadStatus.downloading || status == DownloadStatus.converting;
  bool get isFinished => status == DownloadStatus.completed || status == DownloadStatus.failed || status == DownloadStatus.cancelled;

  Map<String, dynamic> toJson() => {
    'id': id,
    'video': video.toJson(),
    'isAudio': isAudio,
    'format': format,
    'quality': quality,
    'outputPath': outputPath,
    'status': status.index,
    'progress': progress,
    'sizeInfo': sizeInfo,
    'filePath': filePath,
    'localArtPath': localArtPath,
    'engineUsed': engineUsed,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] ?? '',
      video: VideoItem.fromJson(Map<String, dynamic>.from(json['video'] ?? {})),
      isAudio: json['isAudio'] ?? true,
      format: json['format'] ?? 'mp3',
      quality: json['quality'] ?? '320k',
      outputPath: json['outputPath'] ?? '',
      status: DownloadStatus.values[json['status'] ?? DownloadStatus.completed.index],
      progress: (json['progress'] as num?)?.toDouble() ?? 1.0,
      sizeInfo: json['sizeInfo'] ?? '',
      filePath: json['filePath'],
      localArtPath: json['localArtPath'],
      engineUsed: json['engineUsed'] ?? 'yt-dlp',
    );
  }
}
