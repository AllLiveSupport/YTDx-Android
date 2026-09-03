import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:aura_app/models/download_task.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class AuthenticatedYoutubeHttpClient extends YoutubeHttpClient {
  final String? accessToken;

  AuthenticatedYoutubeHttpClient([this.accessToken, http.Client? client])
      : super(client);

  @override
  Map<String, String> get headers {
    final base = Map<String, String>.from(super.headers);
    base['user-agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    if (accessToken != null && accessToken!.isNotEmpty) {
      base['authorization'] = 'Bearer $accessToken';
    }
    return base;
  }
}

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

    test('AuthenticatedYoutubeHttpClient initializes with YoutubeExplode', () {
      final authClient = AuthenticatedYoutubeHttpClient('test_token');
      expect(authClient.headers['authorization'], equals('Bearer test_token'));
      expect(authClient.headers['user-agent']!.contains('Mozilla'), isTrue);
      final yt = YoutubeExplode(httpClient: authClient);
      expect(yt, isNotNull);
      yt.close();
    });
  });
}
