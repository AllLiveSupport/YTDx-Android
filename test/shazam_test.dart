import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shazam_identifier/shazam_identifier.dart';
import 'package:aura_app/services/song_recognition_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async {
        if (call.method == 'create') return 'test_recorder_id';
        return null;
      },
    );
  });

  test('SongRecognitionService singleton initialization & state', () {
    final service = SongRecognitionService.instance;
    expect(service, isNotNull);
    expect(service.currentStatus.state, equals(RecognitionStatusState.ready));

    service.reset();
    expect(service.currentStatus.state, equals(RecognitionStatusState.ready));
  });

  test('RecognitionResult model instantiation and serialization', () {
    final result = RecognitionResult(
      trackId: '123456',
      title: 'Seni Düşündüm',
      artist: 'Çağla',
      coverArtUrl: 'https://example.com/cover.jpg',
      coverArtHqUrl: 'https://example.com/cover_hq.jpg',
    );

    expect(result.trackId, equals('123456'));
    expect(result.title, equals('Seni Düşündüm'));
    expect(result.artist, equals('Çağla'));
    expect(result.coverArtUrl, equals('https://example.com/cover.jpg'));
    expect(result.coverArtHqUrl, equals('https://example.com/cover_hq.jpg'));
  });
}
