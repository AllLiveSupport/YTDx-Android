import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/custom_playlist.dart';
import '../models/download_task.dart';
import 'local_audio_scanner.dart';

class PlaylistManager extends ChangeNotifier {
  static final PlaylistManager instance = PlaylistManager._internal();
  PlaylistManager._internal();

  final List<CustomPlaylist> _playlists = [];
  bool _isInitialized = false;

  List<CustomPlaylist> get playlists => List.unmodifiable(_playlists);

  CustomPlaylist get favorites {
    final idx = _playlists.indexWhere((p) => p.id == 'favorites');
    if (idx != -1) return _playlists[idx];
    final fav = CustomPlaylist(
      id: 'favorites',
      title: 'Favorilerim',
      description: 'En sevdiğiniz şarkılar',
      iconName: 'favorite',
      colorValue: 0xFFEF4444,
    );
    _playlists.insert(0, fav);
    return fav;
  }

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final file = await _getStorageFile();
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final list = jsonDecode(content) as List<dynamic>;
          _playlists.clear();
          for (final item in list) {
            _playlists.add(CustomPlaylist.fromJson(item as Map<String, dynamic>));
          }
        }
      }
    } catch (_) {}

    // Ensure favorites playlist always exists
    if (!_playlists.any((p) => p.id == 'favorites')) {
      _playlists.insert(
        0,
        CustomPlaylist(
          id: 'favorites',
          title: 'Favorilerim',
          description: 'En sevdiğiniz şarkılar',
          iconName: 'favorite',
          colorValue: 0xFFEF4444,
        ),
      );
      await _saveToDisk();
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<File> _getStorageFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/custom_playlists.json');
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _getStorageFile();
      final data = _playlists.map((p) => p.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<CustomPlaylist> createPlaylist({
    required String title,
    String? description,
    String iconName = 'music_note',
    int colorValue = 0xFF3B82F6,
  }) async {
    final playlist = CustomPlaylist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim(),
      description: description?.trim(),
      iconName: iconName,
      colorValue: colorValue,
    );
    _playlists.add(playlist);
    await _saveToDisk();
    notifyListeners();
    return playlist;
  }

  Future<void> deletePlaylist(String playlistId) async {
    if (playlistId == 'favorites') return; // Cannot delete favorites
    _playlists.removeWhere((p) => p.id == playlistId);
    await _saveToDisk();
    notifyListeners();
  }

  Future<void> renamePlaylist(String playlistId, String newTitle) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      _playlists[idx].title = newTitle.trim();
      await _saveToDisk();
      notifyListeners();
    }
  }

  bool isFavorite(String? filePath) {
    if (filePath == null || filePath.isEmpty) return false;
    return favorites.trackPaths.contains(filePath);
  }

  Future<bool> toggleFavorite(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return false;
    final fav = favorites;
    bool isNowFav;
    if (fav.trackPaths.contains(filePath)) {
      fav.trackPaths.remove(filePath);
      isNowFav = false;
    } else {
      fav.trackPaths.add(filePath);
      isNowFav = true;
    }
    await _saveToDisk();
    notifyListeners();
    return isNowFav;
  }

  Future<void> addTrackToPlaylist(String playlistId, String filePath) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1 && !_playlists[idx].trackPaths.contains(filePath)) {
      _playlists[idx].trackPaths.add(filePath);
      await _saveToDisk();
      notifyListeners();
    }
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String filePath) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      _playlists[idx].trackPaths.remove(filePath);
      await _saveToDisk();
      notifyListeners();
    }
  }

  /// Resolves actual playable DownloadTasks from paths in a playlist
  Future<List<DownloadTask>> resolvePlaylistTasks(CustomPlaylist playlist) async {
    final tasks = <DownloadTask>[];
    for (final path in playlist.trackPaths) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          final track = await LocalAudioScanner.createTrackFromFile(file);
          tasks.add(track.toDownloadTask());
        } catch (_) {}
      }
    }
    return tasks;
  }
}
