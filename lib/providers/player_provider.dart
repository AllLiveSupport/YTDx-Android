import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/download_task.dart';
import '../models/lyrics_data.dart';
import '../services/app_logger.dart';
import '../services/audio_handler.dart';
import '../services/lyrics_service.dart';

export 'package:just_audio/just_audio.dart' show LoopMode;

const String _tag = 'PlayerProvider';

enum CustomPlayerState { stopped, playing, paused }

class PlayerProvider extends ChangeNotifier {
  Process? _nativeProcess;
  Timer? _posTicker;
  int _currentPlaybackSessionId = 0;
  bool _completionHandled = false; // guard against double-trigger

  // audio_service handler (mobile only)
  final YTDxAudioHandler? _audioHandler;

  // Shortcut to the underlying just_audio player inside the handler
  AudioPlayer? get _mobilePlayer => _audioHandler?.player;

  DownloadTask? _currentTask;
  List<DownloadTask> _queue = [];
  int _currentIndex = -1;

  CustomPlayerState _playerState = CustomPlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 0.85;
  int _crossfadeSeconds = 2;
  bool _isShuffle = false;
  LoopMode _loopMode = LoopMode.off;
  bool _isVisible = false;

  // Synced Lyrics State
  LyricsData? _currentLyrics;
  bool _isLoadingLyrics = false;
  int _activeLyricIndex = -1;

  LyricsData? get currentLyrics => _currentLyrics;
  bool get isLoadingLyrics => _isLoadingLyrics;
  int get activeLyricIndex => _activeLyricIndex;

  // Smart Sleep Timer & Fade-out State
  Timer? _sleepTicker;
  DateTime? _sleepTimerTarget;
  Duration? _sleepTimerTotalDuration;
  Duration? _sleepTimerRemaining;
  bool _sleepTimerEndOfTrack = false;
  bool _sleepTimerFadeOut = true;

  bool get isSleepTimerActive => _sleepTimerTarget != null || _sleepTimerEndOfTrack;
  Duration? get sleepTimerRemaining => _sleepTimerRemaining;
  Duration? get sleepTimerTotalDuration => _sleepTimerTotalDuration;
  bool get isSleepTimerEndOfTrack => _sleepTimerEndOfTrack;
  bool get sleepTimerFadeOut => _sleepTimerFadeOut;

  int get crossfadeSeconds => _crossfadeSeconds;
  void setCrossfadeSeconds(int seconds) {
    _crossfadeSeconds = seconds;
    notifyListeners();
  }

