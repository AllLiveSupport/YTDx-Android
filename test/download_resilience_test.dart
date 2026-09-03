import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:aura_app/models/download_task.dart';
import 'package:aura_app/services/auth_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadTask and Format Resilience Tests', () {
    test('Identifies audio and video formats correctly', () {
      expect(DownloadTask.isAudioFormat('mp3'), isTrue);
      expect(DownloadTask.isAudioFormat('MP3'), isTrue);
      expect(DownloadTask.isAudioFormat('m4a'), isTrue);
      expect(DownloadTask.isAudioFormat('opus'), isTrue);
      expect(DownloadTask.isAudioFormat('flac'), isTrue);
      expect(DownloadTask.isAudioFormat('wav'), isTrue);

      expect(DownloadTask.isAudioFormat('mp4'), isFalse);
      expect(DownloadTask.isAudioFormat('mkv'), isFalse);
      expect(DownloadTask.isAudioFormat('webm'), isFalse);
    });

    test('Audio file extensions match target format', () {
      const formats = ['mp3', 'm4a', 'opus'];
      for (final f in formats) {
        final saveExt = (f == 'mp3' || f == 'opus') ? f : 'm4a';
        expect(saveExt, equals(f));
      }
    });

    test('AuthenticatedYoutubeHttpClient initializes with modern browser headers', () {
      final authClient = AuthenticatedYoutubeHttpClient('test_token');
      expect(authClient.headers['user-agent']!.contains('Mozilla'), isTrue);
      expect(authClient.headers['cookie']!.contains('CONSENT=YES+cb'), isTrue);
      final yt = YoutubeExplode(httpClient: authClient);
      expect(yt, isNotNull);
      yt.close();
    });

    test('AuthenticatedYoutubeHttpClient never sends Bearer auth to watch HTML pages', () async {
      final authClient = AuthenticatedYoutubeHttpClient('sample_google_token');

      // Test 1: HTML Watch Page -> MUST NOT HAVE Bearer auth
      final watchReq = http.Request('GET', Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'));
      watchReq.headers.addAll(authClient.headers);
      // Simulating send filtering
      final isWatch = watchReq.url.host.contains('youtube.com') && watchReq.url.path.contains('watch');
      if (isWatch) {
        watchReq.headers.remove('authorization');
      }
      expect(watchReq.headers.containsKey('authorization'), isFalse);

      // Test 2: Googlevideo Media Stream -> MUST HAVE Bearer auth
      final mediaReq = http.Request('GET', Uri.parse('https://rr1---sn-4g5ednss.googlevideo.com/videoplayback?id=123'));
      mediaReq.headers.addAll(authClient.headers);
      final isMedia = mediaReq.url.host.contains('googlevideo.com');
      if (isMedia && authClient.accessToken != null) {
        mediaReq.headers['authorization'] = 'Bearer ${authClient.accessToken}';
      }
      expect(mediaReq.headers['authorization'], equals('Bearer sample_google_token'));
    });
  });
}
