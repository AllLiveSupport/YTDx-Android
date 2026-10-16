import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/services/visionos_stream_resolver.dart';

void main() {
  group('VisionosStreamResolver Tests', () {
    test('Resolves direct VisionOS unthrottled streaming URLs for video and audio', () async {
      // Test video ID: LXb3EKWsInQ (4K sample)
      const videoId = 'LXb3EKWsInQ';
      
      // itag 315 (4K 2160p60 VP9)
      final url315 = await VisionosStreamResolver.getStreamUrl(videoId, 315);
      expect(url315, isNotNull);
      expect(url315, contains('c=VISIONOS'));
      expect(url315, contains('googlevideo.com'));

      // itag 140 (128k AAC Audio)
      final url140 = await VisionosStreamResolver.getStreamUrl(videoId, 140);
      expect(url140, isNotNull);
      expect(url140, contains('c=VISIONOS'));

      // Empty videoId handling
      final emptyResult = await VisionosStreamResolver.getStreamUrl('', 315);
      expect(emptyResult, isNull);
    });
  });
}
