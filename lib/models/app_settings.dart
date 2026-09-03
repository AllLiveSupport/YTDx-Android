import 'dart:io';
import 'package:path_provider/path_provider.dart';

class AppSettings {
  String themeMode; // 'dark', 'light', 'system'
  String language; // 'tr', 'en', 'es', 'ru'
  String region; // 'TR', 'US', 'DE', 'GB', 'ES', 'RU', 'FR', 'GLOBAL'
  String trendingTopic; // 'music', 'general', 'gaming', 'movies', 'sports', 'tech', 'news'
  String engine; // 'auto', 'ytdlp', 'pytubefix'
  String downloadPreset; // 'auto_highest', 'ask_always'
  String defaultAudioFormat; // 'm4a', 'mp3', 'flac'
  String defaultVideoQuality; // 'auto', '1080p', '4k'
  String browserCookies; // 'none', 'firefox', 'chrome', 'brave', 'edge'
  String downloadPath;
  String localMusicPath;
  String ffmpegPath;
  bool isGoogleLinked;
  bool enableHaptics;
  int crossfadeSeconds; // 0 = off, 1-5 seconds

  AppSettings({
    this.themeMode = 'dark',
    this.language = 'tr',
    this.region = 'TR',
    this.trendingTopic = 'music',
    this.engine = 'ytdlp',
    this.downloadPreset = 'ask_always',
    this.defaultAudioFormat = 'm4a',
    this.defaultVideoQuality = 'auto',
    this.browserCookies = 'none',
    this.downloadPath = '',
    this.localMusicPath = '',
    this.ffmpegPath = '',
    this.isGoogleLinked = false,
    this.enableHaptics = true,
    this.crossfadeSeconds = 2,
  });

  /// Synchronous default - uses a placeholder that gets replaced on first init
  factory AppSettings.defaultSettings() {
    String defaultPath = _defaultPathSync();
    return AppSettings(downloadPath: defaultPath);
  }

  /// Get the correct default path synchronously (best-effort)
  static String _defaultPathSync() {
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? '';
        return '$home/Desktop';
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\';
        return '$userProfile\\Downloads';
      } else if (Platform.isAndroid) {
        // Public Downloads folder - will be validated/replaced at runtime
        return '/storage/emulated/0/Download';
      }
    } catch (_) {}
    return '';
  }

  /// Async version - resolves actual writable path on Android using path_provider
  static Future<String> resolveAndroidDownloadPath() async {
    if (!Platform.isAndroid) return _defaultPathSync();

    // First try the public Downloads directory (/storage/emulated/0/Download)
    const publicDownloads = '/storage/emulated/0/Download';
    try {
      final dir = Directory(publicDownloads);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      // Quick write test
      final testFile = File('$publicDownloads/.ytdx_test');
      testFile.writeAsStringSync('ok');
      testFile.deleteSync();
      return publicDownloads;
    } catch (_) {}

    // Fall back to app-specific external storage (always writable)
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        if (!extDir.existsSync()) extDir.createSync(recursive: true);
        return extDir.path;
      }
    } catch (_) {}

    // Last resort: app documents dir
    try {
      final docs = await getApplicationDocumentsDirectory();
      return docs.path;
    } catch (_) {}

    return publicDownloads;
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    var def = AppSettings.defaultSettings();
    return AppSettings(
      themeMode: json['themeMode'] ?? def.themeMode,
      language: json['language'] ?? def.language,
      region: json['region'] ?? def.region,
      trendingTopic: json['trendingTopic'] ?? def.trendingTopic,
      engine: json['engine'] ?? def.engine,
      downloadPreset: json['downloadPreset'] ?? def.downloadPreset,
      defaultAudioFormat: json['defaultAudioFormat'] ?? def.defaultAudioFormat,
      defaultVideoQuality: json['defaultVideoQuality'] ?? def.defaultVideoQuality,
      browserCookies: json['browserCookies'] ?? def.browserCookies,
      downloadPath: json['downloadPath'] ?? def.downloadPath,
      localMusicPath: json['localMusicPath'] ?? def.localMusicPath,
      ffmpegPath: json['ffmpegPath'] ?? def.ffmpegPath,
      isGoogleLinked: json['isGoogleLinked'] ?? def.isGoogleLinked,
      enableHaptics: json['enableHaptics'] ?? def.enableHaptics,
      crossfadeSeconds: json['crossfadeSeconds'] ?? def.crossfadeSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'language': language,
    'region': region,
    'trendingTopic': trendingTopic,
    'engine': engine,
    'downloadPreset': downloadPreset,
    'defaultAudioFormat': defaultAudioFormat,
    'defaultVideoQuality': defaultVideoQuality,
    'browserCookies': browserCookies,
    'downloadPath': downloadPath,
    'localMusicPath': localMusicPath,
    'ffmpegPath': ffmpegPath,
    'isGoogleLinked': isGoogleLinked,
    'enableHaptics': enableHaptics,
    'crossfadeSeconds': crossfadeSeconds,
  };
}
