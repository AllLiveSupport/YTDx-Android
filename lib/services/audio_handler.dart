import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// A proper AudioHandler implementation for audio_service.
/// This creates the real Android foreground service with media session
/// controls on lock screen and notification shade across all Android skins (including HyperOS / MIUI).
class YTDxAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  void Function()? onSkipNext;
  void Function()? onSkipPrevious;
  void Function()? onStopPlayer;

  YTDxAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.playerStateStream.listen((state) {
      _broadcastState(_player.playbackEvent);
    });
  }

  AudioPlayer get player => _player;

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_player.processingState] ?? AudioProcessingState.idle;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
    ));
    if (onStopPlayer != null) {
      onStopPlayer!();
    }
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (onSkipNext != null) {
      onSkipNext!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (onSkipPrevious != null) {
      onSkipPrevious!();
    }
  }

  Future<void> playMediaItemFromFile(MediaItem item, String filePath) async {
    try {
      mediaItem.add(item);
      final source = AudioSource.file(filePath, tag: item);
      await _player.setAudioSource(source, initialPosition: Duration.zero);
      await _player.seek(Duration.zero);
      await _player.play();
      _broadcastState(_player.playbackEvent);
    } on PlayerInterruptedException catch (_) {
      // Expected when tracks change rapidly or user skips track while loading
    } on PlayerException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      if (!msg.contains('abort') && !msg.contains('interrupt')) {
        rethrow;
      }
    } catch (e) {
      final str = e.toString().toLowerCase();
      if (!str.contains('interrupted') && !str.contains('abort')) {
        rethrow;
      }
    }
  }

  Future<void> setLoopModeAudio(LoopMode mode) => _player.setLoopMode(mode);

  Future<void> setVolumeAudio(double v) => _player.setVolume(v);
}
