import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/video_item.dart';
import '../models/download_task.dart';
import '../models/app_settings.dart';
import '../services/youtube_service.dart';
import '../services/download_manager.dart';
import '../services/i18n.dart';

class BatchDownloadResult {
  final int queued;
  final int skipped;
  const BatchDownloadResult({required this.queued, required this.skipped});
}

class AppState extends ChangeNotifier {
  // Navigation
  int _currentTabIndex = 0;
  int get currentTabIndex => _currentTabIndex;

  // Search & Trending
  String _searchQuery = '';
  String get searchQuery => _searchQuery;
  List<VideoItem> searchResults = [];
  List<VideoItem> trendingVideos = [];
  bool isSearching = false;
  bool isTrendingLoading = false;
  String selectedFilter = 'All'; // 'All', 'Video', 'Audio', 'Playlist'

  // Downloads Queue & Completed Library
  List<DownloadTask> tasks = [];
  List<DownloadTask> completedTasks = [];
  static const int maxConcurrentDownloads = 2; // Keep UI smooth & prevent network congestion

  // Playlists
  List<VideoItem> playlistVideos = [];
  bool isPlaylistLoading = false;
  String? currentPlaylistUrl;

  // Settings
  late AppSettings settings;

  AppState() {
    settings = AppSettings.defaultSettings();
    I18n.setLocale(settings.language);
    _initStorage();
  }

  Future<void> _initStorage() async {
    await _loadSettings();
    await _loadHistory();

    // On Android: resolve the actual writable download path
    if (Platform.isAndroid) {
      final resolvedPath = await AppSettings.resolveAndroidDownloadPath();
      if (settings.downloadPath.isEmpty || settings.downloadPath == '/storage/emulated/0/Download') {
        // Verify the default path is actually writable, update if not
        try {
          final testFile = File('${settings.downloadPath}/.ytdx_check');
          testFile.writeAsStringSync('ok');
          testFile.deleteSync();
          // Default path is fine, keep it
        } catch (_) {
          settings.downloadPath = resolvedPath;
          saveSettings();
        }
      }
      notifyListeners();
    }

    fetchTrending();
  }

  void setTabIndex(int index) {
    _currentTabIndex = index;
    notifyListeners();
  }

  // --- Localization & Region & Trends ---
  void setLanguage(String lang) {
    settings.language = lang;
    I18n.setLocale(lang);
    saveSettings();
    notifyListeners();
  }

  void setRegion(String region) {
    settings.region = region;
    saveSettings();
    fetchTrending();
  }

  void setTrendingTopic(String topic) {
    settings.trendingTopic = topic;
    saveSettings();
    fetchTrending();
  }

  void setLocalMusicPath(String path) {
    settings.localMusicPath = path;
    saveSettings();
    notifyListeners();
  }

  void setEnableHaptics(bool enabled) {
    settings.enableHaptics = enabled;
    saveSettings();
    notifyListeners();
  }

  void setDefaultAudioFormat(String format) {
    settings.defaultAudioFormat = format;
    saveSettings();
    notifyListeners();
  }

  void setCrossfadeSeconds(int seconds) {
    settings.crossfadeSeconds = seconds;
    saveSettings();
    notifyListeners();
  }

  // --- Search & Trending ---
  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    _searchQuery = query;
    isSearching = true;
    notifyListeners();

