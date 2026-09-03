class LyricLine {
  final Duration time;
  final Duration? duration;
  final String text;

  const LyricLine({
    required this.time,
    this.duration,
    required this.text,
  });

  /// Formats line into standard LRC tag: [mm:ss.xx] Text
  String toLrcString() {
    final minutes = time.inMinutes.toString().padLeft(2, '0');
    final seconds = (time.inSeconds % 60).toString().padLeft(2, '0');
    final hundredths = ((time.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '[$minutes:$seconds.$hundredths]$text';
  }

  @override
  String toString() => toLrcString();
}

class LyricsData {
  final List<LyricLine> lines;
  final bool isSynced;
  final String source; // 'YouTube Altyazı', 'Yerel .lrc', 'Video Açıklaması'

  const LyricsData({
    required this.lines,
    required this.isSynced,
    this.source = 'YouTube',
  });

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  /// Finds the active line index for a given playback position using binary search
  int getActiveIndex(Duration position) {
    if (lines.isEmpty) return -1;
    if (position < lines.first.time) return -1;
    if (position >= lines.last.time) return lines.length - 1;

    int low = 0;
    int high = lines.length - 1;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final current = lines[mid].time;
      final next = mid + 1 < lines.length ? lines[mid + 1].time : null;

      if (position >= current && (next == null || position < next)) {
        return mid;
      } else if (position < current) {
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }

    return 0;
  }

  /// Converts all lines into standard .lrc file text format
  String toLrcFileContent({String? title, String? artist}) {
    final buffer = StringBuffer();
    if (title != null && title.isNotEmpty) buffer.writeln('[ti:$title]');
    if (artist != null && artist.isNotEmpty) buffer.writeln('[ar:$artist]');
    buffer.writeln('[by:YTDx Studio]');
    buffer.writeln();

    for (final line in lines) {
      buffer.writeln(line.toLrcString());
    }
    return buffer.toString();
  }

  /// Parses standard .lrc format text into LyricsData
  static LyricsData? fromLrcString(String lrcContent, {String source = 'Yerel .lrc'}) {
    if (lrcContent.trim().isEmpty) return null;

    final lines = <LyricLine>[];
    final lrcRegex = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\](.*)');

    for (final rawLine in lrcContent.split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      final match = lrcRegex.firstMatch(trimmed);
      if (match != null) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final fracStr = match.group(3) ?? '0';
        final millis = fracStr.length == 2
            ? (int.tryParse(fracStr) ?? 0) * 10
            : (int.tryParse(fracStr) ?? 0);

        final text = match.group(4)?.trim() ?? '';
        // Skip metadata tags or purely empty brackets
        if (text.isNotEmpty && !text.startsWith('[') && !text.endsWith(']')) {
          lines.add(LyricLine(
            time: Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
            text: text,
          ));
        }
      }
    }

    if (lines.isEmpty) return null;

    // Ensure sorted by timestamp
    lines.sort((a, b) => a.time.compareTo(b.time));

    return LyricsData(
      lines: lines,
      isSynced: true,
      source: source,
    );
  }
}
