import 'dart:io';
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

class DownloadTask {
  final String id;
  final VideoItem video;
  final bool isAudio;
  final String format; // mp3, m4a, flac, mp4
  final String quality; // 320k, 256k, 1080p, 4k, auto
  final String outputPath;
  
  DownloadStatus status;
  double progress; // 0.0 to 1.0
  String speed; // e.g. "5.6 MB/s"
  String eta; // e.g. "2 mins"
  String sizeInfo; // e.g. "1.2 GB / 2.5 GB"
  String? filePath;
  String? localArtPath; // Local cached thumbnail path for offline/lock screen notification
  String? errorMessage;
  String engineUsed; // 'yt-dlp (Auto/Fast)', 'pytubefix', 'Pure Dart'
  Process? activeProcess;

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
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.speed = '0 KB/s',
    this.eta = '--',
    this.sizeInfo = '0 MB / 0 MB',
    this.filePath,
    this.localArtPath,
    this.errorMessage,
    this.engineUsed = 'yt-dlp',
    this.activeProcess,
  }) : isAudio = isAudio || isAudioFormat(format);

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