    try {
      searchResults = await YouTubeService.searchVideos(query);
    } catch (e) {
      searchResults = [];
    } finally {
      isSearching = false;
      notifyListeners();
    }
  }

  bool isLoadingMore = false;
  Future<void> loadMoreSearchResults() async {
    if (isLoadingMore || isSearching || _searchQuery.isEmpty) return;
    isLoadingMore = true;
    notifyListeners();

    try {
      final more = await YouTubeService.loadMoreSearchResults();
      if (more.isNotEmpty) {
        // Prevent duplicate IDs
        final existingIds = searchResults.map((e) => e.id).toSet();
        for (var item in more) {
          if (!existingIds.contains(item.id)) {
            searchResults.add(item);
          }
        }
      }
    } catch (_) {} finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  static final Map<String, List<VideoItem>> _trendingMemoryCache = {};

  Future<void> fetchTrending({bool force = false}) async {
    // YouTubeService now handles its own 30-min TTL cache.
    // We keep a simple session cache here only to prevent redundant calls
    // within the same app session if force=false.
    final cacheKey = '${settings.region}_${settings.trendingTopic}';
    if (!force && _trendingMemoryCache.containsKey(cacheKey) && _trendingMemoryCache[cacheKey]!.isNotEmpty) {
      trendingVideos = _trendingMemoryCache[cacheKey]!;
      isTrendingLoading = false;
      notifyListeners();
      return;
    }

    isTrendingLoading = true;
    notifyListeners();

    try {
      final videos = await YouTubeService.fetchTrendingVideos(
        region: settings.region,
        topic: settings.trendingTopic,
      );
      if (videos.isNotEmpty) {
        trendingVideos = videos;
        _trendingMemoryCache[cacheKey] = videos;
      }
    } catch (e) {
      if (!_trendingMemoryCache.containsKey(cacheKey)) {
        trendingVideos = [];
      }
    } finally {
      isTrendingLoading = false;
      notifyListeners();
    }
  }

  /// Force-refresh trending — clears session cache so YouTubeService re-fetches
  Future<void> refreshTrending() async {
    final cacheKey = '${settings.region}_${settings.trendingTopic}';
    _trendingMemoryCache.remove(cacheKey);
    await fetchTrending(force: true);
  }


  void setFilter(String filter) {
    selectedFilter = filter;
    notifyListeners();
  }

  bool get isLoadingTrending => isTrendingLoading;

  // --- Playlist Fetching ---
  Future<void> fetchPlaylist(String url) => loadPlaylist(url);

  Future<void> loadPlaylist(String url) async {
    if (url.trim().isEmpty) return;
    currentPlaylistUrl = url;
    isPlaylistLoading = true;
    playlistVideos = [];
    notifyListeners();

    try {
      playlistVideos = await YouTubeService.fetchPlaylistVideos(url.trim());
    } catch (_) {
      playlistVideos = [];
    } finally {
      isPlaylistLoading = false;
      notifyListeners();
    }
  }

  void togglePlaylistSelection(int index) {
    if (index >= 0 && index < playlistVideos.length) {
      playlistVideos[index].isSelected = !playlistVideos[index].isSelected;
      notifyListeners();
    }
  }

  void selectAllPlaylist(bool select) {
    for (var v in playlistVideos) {
      v.isSelected = select;
    }
    notifyListeners();
  }

  // --- Download Engine & Queue Management ---
  String? _checkExistingFile(VideoItem video, String targetDir, String format) {
    try {
      final dir = Directory(targetDir);
      if (!dir.existsSync()) return null;

      final cleanTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').toLowerCase();
      final ext = format.toLowerCase();

      for (var f in dir.listSync(recursive: false).whereType<File>()) {
        final path = f.path.toLowerCase();
        if (path.endsWith('.$ext')) {
          final fileName = f.uri.pathSegments.last.toLowerCase();
          final baseName = fileName.replaceAll(RegExp(r'\.[a-z0-9]+$'), '');
          if (cleanTitle.contains(baseName) || baseName.contains(cleanTitle) || baseName.contains(video.id.toLowerCase())) {
            if (f.lengthSync() > 100 * 1024) {
              return f.path;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  void startDownload({
    required VideoItem video,
    required bool isAudio,
    String? format,
    String? quality,
    String? outputPath,
  }) {
    final effectiveIsAudio = isAudio || (format != null && DownloadTask.isAudioFormat(format));
    final effectiveFormat = format ?? (effectiveIsAudio ? settings.defaultAudioFormat : 'mp4');
    final effectiveQuality = quality ?? (effectiveIsAudio ? '320k' : settings.defaultVideoQuality);
    final targetDir = (outputPath != null && outputPath.isNotEmpty)
        ? outputPath
        : (settings.downloadPath.isNotEmpty ? settings.downloadPath : AppSettings.defaultSettings().downloadPath);

    final existing = _checkExistingFile(video, targetDir, effectiveFormat);
    if (existing != null) {
      final completedTask = DownloadTask(
        id: '${video.id}_${DateTime.now().millisecondsSinceEpoch}',
        video: video,
        isAudio: effectiveIsAudio,
        format: effectiveFormat,
        quality: effectiveQuality,
        outputPath: targetDir,
        status: DownloadStatus.completed,
        filePath: existing,
        engineUsed: settings.engine,
      );
      if (!completedTasks.any((ct) => ct.video.id == video.id)) {
        completedTasks.insert(0, completedTask);
        _saveHistory();
      }
      notifyListeners();
      return;
    }

    final task = DownloadTask(
      id: '${video.id}_${DateTime.now().millisecondsSinceEpoch}',
      video: video,
      isAudio: effectiveIsAudio,
      format: effectiveFormat,
      quality: effectiveQuality,
      outputPath: targetDir,
      status: DownloadStatus.queued,
      engineUsed: settings.engine == 'pytubefix' ? 'pytubefix' : (settings.engine == 'ytdlp' ? 'yt-dlp' : 'auto'),
    );

    tasks.insert(0, task);
    notifyListeners();
    _processQueue();
  }

  BatchDownloadResult startBatchDownload({
    required List<VideoItem> selectedVideos,
    required bool isAudio,
    String? format,
    String? quality,
    String? outputPath,
  }) {
    final targetDir = (outputPath != null && outputPath.isNotEmpty)
        ? outputPath
        : (settings.downloadPath.isNotEmpty ? settings.downloadPath : AppSettings.defaultSettings().downloadPath);

    final effectiveIsAudio = isAudio || (format != null && DownloadTask.isAudioFormat(format));
    final effectiveFormat = format ?? (effectiveIsAudio ? settings.defaultAudioFormat : 'mp4');
    final effectiveQuality = quality ?? (effectiveIsAudio ? '256k' : 'auto');

    int skippedCount = 0;
    int queuedCount = 0;

    for (var video in selectedVideos) {
      final existingFilePath = _checkExistingFile(video, targetDir, effectiveFormat);
      if (existingFilePath != null) {
        skippedCount++;
        final completedTask = DownloadTask(
          id: '${video.id}_${DateTime.now().millisecondsSinceEpoch}_${selectedVideos.indexOf(video)}',
          video: video,
          isAudio: effectiveIsAudio,
          format: effectiveFormat,
          quality: effectiveQuality,
          outputPath: targetDir,
          status: DownloadStatus.completed,
          filePath: existingFilePath,
          engineUsed: settings.engine,
        );
        if (!completedTasks.any((ct) => ct.video.id == video.id)) {
          completedTasks.insert(0, completedTask);
        }
      } else {
        queuedCount++;
        final task = DownloadTask(
          id: '${video.id}_${DateTime.now().millisecondsSinceEpoch}_${selectedVideos.indexOf(video)}',
          video: video,
          isAudio: effectiveIsAudio,
          format: effectiveFormat,
          quality: effectiveQuality,
          outputPath: targetDir,
          status: DownloadStatus.queued,
          engineUsed: settings.engine == 'pytubefix' ? 'pytubefix' : (settings.engine == 'ytdlp' ? 'yt-dlp' : 'auto'),
        );
        tasks.add(task);
      }
    }

    if (skippedCount > 0) {
      _saveHistory();
    }

    notifyListeners();
    _processQueue();

    return BatchDownloadResult(queued: queuedCount, skipped: skippedCount);
  }

  void _processQueue() {
    final activeCount = tasks.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.converting).length;
    if (activeCount >= maxConcurrentDownloads) {
      return; // Slots full, wait for active downloads to finish
    }

    final pendingTasks = tasks.where((t) => t.status == DownloadStatus.queued).toList();
    if (pendingTasks.isEmpty) return;

    final slotsAvailable = maxConcurrentDownloads - activeCount;
    for (int i = 0; i < slotsAvailable && i < pendingTasks.length; i++) {
      final task = pendingTasks[i];
      _executeTask(task);
    }
  }

  void _executeTask(DownloadTask task) {
    task.status = DownloadStatus.downloading;
    notifyListeners();

    DownloadManager.executeDownload(
      task: task,
      settings: settings,
      onUpdate: () {
        if (task.status == DownloadStatus.completed) {
          if (!completedTasks.any((ct) => ct.id == task.id)) {
            completedTasks.insert(0, task);
            _saveHistory();
          }
        }
        notifyListeners();

        // When task finishes or fails, trigger next queued item
        if (task.status == DownloadStatus.completed || task.status == DownloadStatus.failed || task.status == DownloadStatus.cancelled) {
          _processQueue();
        }
      },
    );
  }

  void cancelTask(DownloadTask task) {
    DownloadManager.cancelTask(task);
    tasks.remove(task);
    notifyListeners();
    _processQueue();
  }

  void cancelAllTasks() {
    for (var task in List.from(tasks)) {
      DownloadManager.cancelTask(task);
    }
    tasks.clear();
    notifyListeners();
  }

  void deleteCompletedTask(DownloadTask task, {bool deleteFromDisk = true}) {
    completedTasks.removeWhere((t) => t.id == task.id);
    tasks.removeWhere((t) => t.id == task.id);
    _saveHistory();
    if (deleteFromDisk && task.filePath != null) {
      try {
        final f = File(task.filePath!);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  void clearCompletedTasks() {
    completedTasks.clear();
    _saveHistory();
    notifyListeners();
  }

  void clearCache() {
    tasks.clear();
    completedTasks.clear();
    _saveHistory();
    notifyListeners();
  }

  // --- Settings & History Persistence ---
  Future<void> _loadSettings() async {
    try {
      final file = await _getSettingsFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content);
        settings = AppSettings.fromJson(json);
        I18n.setLocale(settings.language);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> saveSettings() async {
    try {
      final file = await _getSettingsFile();
      await file.writeAsString(jsonEncode(settings.toJson()));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    try {
      final file = await _getHistoryFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List list = jsonDecode(content);
        completedTasks = list.map((item) => DownloadTask.fromJson(Map<String, dynamic>.from(item))).toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final file = await _getHistoryFile();
      final data = completedTasks.map((t) => t.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<File> _getSettingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/ytdx_settings.json');
  }

  Future<File> _getHistoryFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/ytdx_history.json');
  }
}
