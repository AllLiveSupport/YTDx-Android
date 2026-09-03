import 'dart:io';
import 'dart:typed_data';
import '../models/download_task.dart';
import '../models/video_item.dart';

class LocalTrack {
  final String filePath;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String format;
  final int sizeBytes;
  final DateTime dateModified;
  final Uint8List? pictureBytes;
  String? cachedArtPath;

  LocalTrack({
    required this.filePath,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.format,
    required this.sizeBytes,
    required this.dateModified,
    this.pictureBytes,
    this.cachedArtPath,
  });

  String get durationStr {
    if (duration.inSeconds <= 0) return '--:--';
    final hours = duration.inHours;
    final mins = duration.inMinutes % 60;
    final secs = duration.inSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String get sizeStr {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }

  bool get hasEmbeddedArt => pictureBytes != null && pictureBytes!.isNotEmpty;

  /// Converts this local track into a DownloadTask for seamless playback through PlayerProvider
  DownloadTask toDownloadTask() {
    final file = File(filePath);
    final id = 'local_${filePath.hashCode.abs()}';

    return DownloadTask(
      id: id,
      video: VideoItem(
        id: id,
        url: '',
        title: title,
        channel: artist.isNotEmpty ? artist : 'Yerel Müzik',
        thumbnail: '',
        duration: durationStr,
      ),
      isAudio: true,
      format: format.toLowerCase(),
      quality: '',
      outputPath: file.parent.path,
      filePath: filePath,
      localArtPath: cachedArtPath,
      status: DownloadStatus.completed,
    );
  }
}
