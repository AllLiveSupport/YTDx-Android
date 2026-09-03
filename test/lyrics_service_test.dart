import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/models/lyrics_data.dart';

void main() {
  group('Lyrics Models & LRC Parser Tests', () {
    test('LyricLine formats into standard LRC timestamp', () {
      final line1 = LyricLine(time: const Duration(minutes: 1, seconds: 23, milliseconds: 450), text: 'Hello World');
      expect(line1.toLrcString(), '[01:23.45]Hello World');

      final line2 = LyricLine(time: const Duration(seconds: 4, milliseconds: 50), text: 'First line');
      expect(line2.toLrcString(), '[00:04.05]First line');
    });

    test('LyricsData.getActiveIndex accurately identifies current line via binary search', () {
      final lines = [
        LyricLine(time: const Duration(seconds: 5), text: 'Line 1'),
        LyricLine(time: const Duration(seconds: 12), text: 'Line 2'),
        LyricLine(time: const Duration(seconds: 20), text: 'Line 3'),
        LyricLine(time: const Duration(seconds: 35), text: 'Line 4'),
      ];
      final lyrics = LyricsData(lines: lines, isSynced: true);

      // Before first line
      expect(lyrics.getActiveIndex(const Duration(seconds: 2)), -1);
      // Exactly at first line
      expect(lyrics.getActiveIndex(const Duration(seconds: 5)), 0);
      // Between line 1 and line 2
      expect(lyrics.getActiveIndex(const Duration(seconds: 10)), 0);
      // At line 2
      expect(lyrics.getActiveIndex(const Duration(seconds: 12)), 1);
      // Between line 2 and line 3
      expect(lyrics.getActiveIndex(const Duration(seconds: 18)), 1);
      // At line 3
      expect(lyrics.getActiveIndex(const Duration(seconds: 20)), 2);
      // Between line 3 and line 4
      expect(lyrics.getActiveIndex(const Duration(seconds: 30)), 2);
      // At line 4
      expect(lyrics.getActiveIndex(const Duration(seconds: 35)), 3);
      // Far after last line
      expect(lyrics.getActiveIndex(const Duration(minutes: 2)), 3);
    });

    test('LyricsData exports to and parses from standard .lrc file format', () {
      const sampleLrc = '''
[ti:Test Title]
[ar:Test Artist]
[by:YTDx Studio]

[00:05.20]Bu gece gözümü uyku tutmadı
[00:11.80]Bir seni düşündüm bir de kendimi
[00:24.00]Saatler dolmadı sabah olmadı
''';

      final parsed = LyricsData.fromLrcString(sampleLrc, source: 'Test');
      expect(parsed, isNotNull);
      expect(parsed!.lines.length, 3);
      expect(parsed.isSynced, isTrue);
      expect(parsed.lines[0].text, 'Bu gece gözümü uyku tutmadı');
      expect(parsed.lines[0].time.inMilliseconds, 5200);
      expect(parsed.lines[1].text, 'Bir seni düşündüm bir de kendimi');
      expect(parsed.lines[1].time.inMilliseconds, 11800);
      expect(parsed.lines[2].text, 'Saatler dolmadı sabah olmadı');
      expect(parsed.lines[2].time.inMilliseconds, 24000);

      final exported = parsed.toLrcFileContent(title: 'Exported', artist: 'Artist');
      expect(exported.contains('[00:05.20]Bu gece gözümü uyku tutmadı'), isTrue);
      expect(exported.contains('[00:11.80]Bir seni düşündüm bir de kendimi'), isTrue);
    });

    test('Parses multi-line LRCLIB syncedLyrics response into synced LyricsData', () {
      const lrclibSynced = '''
[00:22.04] Bu gece gözümü uyku tutmadı
[00:27.36] Bir seni düşündüm, bir de kendimi
[00:32.86] Saatler dolmadı, sabah olmadı
[00:38.09] Bir seni düşündüm, bir de kendimi
''';
      final parsed = LyricsData.fromLrcString(lrclibSynced, source: 'Çevrimiçi (Senkronize .lrc)');
      expect(parsed, isNotNull);
      expect(parsed!.isSynced, isTrue);
      expect(parsed.lines.length, 4);
      expect(parsed.lines[0].text, 'Bu gece gözümü uyku tutmadı');
      expect(parsed.lines[0].time.inMilliseconds, 22040);
      expect(parsed.lines[1].text, 'Bir seni düşündüm, bir de kendimi');
      expect(parsed.lines[1].time.inMilliseconds, 27360);
    });
  });
}
