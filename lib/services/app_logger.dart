import 'package:flutter/material.dart';

enum LogLevel { info, warning, error, success }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  LogEntry({
    required this.level,
    required this.tag,
    required this.message,
  }) : time = DateTime.now();

  String get levelIcon {
    switch (level) {
      case LogLevel.info: return 'ℹ';
      case LogLevel.warning: return '⚠';
      case LogLevel.error: return '✗';
      case LogLevel.success: return '✓';
    }
  }

  Color get levelColor {
    switch (level) {
      case LogLevel.info: return const Color(0xFF60A5FA);
      case LogLevel.warning: return const Color(0xFFFBBF24);
      case LogLevel.error: return const Color(0xFFF87171);
      case LogLevel.success: return const Color(0xFF34D399);
    }
  }

  String get timeStr {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final ms = (time.millisecond ~/ 10).toString().padLeft(2, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  String toString() => '[$timeStr] [${level.name.toUpperCase()}] [$tag] $message';
}

/// Global in-memory logger. Use AppLogger.log() anywhere in the app.
class AppLogger extends ChangeNotifier {
  static final AppLogger _instance = AppLogger._();
  static AppLogger get instance => _instance;
  AppLogger._();

  final List<LogEntry> _entries = [];
  List<LogEntry> get entries => List.unmodifiable(_entries);

  static void log(LogLevel level, String tag, String message) {
    final entry = LogEntry(level: level, tag: tag, message: message);
    _instance._entries.add(entry);
    // Keep max 500 entries in memory
    if (_instance._entries.length > 500) {
      _instance._entries.removeAt(0);
    }
    _instance.notifyListeners();
    // Also print to console for debugging
    debugPrint('[${entry.timeStr}][${level.name.toUpperCase()}][$tag] $message');
  }

  static void info(String tag, String msg) => log(LogLevel.info, tag, msg);
  static void warn(String tag, String msg) => log(LogLevel.warning, tag, msg);
  static void error(String tag, String msg) => log(LogLevel.error, tag, msg);
  static void success(String tag, String msg) => log(LogLevel.success, tag, msg);

  static void clear() {
    _instance._entries.clear();
    _instance.notifyListeners();
  }

  static String exportAll() {
    return _instance._entries.map((e) => e.toString()).join('\n');
  }
}
