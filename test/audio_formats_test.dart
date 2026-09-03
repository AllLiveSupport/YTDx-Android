import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/models/app_settings.dart';
import 'package:aura_app/models/download_task.dart';
import 'package:aura_app/models/video_item.dart';
import 'package:aura_app/services/i18n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('I18n Audio Format Translations', () {
    test('Turkish translations are present and valid', () {
      I18n.setLocale('tr');
      expect(I18n.tr('modal_mp3_320_title'), contains('320 kbps'));
      expect(I18n.tr('modal_mp3_192_title'), contains('192 kbps'));
      expect(I18n.tr('modal_mp3_128_title'), contains('128 kbps'));
      expect(I18n.tr('modal_opus_160_title'), contains('160 kbps'));
      expect(I18n.tr('modal_opus_70_title'), contains('70 kbps'));
      expect(I18n.tr('modal_m4a_256_title'), contains('256 kbps'));
      expect(I18n.tr('modal_badge_ultra'), equals('320k HQ'));
    });

    test('English translations are present and valid', () {
      I18n.setLocale('en');
      expect(I18n.tr('modal_mp3_320_title'), contains('320 kbps'));
      expect(I18n.tr('modal_opus_160_title'), contains('160 kbps'));
      expect(I18n.tr('modal_badge_max_clarity'), equals('Max Clarity'));
    });

    test('Spanish translations are present and valid', () {
      I18n.setLocale('es');
      expect(I18n.tr('modal_mp3_320_title'), contains('320 kbps'));
      expect(I18n.tr('modal_opus_160_title'), contains('160 kbps'));
      expect(I18n.tr('modal_badge_ultra'), equals('320k HQ'));
    });

    test('Russian translations are present and valid', () {
      I18n.setLocale('ru');
      expect(I18n.tr('modal_mp3_320_title'), contains('320'));
      expect(I18n.tr('modal_opus_160_title'), contains('160'));
    });
  });

  group('AppSettings Audio Format Preferences', () {
    test('defaultAudioFormat initializes and serializes correctly', () {
      final settings = AppSettings.defaultSettings();
      expect(settings.defaultAudioFormat, equals('m4a'));

      settings.defaultAudioFormat = 'mp3';
      final json = settings.toJson();
      expect(json['defaultAudioFormat'], equals('mp3'));

      final reconstructed = AppSettings.fromJson(json);
      expect(reconstructed.defaultAudioFormat, equals('mp3'));

      settings.defaultAudioFormat = 'opus';
      final jsonOpus = settings.toJson();
      expect(jsonOpus['defaultAudioFormat'], equals('opus'));
      expect(AppSettings.fromJson(jsonOpus).defaultAudioFormat, equals('opus'));
    });
  });

  group('DownloadTask Format & Quality Mapping', () {
    final sampleVideo = VideoItem(
      id: 'dQw4w9WgXcQ',
      title: 'Rick Astley - Never Gonna Give You Up',
      channel: 'Rick Astley',
      duration: '3:33',
      thumbnail: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );

    test('MP3 320k task configuration', () {
      final task = DownloadTask(
        id: 'task_1',
        video: sampleVideo,
        isAudio: true,
        format: 'mp3',
        quality: '320k',
        outputPath: '/storage/emulated/0/Download',
      );
      expect(task.isAudio, isTrue);
      expect(task.format, equals('mp3'));
      expect(task.quality, equals('320k'));
    });

    test('Opus 160k task configuration', () {
      final task = DownloadTask(
        id: 'task_2',
        video: sampleVideo,
        isAudio: true,
        format: 'opus',
        quality: '160k',
        outputPath: '/storage/emulated/0/Download',
      );
      expect(task.isAudio, isTrue);
      expect(task.format, equals('opus'));
      expect(task.quality, equals('160k'));
    });

    test('M4A 256k task configuration', () {
      final task = DownloadTask(
        id: 'task_3',
        video: sampleVideo,
        isAudio: true,
        format: 'm4a',
        quality: '256k',
        outputPath: '/storage/emulated/0/Download',
      );
      expect(task.isAudio, isTrue);
      expect(task.format, equals('m4a'));
      expect(task.quality, equals('256k'));
    });

    test('isAudioFormat helper correctly classifies formats', () {
      expect(DownloadTask.isAudioFormat('opus'), isTrue);
      expect(DownloadTask.isAudioFormat('OPUS'), isTrue);
      expect(DownloadTask.isAudioFormat('mp3'), isTrue);
      expect(DownloadTask.isAudioFormat('m4a'), isTrue);
      expect(DownloadTask.isAudioFormat('flac'), isTrue);
      expect(DownloadTask.isAudioFormat('ogg'), isTrue);
      expect(DownloadTask.isAudioFormat('wav'), isTrue);
      expect(DownloadTask.isAudioFormat('aac'), isTrue);
      expect(DownloadTask.isAudioFormat('mp4'), isFalse);
      expect(DownloadTask.isAudioFormat('mkv'), isFalse);
    });

    test('Defensive constructor guarantees isAudio is true for Opus even if isAudio: false was passed', () {
      final task = DownloadTask(
        id: 'task_opus_defensive',
        video: sampleVideo,
        isAudio: false, // Intentionally passed false
        format: 'opus',
        quality: '160k',
        outputPath: '/storage/emulated/0/Download',
      );
      expect(task.isAudio, isTrue, reason: 'Opus format must always be classified as audio');
    });
  });
}
