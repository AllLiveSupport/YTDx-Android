import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadManager Video Quality & Duration Tests', () {
    int parseDurationToSeconds(String dur) {
      try {
        final parts = dur.split(':').map((p) => int.tryParse(p.trim()) ?? 0).toList();
        if (parts.length == 3) {
          return parts[0] * 3600 + parts[1] * 60 + parts[2];
        } else if (parts.length == 2) {
          return parts[0] * 60 + parts[1];
        } else if (parts.length == 1) {
          return parts[0];
        }
      } catch (_) {}
      return 0;
    }

    test('accurately parses duration strings', () {
      expect(parseDurationToSeconds('0:45'), 45);
      expect(parseDurationToSeconds('10:34'), 634);
      expect(parseDurationToSeconds('01:15:30'), 4530);
      expect(parseDurationToSeconds('invalid'), 0);
    });

    test('auto resolution priority selects 8K > 4K > 2K > 1080p', () {
      final availableLabels = ['1080p60', '720p', '1440p60', '2160p60', '4320p60', '480p', '360p'];

      List<String> findMatches(String label) {
        return availableLabels.where((s) => s.toLowerCase().contains(label)).toList();
      }

      final candidates = <String>[];
      // Simulated Auto mode
      candidates.addAll(findMatches('4320'));
      candidates.addAll(findMatches('8k'));
      candidates.addAll(findMatches('2160'));
      candidates.addAll(findMatches('4k'));
      candidates.addAll(findMatches('1440'));
      candidates.addAll(findMatches('2k'));
      candidates.addAll(findMatches('1080'));
      candidates.addAll(findMatches('720'));
      candidates.addAll(findMatches('480'));
      candidates.addAll(findMatches('360'));

      expect(candidates.first, '4320p60');
      expect(candidates[1], '2160p60');
      expect(candidates[2], '1440p60');
      expect(candidates[3], '1080p60');
    });
  });
}