  PlayerProvider({this._audioHandler}) {
    if (Platform.isAndroid || Platform.isIOS) {
      _initMobilePlayer();
    } else {
      cleanupAllAudioProcesses();
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          ProcessSignal.sigint.watch().listen((_) => cleanupAllAudioProcesses());
          ProcessSignal.sigterm.watch().listen((_) => cleanupAllAudioProcesses());
        } catch (_) {}
      }
    }
  }

  Future<void> _initMobilePlayer() async {
    if (_audioHandler == null) return;

    // Connect Android lock screen / notification actions directly to PlayerProvider queue
    _audioHandler.onSkipNext = () => playNext();
    _audioHandler.onSkipPrevious = () => playPrevious();
    _audioHandler.onStopPlayer = () => stop();

    _mobilePlayer!.positionStream.listen((p) {
      _position = p;

      // Update active lyric line index if lyrics are loaded
      if (_currentLyrics != null && _currentLyrics!.isNotEmpty) {
        final newIdx = _currentLyrics!.getActiveIndex(p);
        if (newIdx != _activeLyricIndex) {
          _activeLyricIndex = newIdx;
        }
      }

      // Crossfade logic: gently ramp volume down as track nears end and trigger smooth next
      if (_crossfadeSeconds > 0 &&
          _duration > Duration(seconds: _crossfadeSeconds + 3) &&
          _playerState == CustomPlayerState.playing &&
          !_completionHandled) {
        final remaining = _duration - p;
        if (remaining <= Duration(seconds: _crossfadeSeconds)) {
          final factor = (remaining.inMilliseconds / (_crossfadeSeconds * 1000)).clamp(0.0, 1.0);
          _mobilePlayer?.setVolume((_volume * factor).clamp(0.0, 1.0));

          if (remaining <= const Duration(milliseconds: 350)) {
            _handleTrackCompleted();
          }
        }
      }

      // End of Track Sleep Timer: 15-second gentle fade-out
      if (_sleepTimerEndOfTrack && _sleepTimerFadeOut && _duration > Duration.zero) {
        final remaining = _duration - p;
        if (remaining.inSeconds <= 15 && remaining.inSeconds >= 0) {
          final factor = (remaining.inMilliseconds / 15000.0).clamp(0.0, 1.0);
          _mobilePlayer?.setVolume((_volume * factor).clamp(0.0, _volume));
        }
      }

      notifyListeners();
    });

    _mobilePlayer!.durationStream.listen((d) {
      if (d != null && d > Duration.zero) {
        _duration = d;
        notifyListeners();
      }
    });

    _mobilePlayer!.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompleted();
        return;
      }
      final newPlaying = state.playing;
      if (newPlaying && _playerState != CustomPlayerState.playing) {
        _playerState = CustomPlayerState.playing;
        _completionHandled = false;
        notifyListeners();
      } else if (!newPlaying && _playerState != CustomPlayerState.paused && _playerState != CustomPlayerState.stopped) {
        _playerState = CustomPlayerState.paused;
        notifyListeners();
      }
    });
  }

  void _replayCurrentTrack() {
    if (_currentTask == null) return;
    _position = Duration.zero;
    _completionHandled = false;
    _playerState = CustomPlayerState.playing;
    _activeLyricIndex = _currentLyrics?.getActiveIndex(Duration.zero) ?? -1;
    notifyListeners();

    if (Platform.isAndroid || Platform.isIOS) {
      _mobilePlayer?.seek(Duration.zero).then((_) {
        _mobilePlayer?.setVolume(_volume);
        _mobilePlayer?.play();
      });
    } else {
      _startNativePlayback(_currentTask!.filePath!, Duration.zero);
    }
  }

  void _handleTrackCompleted() {
    if (_completionHandled) return; // prevent double-trigger
    _completionHandled = true;

    // 🌙 Uyku Zamanlayıcısı: Parça sonu seçildiyse müziği kapat
    if (_sleepTimerEndOfTrack) {
      AppLogger.info(_tag, '🌙 Uyku zamanlayıcısı: Parça sonuna ulaşıldı, oynatıcı durduruluyor.');
      cancelSleepTimer();
      pause();
      return;
    }

    AppLogger.info(_tag, '🎵 Parça tamamlandı. Döngü modu: $_loopMode');

    // 🔂 Tek Şarkı Döngüsü (LoopMode.one) -> Parçayı kesintisiz baştan çal
    if (_loopMode == LoopMode.one && _currentTask != null) {
      AppLogger.info(_tag, '🔂 Tek Şarkı Döngüsü: Parça baştan çalınıyor...');
      _replayCurrentTrack();
      return;
    }

    playNext(autoAdvance: true);
  }

  /// Kills any lingering ffplay or mpv playback processes
  static void cleanupAllAudioProcesses() {
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        Process.runSync('killall', ['-9', 'ffplay']);
      } else if (Platform.isWindows) {
        Process.runSync('taskkill', ['/F', '/IM', 'ffplay.exe']);
      }
    } catch (_) {}
  }

  DownloadTask? get currentTask => _currentTask;
  List<DownloadTask> get queue => _queue;
  int get currentIndex => _currentIndex;
  CustomPlayerState get playerState => _playerState;
  bool get isPlaying => (Platform.isAndroid || Platform.isIOS)
      ? (_mobilePlayer?.playing ?? false)
      : _playerState == CustomPlayerState.playing;
  bool get isPaused => (Platform.isAndroid || Platform.isIOS)
      ? (!(_mobilePlayer?.playing ?? false) && _currentTask != null)
      : _playerState == CustomPlayerState.paused;
  bool get isVisible => _isVisible && _currentTask != null;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  bool get isShuffle => _isShuffle;
  LoopMode get loopMode => _loopMode;
  bool get isLooping => _loopMode == LoopMode.one;

  void setQueue(List<DownloadTask> newQueue, {DownloadTask? initialTask}) {
    _queue = List.from(newQueue);
    if (initialTask != null) {
      _currentIndex = _queue.indexWhere((t) =>
          (initialTask.filePath != null && t.filePath == initialTask.filePath) ||
          t.id == initialTask.id ||
          t.video.id == initialTask.video.id);
      if (_currentIndex == -1) {
        _queue.insert(0, initialTask);
        _currentIndex = 0;
      }
    } else if (_queue.isNotEmpty) {
      _currentIndex = 0;
    } else {
      _currentIndex = -1;
    }
    notifyListeners();
  }

  Future<void> playTask(
    DownloadTask task, {
    List<DownloadTask>? queue,
    Duration? startPosition,
  }) async {
    if (task.filePath == null || !File(task.filePath!).existsSync()) {
      return;
    }

    if (queue != null && queue.isNotEmpty) {
      _queue = List.from(queue);
      _currentIndex = _queue.indexWhere((t) =>
          (task.filePath != null && t.filePath == task.filePath) ||
          t.id == task.id ||
          t.video.id == task.video.id);
      if (_currentIndex == -1) {
        _queue.insert(0, task);
        _currentIndex = 0;
      }
    } else if (_queue.isEmpty || !_queue.any((t) => (task.filePath != null && t.filePath == task.filePath) || t.id == task.id || t.video.id == task.video.id)) {
      _queue = [task];
      _currentIndex = 0;
    } else {
      _currentIndex = _queue.indexWhere((t) =>
          (task.filePath != null && t.filePath == task.filePath) ||
          t.id == task.id ||
          t.video.id == task.video.id);
    }

    _currentTask = task;
    _isVisible = true;
    _position = startPosition ?? Duration.zero;

    // Parse duration from video metadata as initial duration
    if (task.video.duration.isNotEmpty) {
      final parts = task.video.duration.split(':').map((e) => int.tryParse(e) ?? 0).toList();
      if (parts.length == 2) {
        _duration = Duration(minutes: parts[0], seconds: parts[1]);
      } else if (parts.length == 3) {
        _duration = Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
      }
    }

    notifyListeners();

    // Asynchronously load lyrics from pure YouTube / local cache
    _loadLyricsForTask(task);

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        if (Platform.isAndroid) {
          try {
            final notif = await Permission.notification.status;
            if (!notif.isGranted) {
              await Permission.notification.request();
            }
          } catch (_) {}
        }

        // Build artUri: prefer local cached file (offline/lock screen), fallback to network URL
        Uri? artUri;
        if (task.localArtPath != null && File(task.localArtPath!).existsSync()) {
          artUri = Uri.file(task.localArtPath!);
        } else if (task.video.thumbnail.isNotEmpty) {
          artUri = Uri.tryParse(task.video.thumbnail);
        }

        final mediaItem = MediaItem(
          id: task.id,
          album: 'YTDx Studio',
          title: task.video.title.isNotEmpty ? task.video.title : 'Bilinmeyen',
          artist: task.video.channel.isNotEmpty ? task.video.channel : 'YouTube',
          artUri: artUri,
          duration: _duration,
          playable: true,
        );

        // Play via audio_service handler — this creates real foreground service
        // visible on lock screen and notification shade on all Android devices
        if (_audioHandler != null) {
          await _audioHandler.playMediaItemFromFile(mediaItem, task.filePath!);
          await _audioHandler.setLoopModeAudio(
              _loopMode == LoopMode.one ? LoopMode.one : LoopMode.off);
          await _audioHandler.setVolumeAudio(_volume);
        }

        _completionHandled = false;
        _playerState = CustomPlayerState.playing;
        notifyListeners();
      } catch (e) {
        if (!e.toString().toLowerCase().contains('interrupted') && !e.toString().toLowerCase().contains('abort')) {
          AppLogger.error(_tag, 'Mobil oynatma hatası: $e');
        }
      }
    } else {
      _startNativePlayback(File(task.filePath!).absolute.path, _position);
    }
  }

  Future<void> _loadLyricsForTask(DownloadTask task) async {
    final currentTaskId = task.id;
    _currentLyrics = null;
    _activeLyricIndex = -1;
    _isLoadingLyrics = true;
    notifyListeners();

    try {
      final lyrics = await LyricsService.getLyrics(
        videoId: task.video.id,
        filePath: task.filePath,
        title: task.video.title,
        artist: task.video.channel,
      );

      if (_currentTask?.id == currentTaskId) {
        _currentLyrics = lyrics;
        _isLoadingLyrics = false;
        _activeLyricIndex = lyrics?.getActiveIndex(_position) ?? -1;
        notifyListeners();
      }
    } catch (e) {
      if (_currentTask?.id == currentTaskId) {
        _isLoadingLyrics = false;
        notifyListeners();
      }
    }
  }

  void refreshLyrics() {
    if (_currentTask != null) {
      _loadLyricsForTask(_currentTask!);
    }
  }

  List<int> _shuffledOrder = [];
  int _shuffledPointer = -1;

  void _rebuildShuffleOrder(int queueLength, {int currentIdx = -1}) {
    if (queueLength <= 0) {
      _shuffledOrder = [];
      _shuffledPointer = -1;
      return;
    }
    final indices = List.generate(queueLength, (i) => i);
    indices.shuffle(Random());
    if (currentIdx != -1) {
      indices.remove(currentIdx);
      indices.insert(0, currentIdx);
      _shuffledPointer = 0;
    } else {
      _shuffledPointer = 0;
    }
    _shuffledOrder = indices;
  }

  void playNext({bool autoAdvance = false}) {
    final validQueue = _queue.where((t) => t.filePath != null && File(t.filePath!).existsSync()).toList();
    if (validQueue.isEmpty) {
      if (autoAdvance) {
        _playerState = CustomPlayerState.stopped;
        _position = Duration.zero;
        notifyListeners();
      }
      return;
    }

    // Natural end of track with Single Track Loop (LoopMode.one)
    if (autoAdvance && _loopMode == LoopMode.one && _currentTask != null) {
      _replayCurrentTrack();
      return;
    }

    // If there is only 1 song in queue
    if (validQueue.length == 1) {
      if (_loopMode == LoopMode.all || _loopMode == LoopMode.one) {
        // Loop is active -> replay the song seamlessly
        _replayCurrentTrack();
      } else {
        if (autoAdvance) {
          _playerState = CustomPlayerState.stopped;
          _position = Duration.zero;
          notifyListeners();
        } else {
          _replayCurrentTrack();
        }
      }
      return;
    }

    int currentValidIdx = validQueue.indexWhere((t) =>
        (t.filePath != null && t.filePath == _currentTask?.filePath) ||
        t.id == _currentTask?.id ||
        t.video.id == _currentTask?.video.id);

    if (_isShuffle && validQueue.length > 1) {
      if (_shuffledOrder.length != validQueue.length || _shuffledPointer == -1) {
        _rebuildShuffleOrder(validQueue.length, currentIdx: currentValidIdx);
      }

      if (_shuffledPointer + 1 < _shuffledOrder.length) {
        _shuffledPointer++;
        final nextIdx = _shuffledOrder[_shuffledPointer];
        playTask(validQueue[nextIdx], queue: validQueue);
        return;
      } else if (_loopMode == LoopMode.all) {
        _rebuildShuffleOrder(validQueue.length);
        final nextIdx = _shuffledOrder.isNotEmpty ? _shuffledOrder[0] : 0;
        playTask(validQueue[nextIdx], queue: validQueue);
        return;
      } else {
        if (autoAdvance) {
          _playerState = CustomPlayerState.stopped;
          _position = Duration.zero;
          notifyListeners();
        } else {
          // Manual skip loops to first in shuffle
          _shuffledPointer = 0;
          final nextIdx = _shuffledOrder.isNotEmpty ? _shuffledOrder[0] : 0;
          playTask(validQueue[nextIdx], queue: validQueue);
        }
        return;
      }
    }

    // Sequential playback
    if (currentValidIdx != -1 && currentValidIdx + 1 < validQueue.length) {
      playTask(validQueue[currentValidIdx + 1], queue: validQueue);
    } else if (_loopMode == LoopMode.all && validQueue.isNotEmpty) {
      if (currentValidIdx == 0 && validQueue.length == 1) {
        _replayCurrentTrack();
      } else {
        playTask(validQueue[0], queue: validQueue);
      }
    } else {
      if (autoAdvance) {
        _playerState = CustomPlayerState.stopped;
        _position = Duration.zero;
        notifyListeners();
      } else if (validQueue.isNotEmpty) {
        playTask(validQueue[0], queue: validQueue);
      }
    }
  }

  void playPrevious() {
    if (_position.inSeconds > 3 && _currentTask != null) {
      seek(Duration.zero);
      return;
    }

    final validQueue = _queue.where((t) => t.filePath != null && File(t.filePath!).existsSync()).toList();
    if (validQueue.isEmpty) return;

    int currentValidIdx = validQueue.indexWhere((t) =>
        (t.filePath != null && t.filePath == _currentTask?.filePath) ||
        t.id == _currentTask?.id ||
        t.video.id == _currentTask?.video.id);

    if (_isShuffle && validQueue.length > 1 && _shuffledOrder.isNotEmpty) {
      if (_shuffledPointer > 0) {
        _shuffledPointer--;
        final prevIdx = _shuffledOrder[_shuffledPointer];
        playTask(validQueue[prevIdx], queue: validQueue);
        return;
      } else if (_loopMode == LoopMode.all) {
        _shuffledPointer = _shuffledOrder.length - 1;
        final prevIdx = _shuffledOrder[_shuffledPointer];
        playTask(validQueue[prevIdx], queue: validQueue);
        return;
      }
    }

    if (currentValidIdx > 0) {
      playTask(validQueue[currentValidIdx - 1], queue: validQueue);
    } else if (_loopMode == LoopMode.all && validQueue.isNotEmpty) {
      playTask(validQueue[validQueue.length - 1], queue: validQueue);
    } else if (_currentTask != null) {
      seek(Duration.zero);
    }
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_isShuffle && _queue.isNotEmpty) {
      final currentValidIdx = _queue.indexWhere((t) => t.filePath == _currentTask?.filePath);
      _rebuildShuffleOrder(_queue.length, currentIdx: currentValidIdx);
    }
    AppLogger.info(_tag, 'Karışık oynatma: $_isShuffle');
    notifyListeners();
  }

  void toggleLoopMode() {
    if (_loopMode == LoopMode.off) {
      _loopMode = LoopMode.all; // Tümünü tekrarla
    } else if (_loopMode == LoopMode.all) {
      _loopMode = LoopMode.one; // Tek şarkıyı tekrarla
    } else {
      _loopMode = LoopMode.off; // Kapalı
    }

    if (Platform.isAndroid || Platform.isIOS) {
      _audioHandler?.setLoopModeAudio(
        _loopMode == LoopMode.one ? LoopMode.one : LoopMode.off,
      );
    }

    AppLogger.info(_tag, 'Döngü Modu değiştirildi: $_loopMode');
    notifyListeners();
  }

  void toggleLoop() => toggleLoopMode();

  void _startNativePlayback(String filePath, Duration startPos) {
    _killNativeProcess();
    final sessionId = ++_currentPlaybackSessionId;

    _playerState = CustomPlayerState.playing;
    _position = startPos;
    notifyListeners();

    try {
      final startSec = startPos.inSeconds;
      final volInt = (_volume * 100).toInt().clamp(0, 100);

      // Start ffplay with stats output on stderr
      Process.start(
        'ffplay',
        [
          '-nodisp',
          '-autoexit',
          '-stats',
          if (startSec > 0) ...['-ss', '$startSec'],
          '-volume', '$volInt',
          filePath,
        ],
        mode: ProcessStartMode.normal,
      ).then((proc) {
        if (sessionId != _currentPlaybackSessionId) {
          try { proc.kill(ProcessSignal.sigkill); } catch (_) {}
          return;
        }

        _nativeProcess = proc;
        _startTicker(sessionId);

        // Parse continuous real-time playback position from ffplay stderr
        proc.stderr.transform(utf8.decoder).listen((chunk) {
          if (sessionId != _currentPlaybackSessionId) return;

          final match = RegExp(r'(\d+\.?\d*)\s+M-A:').firstMatch(chunk);
          if (match != null) {
            final secDouble = double.tryParse(match.group(1) ?? '');
            if (secDouble != null && secDouble > 0) {
              _position = Duration(milliseconds: (secDouble * 1000).toInt());
              if (_playerState != CustomPlayerState.playing) {
                _playerState = CustomPlayerState.playing;
              }
              notifyListeners();
            }
          }
        });

        proc.exitCode.then((code) {
          if (sessionId != _currentPlaybackSessionId) return;

          _posTicker?.cancel();
          if (_playerState == CustomPlayerState.playing) {
            _handleTrackCompleted();
          }
        });
      }).catchError((_) {
        if (sessionId != _currentPlaybackSessionId) return;
        // Fallback to mpv if ffplay is not found
        Process.start(
          'mpv',
          [
            '--no-video',
            '--really-quiet',
            if (startSec > 0) ...['--start=$startSec'],
            '--volume=$volInt',
            filePath,
          ],
        ).then((proc) {
          if (sessionId != _currentPlaybackSessionId) {
            try { proc.kill(ProcessSignal.sigkill); } catch (_) {}
            return;
          }
          _nativeProcess = proc;
          _startTicker(sessionId);
        }).catchError((_) {});
      });
    } catch (_) {}
  }

  void _startTicker(int sessionId) {
    _posTicker?.cancel();
    _posTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (sessionId != _currentPlaybackSessionId) return;

      if (_playerState == CustomPlayerState.playing) {
        _position += const Duration(seconds: 1);
        if (_duration > Duration.zero && _position >= _duration) {
          _handleTrackCompleted();
        }
        notifyListeners();
      }
    });
  }

  void _killNativeProcess() {
    _posTicker?.cancel();
    try {
      _nativeProcess?.kill(ProcessSignal.sigkill);
    } catch (_) {}
    _nativeProcess = null;
    cleanupAllAudioProcesses();
  }

  Future<void> togglePlayPause() async {
    if (Platform.isAndroid || Platform.isIOS) {
      if (_mobilePlayer != null && _currentTask != null) {
        if (_mobilePlayer!.playing) {
          _playerState = CustomPlayerState.paused;
          notifyListeners();
          await _mobilePlayer!.pause();
        } else {
          _playerState = CustomPlayerState.playing;
          notifyListeners();
          if (_mobilePlayer!.processingState == ProcessingState.idle) {
            await playTask(_currentTask!, startPosition: _position);
          } else {
            await _mobilePlayer!.play();
          }
        }
      } else if (_currentTask != null) {
        await playTask(_currentTask!);
      }
      return;
    }

    if (isPlaying) {
      // Pause process instantly via SIGSTOP
      if (_nativeProcess != null && (Platform.isLinux || Platform.isMacOS)) {
        try {
          _nativeProcess!.kill(ProcessSignal.sigstop);
          _posTicker?.cancel();
          _playerState = CustomPlayerState.paused;
          notifyListeners();
          return;
        } catch (_) {}
      }
      _killNativeProcess();
      _playerState = CustomPlayerState.paused;
      notifyListeners();
    } else if (isPaused) {
      // Resume process instantly via SIGCONT
      if (_nativeProcess != null && (Platform.isLinux || Platform.isMacOS)) {
        try {
          _nativeProcess!.kill(ProcessSignal.sigcont);
          _startTicker(_currentPlaybackSessionId);
          _playerState = CustomPlayerState.playing;
          notifyListeners();
          return;
        } catch (_) {}
      }
      if (_currentTask?.filePath != null) {
        _startNativePlayback(_currentTask!.filePath!, _position);
      }
    } else if (_currentTask != null) {
      await playTask(_currentTask!);
    }
  }

  Future<void> play() async {
    if (_playerState == CustomPlayerState.playing) return;
    _playerState = CustomPlayerState.playing;
    notifyListeners();
    if (Platform.isAndroid || Platform.isIOS) {
      await _mobilePlayer?.play();
    } else if (_currentTask?.filePath != null) {
      _startNativePlayback(_currentTask!.filePath!, _position);
    }
  }

  Future<void> pause() async {
    if (_playerState == CustomPlayerState.paused) return;
    _playerState = CustomPlayerState.paused;
    notifyListeners();
    if (Platform.isAndroid || Platform.isIOS) {
      await _mobilePlayer?.pause();
    } else {
      _killNativeProcess();
    }
  }

  Future<void> seek(Duration newPos) async {
    _position = newPos;
    notifyListeners();

    if (Platform.isAndroid || Platform.isIOS) {
      await _mobilePlayer?.seek(newPos);
      return;
    }

    if (_currentTask?.filePath != null && File(_currentTask!.filePath!).existsSync()) {
      _startNativePlayback(_currentTask!.filePath!, newPos);
    }
  }

  Future<void> setVolume(double vol) async {
    _volume = vol.clamp(0.0, 1.0);
    notifyListeners();

    if (Platform.isAndroid || Platform.isIOS) {
      await _mobilePlayer?.setVolume(_volume);
      return;
    }

    if (isPlaying && _currentTask?.filePath != null) {
      _startNativePlayback(_currentTask!.filePath!, _position);
    }
  }

  Future<void> stop() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await _mobilePlayer?.stop();
    }
    _killNativeProcess();
    _playerState = CustomPlayerState.stopped;
    _position = Duration.zero;
    notifyListeners();
  }

  Future<void> closePlayer() async {
    await stop();
    _isVisible = false;
    _currentTask = null;
    _queue = [];
    _currentIndex = -1;
    notifyListeners();
  }

  Future<void> testNotification() async {
    if (_audioHandler != null) {
      final testItem = MediaItem(
        id: 'test_notification_id',
        album: 'YTDx Studio Pro',
        title: '🔔 Bildirim & Kilit Ekranı Testi',
        artist: 'YTDx Medya Kontrolleri',
        duration: const Duration(minutes: 3, seconds: 45),
        playable: true,
      );
      _audioHandler.mediaItem.add(testItem);
      _audioHandler.playbackState.add(_audioHandler.playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.pause,
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
        processingState: AudioProcessingState.ready,
        playing: true,
        updatePosition: const Duration(seconds: 42),
        bufferedPosition: const Duration(minutes: 2),
        speed: 1.0,
      ));
      _playerState = CustomPlayerState.playing;
      notifyListeners();
    }
  }

  // ==========================================
  // 🌙 Akıllı Uyku Zamanlayıcısı (Sleep Timer)
  // ==========================================

  void startSleepTimer(Duration duration, {bool fadeOut = true}) {
    cancelSleepTimer();
    _sleepTimerTotalDuration = duration;
    _sleepTimerTarget = DateTime.now().add(duration);
    _sleepTimerRemaining = duration;
    _sleepTimerFadeOut = fadeOut;
    _sleepTimerEndOfTrack = false;

    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sleepTimerTarget == null) {
        timer.cancel();
        return;
      }

      final remaining = _sleepTimerTarget!.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _sleepTimerRemaining = Duration.zero;
        timer.cancel();
        _triggerSleepTimerStop();
      } else {
        _sleepTimerRemaining = remaining;

        // Son 15 saniyede akıllı yumuşak kapanış (Fade-out)
        if (_sleepTimerFadeOut && remaining.inSeconds <= 15) {
          final factor = (remaining.inMilliseconds / 15000.0).clamp(0.0, 1.0);
          final targetVol = (_volume * factor).clamp(0.0, _volume);
          if (Platform.isAndroid || Platform.isIOS) {
            _mobilePlayer?.setVolume(targetVol);
          }
        }

        notifyListeners();
      }
    });

    notifyListeners();
    AppLogger.info(_tag, '🌙 Uyku zamanlayıcısı başlatıldı: ${duration.inMinutes} dk (Fade-out: $fadeOut)');
  }

  void startSleepTimerEndOfTrack({bool fadeOut = true}) {
    cancelSleepTimer();
    _sleepTimerEndOfTrack = true;
    _sleepTimerFadeOut = fadeOut;
    _sleepTimerTotalDuration = null;
    _sleepTimerTarget = null;
    _sleepTimerRemaining = null;
    notifyListeners();
    AppLogger.info(_tag, '🌙 Uyku zamanlayıcısı başlatıldı: Parça Sonu (Fade-out: $fadeOut)');
  }

  void addSleepTimerMinutes(int minutes) {
    if (_sleepTimerTarget != null) {
      _sleepTimerTarget = _sleepTimerTarget!.add(Duration(minutes: minutes));
      _sleepTimerRemaining = _sleepTimerTarget!.difference(DateTime.now());
      _sleepTimerTotalDuration = (_sleepTimerTotalDuration ?? Duration.zero) + Duration(minutes: minutes);
      notifyListeners();
    } else {
      startSleepTimer(Duration(minutes: minutes), fadeOut: _sleepTimerFadeOut);
    }
  }

  void cancelSleepTimer() {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepTimerTarget = null;
    _sleepTimerRemaining = null;
    _sleepTimerTotalDuration = null;
    _sleepTimerEndOfTrack = false;

    // Ses seviyesini eski haline getir
    if (Platform.isAndroid || Platform.isIOS) {
      _mobilePlayer?.setVolume(_volume);
    }

    notifyListeners();
    AppLogger.info(_tag, '🌙 Uyku zamanlayıcısı iptal edildi.');
  }

  void _triggerSleepTimerStop() {
    AppLogger.info(_tag, '🌙 Uyku zamanlayıcısı süresi doldu, oynatıcı durduruluyor.');
    pause();
    cancelSleepTimer();
  }

  @override
  void dispose() {
    _sleepTicker?.cancel();
    _mobilePlayer?.dispose();
    _killNativeProcess();
    super.dispose();
  }
}
