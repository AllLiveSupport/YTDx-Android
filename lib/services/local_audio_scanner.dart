import 'dart:io';
import 'dart:typed_data';
import 'package:audiotags/audiotags.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/local_track.dart';
import 'app_logger.dart';

class LocalAudioScanner {
  static const String _tag = 'LocalAudioScanner';

  static const Set<String> supportedExtensions = {
    '.mp3',
    '.m4a',
    '.flac',
    '.ogg',
    '.wav',
    '.aac',
    '.opus',
    '.wma',
    '.alac',
    '.aiff',
  };

  // In-memory cache for ultra-fast tab switching and instant display
  static final Map<String, List<LocalTrack>> _folderCache = {};
  static final Map<String, LocalTrack> _trackCache = {};
  static String? _tempArtDir;

  static Future<String> _getArtCacheDir() async {
    if (_tempArtDir != null) return _tempArtDir!;
    try {
      final temp = await getTemporaryDirectory();
      final artDir = Directory('${temp.path}/local_art_cache');
      if (!artDir.existsSync()) {
        artDir.createSync(recursive: true);
      }
      _tempArtDir = artDir.path;
      return _tempArtDir!;
    } catch (_) {
      return '';
    }
  }

  /// Request necessary Android storage and media audio permissions
  static Future<bool> requestStoragePermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      // Android 13+ (API 33+) media permission
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) return true;

      // Android 10 and below storage permission
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;

      // Manage external storage (Android 11+)
      if (await Permission.manageExternalStorage.isGranted) return true;
    } catch (e) {
      AppLogger.warn(_tag, 'İzin isteme uyarısı: $e');
    }
    return true;
  }

  /// Recursively scans a folder and all its subdirectories for supported audio files
  static Future<List<LocalTrack>> scanDirectory(
    String folderPath, {
    bool forceRefresh = false,
  }) async {
    final cleanPath = folderPath.trim();
    if (cleanPath.isEmpty) return [];

    if (!forceRefresh && _folderCache.containsKey(cleanPath)) {
      final cached = _folderCache[cleanPath]!;
      if (cached.isNotEmpty) {
        return List.from(cached);
      }
    }

    final dir = Directory(cleanPath);
    if (!dir.existsSync()) {
      AppLogger.warn(_tag, 'Klasör bulunamadı: $cleanPath');
      return [];
    }

    await requestStoragePermissions();

    final audioFiles = <File>[];
    final queue = <Directory>[dir];
    final visited = <String>{};

    // Safe BFS directory traversal that won't crash on individual permission errors
    while (queue.isNotEmpty) {
      final currentDir = queue.removeAt(0);
      final currentPath = currentDir.path;
      if (visited.contains(currentPath)) continue;
      visited.add(currentPath);

      try {
        final entries = currentDir.listSync(recursive: false, followLinks: false);
        for (final entry in entries) {
          if (entry is File) {
            final dotIdx = entry.path.lastIndexOf('.');
            if (dotIdx != -1) {
              final ext = entry.path.substring(dotIdx).toLowerCase();
              if (supportedExtensions.contains(ext)) {
                audioFiles.add(entry);
              }
            }
          } else if (entry is Directory) {
            final name = entry.uri.pathSegments.isNotEmpty
                ? entry.uri.pathSegments[entry.uri.pathSegments.length - (entry.uri.pathSegments.last.isEmpty ? 2 : 1)]
                : '';
            // Skip hidden or system folders like .trashed, .thumbnails, Android/data
            if (!name.startsWith('.') && !entry.path.contains('/Android/data') && !entry.path.contains('/Android/obb')) {
              queue.add(entry);
            }
          }
        }
      } catch (e) {
        AppLogger.warn(_tag, 'Klasör okunamadı ($currentPath): $e');
      }
    }

    final tracks = <LocalTrack>[];
    final artCacheDir = await _getArtCacheDir();

    for (final file in audioFiles) {
      final path = file.path;
      if (!forceRefresh && _trackCache.containsKey(path)) {
        tracks.add(_trackCache[path]!);
        continue;
      }

      try {
        final stat = file.statSync();
        final rawFileName = file.uri.pathSegments.last;
        final dotIdx = rawFileName.lastIndexOf('.');
        final nameNoExt = dotIdx != -1 ? rawFileName.substring(0, dotIdx) : rawFileName;
        final ext = dotIdx != -1 ? rawFileName.substring(dotIdx + 1).toUpperCase() : 'AUDIO';

        // Extract ID3 / MP4 tags
        String title = nameNoExt;
        String artist = '';
        String album = '';
        Duration duration = Duration.zero;
        Uint8List? pictureBytes;
        String? cachedArtPath;

        try {
          final tag = await AudioTags.read(path);
          if (tag != null) {
            if (tag.title != null && tag.title!.trim().isNotEmpty) {
              title = tag.title!.trim();
            }
            if (tag.trackArtist != null && tag.trackArtist!.trim().isNotEmpty) {
              artist = tag.trackArtist!.trim();
            } else if (tag.albumArtist != null && tag.albumArtist!.trim().isNotEmpty) {
              artist = tag.albumArtist!.trim();
            }
            if (tag.album != null && tag.album!.trim().isNotEmpty) {
              album = tag.album!.trim();
            }
            if (tag.duration != null && tag.duration! > 0) {
              duration = Duration(seconds: tag.duration!);
            }
            if (tag.pictures.isNotEmpty) {
              final pic = tag.pictures.first;
              if (pic.bytes.isNotEmpty) {
                pictureBytes = pic.bytes;
                // Cache cover image file for Android MediaSession/lockscreen notification
                if (artCacheDir.isNotEmpty) {
                  final artFile = File('$artCacheDir/${path.hashCode.abs()}.jpg');
                  if (!artFile.existsSync()) {
                    artFile.writeAsBytesSync(pictureBytes);
                  }
                  cachedArtPath = artFile.path;
                }
              }
            }
          }
        } catch (_) {}

        // Fallback: Check folder for cover.jpg, folder.jpg, album.jpg if no embedded art
        if (pictureBytes == null && cachedArtPath == null) {
          try {
            final parent = file.parent;
            final commonCoverNames = ['cover.jpg', 'cover.png', 'folder.jpg', 'album.jpg', 'front.jpg'];
            for (final coverName in commonCoverNames) {
              final coverFile = File('${parent.path}/$coverName');
              if (coverFile.existsSync()) {
                pictureBytes = coverFile.readAsBytesSync();
                cachedArtPath = coverFile.path;
                break;
              }
            }
          } catch (_) {}
        }

        final track = LocalTrack(
          filePath: path,
          title: title,
          artist: artist.isNotEmpty ? artist : 'Yerel Sanatçı',
          album: album.isNotEmpty ? album : file.parent.uri.pathSegments.reversed.skip(1).firstOrNull ?? 'Bilinmeyen Albüm',
          duration: duration,
          format: ext,
          sizeBytes: stat.size,
          dateModified: stat.modified,
          pictureBytes: pictureBytes,
          cachedArtPath: cachedArtPath,
        );

        _trackCache[path] = track;
        tracks.add(track);
      } catch (e) {
        AppLogger.warn(_tag, 'Parça okunamadı ($path): $e');
      }
    }

    // Sort by Title A-Z by default
    tracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    _folderCache[cleanPath] = tracks;
    AppLogger.success(_tag, '🎵 $cleanPath klasöründe ${tracks.length} müzik bulundu.');
    return tracks;
  }

  /// Parses a single audio file into a LocalTrack
  static Future<LocalTrack> createTrackFromFile(File file) async {
    final path = file.path;
    if (_trackCache.containsKey(path)) {
      return _trackCache[path]!;
    }
    final artCacheDir = await _getArtCacheDir();
    final stat = file.statSync();
    final rawFileName = file.uri.pathSegments.last;
    final dotIdx = rawFileName.lastIndexOf('.');
    final nameNoExt = dotIdx != -1 ? rawFileName.substring(0, dotIdx) : rawFileName;
    final ext = dotIdx != -1 ? rawFileName.substring(dotIdx + 1).toUpperCase() : 'AUDIO';

    String title = nameNoExt;
    String artist = '';
    String album = '';
    Duration duration = Duration.zero;
    Uint8List? pictureBytes;
    String? cachedArtPath;

    try {
      final tag = await AudioTags.read(path);
      if (tag != null) {
        if (tag.title != null && tag.title!.trim().isNotEmpty) title = tag.title!.trim();
        if (tag.trackArtist != null && tag.trackArtist!.trim().isNotEmpty) {
          artist = tag.trackArtist!.trim();
        } else if (tag.albumArtist != null && tag.albumArtist!.trim().isNotEmpty) {
          artist = tag.albumArtist!.trim();
        }
        if (tag.album != null && tag.album!.trim().isNotEmpty) album = tag.album!.trim();
        if (tag.duration != null && tag.duration! > 0) duration = Duration(seconds: tag.duration!);
        if (tag.pictures.isNotEmpty) {
          final pic = tag.pictures.first;
          if (pic.bytes.isNotEmpty) {
            pictureBytes = pic.bytes;
            if (artCacheDir.isNotEmpty) {
              final artFile = File('$artCacheDir/${path.hashCode.abs()}.jpg');
              if (!artFile.existsSync()) {
                artFile.writeAsBytesSync(pictureBytes);
              }
              cachedArtPath = artFile.path;
            }
          }
        }
      }
    } catch (_) {}

    final track = LocalTrack(
      filePath: path,
      title: title,
      artist: artist.isNotEmpty ? artist : 'Yerel Sanatçı',
      album: album.isNotEmpty ? album : 'Bilinmeyen Albüm',
      duration: duration,
      format: ext,
      sizeBytes: stat.size,
      dateModified: stat.modified,
      pictureBytes: pictureBytes,
      cachedArtPath: cachedArtPath,
    );
    _trackCache[path] = track;
    return track;
  }

  /// Clears folder cache to force fresh rescan
  static void clearCache([String? folderPath]) {
    if (folderPath != null) {
      _folderCache.remove(folderPath);
    } else {
      _folderCache.clear();
      _trackCache.clear();
    }
  }
}
