import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../theme/app_colors.dart';
import '../services/i18n.dart';
import '../services/playlist_manager.dart';
import '../services/haptic_service.dart';
import 'add_to_playlist_dialog.dart';
import 'sleep_timer_sheet.dart';

enum NowPlayingTab { player, lyrics, queue }

class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NowPlayingSheet(),
    );
  }

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet> {
  double? _dragSec;
  NowPlayingTab _currentTab = NowPlayingTab.player;
  final ScrollController _lyricsScrollController = ScrollController();
  bool _userIsScrolling = false;
  Timer? _userScrollDebounce;
  int _lastScrolledIndex = -1;

  @override
  void dispose() {
    _lyricsScrollController.dispose();
    _userScrollDebounce?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds <= 0) return '00:00';
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    final secs = d.inSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final task = player.currentTask;

    if (task == null) {
      return const SizedBox.shrink();
    }

    final pos = player.position;
    final dur = player.duration;
    final totalSec = dur.inSeconds > 0 ? dur.inSeconds.toDouble() : 1.0;
    final displaySec = (_dragSec ?? pos.inSeconds.toDouble()).clamp(0.0, totalSec);
    final isPlaying = player.isPlaying;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1117) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag Handle & Header
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 16, right: 16, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentTab == NowPlayingTab.lyrics
                            ? 'ŞARKI SÖZLERİ'
                            : (_currentTab == NowPlayingTab.queue
                                ? I18n.tr('queue_title').toUpperCase()
                                : I18n.tr('now_playing_title')),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Sleep Timer (🌙) Button / Active Capsule
                      if (player.isSleepTimerActive)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => SleepTimerSheet.show(context),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.nightlight_round, size: 13, color: AppColors.primaryBlue),
                                  const SizedBox(width: 5),
                                  Text(
                                    player.isSleepTimerEndOfTrack
                                        ? 'Parça Sonu'
                                        : _formatDuration(player.sleepTimerRemaining ?? Duration.zero),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryBlue,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        IconButton(
                          icon: Icon(
                            Icons.nightlight_round,
                            size: 21,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                          tooltip: 'Uyku Zamanlayıcısı',
                          onPressed: () => SleepTimerSheet.show(context),
                        ),
                      // Lyrics Button
                      IconButton(
                        icon: Icon(
                          Icons.lyrics_rounded,
                          size: 23,
                          color: _currentTab == NowPlayingTab.lyrics
                              ? AppColors.primaryBlue
                              : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                        ),
                        tooltip: 'Şarkı Sözleri',
                        onPressed: () {
                          HapticService.light();
                          setState(() {
                            _currentTab = _currentTab == NowPlayingTab.lyrics
                                ? NowPlayingTab.player
                                : NowPlayingTab.lyrics;
                          });
                        },
                      ),
                      // Queue Button
                      IconButton(
                        icon: Icon(
                          Icons.queue_music_rounded,
                          size: 24,
                          color: _currentTab == NowPlayingTab.queue
                              ? AppColors.primaryBlue
                              : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                        ),
                        tooltip: I18n.tr('queue_title'),
                        onPressed: () {
                          HapticService.light();
                          setState(() {
                            _currentTab = _currentTab == NowPlayingTab.queue
                                ? NowPlayingTab.player
                                : NowPlayingTab.queue;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Body: Either Player, Lyrics or Queue View
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _buildCurrentTabContent(context, player, task, isDark, displaySec, totalSec, isPlaying),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent(
    BuildContext context,
    PlayerProvider player,
    dynamic task,
    bool isDark,
    double displaySec,
    double totalSec,
    bool isPlaying,
  ) {
    switch (_currentTab) {
      case NowPlayingTab.lyrics:
        return _buildLyricsView(context, player, task, isDark);
      case NowPlayingTab.queue:
        return _buildQueueView(player, isDark);
      case NowPlayingTab.player:
        return _buildPlayerView(context, player, task, isDark, displaySec, totalSec, isPlaying);
    }
  }

  Widget _buildPlayerView(
    BuildContext context,
    PlayerProvider player,
    dynamic task,
    bool isDark,
    double displaySec,
    double totalSec,
    bool isPlaying,
  ) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
      child: Column(
        children: [
          const SizedBox(height: 10),

          // 1. Large Cover Art with Glow & Lyrics Tap
          Center(
            child: GestureDetector(
              onTap: () {
                HapticService.light();
                setState(() => _currentTab = NowPlayingTab.lyrics);
              },
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: isPlaying ? 0.35 : 0.15),
                      blurRadius: isPlaying ? 28 : 14,
                      offset: const Offset(0, 10),
                      spreadRadius: isPlaying ? 2 : 0,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: _buildCoverArt(task, isDark),
                      ),
                    ),
                    // Floating "Sözler" button badge on bottom-right corner
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lyrics_rounded, size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'Sözler',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // 2. Title & Artist
          Column(
            children: [
              Text(
                task.video.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                task.video.channel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 12),
              // Action Chips (Favorite, Format Badge, Add to Playlist)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Favorite Heart Toggle
                  if (task.filePath != null && task.filePath!.isNotEmpty)
                    Consumer<PlaylistManager>(
                      builder: (context, playlistMgr, _) {
                        final isFav = playlistMgr.isFavorite(task.filePath);
                        return IconButton(
                          icon: Icon(
                            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: isFav ? Colors.redAccent : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                            size: 24,
                          ),
                          tooltip: isFav ? 'Favorilerden Çıkar' : 'Favorilere Ekle',
                          onPressed: () {
                            HapticService.light();
                            playlistMgr.toggleFavorite(task.filePath);
                          },
                        );
                      },
                    ),

                  const SizedBox(width: 8),

                  // Format Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      task.format.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Add to Playlist Button
                  if (task.filePath != null && task.filePath!.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        Icons.playlist_add_rounded,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        size: 26,
                      ),
                      tooltip: 'Çalma Listesine Ekle',
                      onPressed: () {
                        HapticService.light();
                        AddToPlaylistDialog.show(context, task.filePath!, trackTitle: task.video.title);
                      },
                    ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 3. Interactive Seek Bar with Scrubbing
          Column(
            children: [
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4.5,
                  activeTrackColor: AppColors.primaryBlue,
                  inactiveTrackColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
                  thumbColor: AppColors.primaryBlue,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7, pressedElevation: 6),
                  overlayColor: AppColors.primaryBlue.withValues(alpha: 0.2),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                ),
                child: Slider(
                  value: displaySec,
                  min: 0.0,
                  max: totalSec,
                  onChanged: (val) {
                    setState(() => _dragSec = val);
                  },
                  onChangeEnd: (val) {
                    player.seek(Duration(seconds: val.toInt()));
                    setState(() => _dragSec = null);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(Duration(seconds: displaySec.toInt())),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                    Text(
                      _formatDuration(player.duration),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 4. Main Player Controls (Shuffle, Prev, Play/Pause, Next, Repeat)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Shuffle
              IconButton(
                icon: Icon(
                  Icons.shuffle_rounded,
                  size: 24,
                  color: player.isShuffle
                      ? AppColors.primaryBlue
                      : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                ),
                tooltip: 'Karışık Çal',
                onPressed: () => _handleToggleShuffle(context, player),
              ),

              // Previous
              IconButton(
                icon: Icon(
                  Icons.skip_previous_rounded,
                  size: 38,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
                tooltip: 'Önceki Şarkı',
                onPressed: player.playPrevious,
              ),

              // Large Play/Pause Button
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryBlue, Color(0xFF6366F1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 36,
                    color: Colors.white,
                  ),
                  onPressed: player.togglePlayPause,
                ),
              ),

              // Next
              IconButton(
                icon: Icon(
                  Icons.skip_next_rounded,
                  size: 38,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
                tooltip: 'Sonraki Şarkı',
                onPressed: () => player.playNext(),
              ),

              // Loop / Repeat
              IconButton(
                icon: Icon(
                  player.loopMode == LoopMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  size: 24,
                  color: player.loopMode != LoopMode.off
                      ? AppColors.primaryBlue
                      : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                ),
                tooltip: player.loopMode == LoopMode.one
                    ? I18n.tr('loop_one')
                    : (player.loopMode == LoopMode.all ? I18n.tr('loop_all') : I18n.tr('loop_off')),
                onPressed: () => _handleToggleLoop(context, player),
              ),
            ],
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

Widget _buildLyricsView(
    BuildContext context,
    PlayerProvider player,
    dynamic task,
    bool isDark,
  ) {
    final lyrics = player.currentLyrics;
    final activeIndex = player.activeLyricIndex;

    // Auto-scroll to active line if user is not manually scrolling
    if (!_userIsScrolling &&
        activeIndex >= 0 &&
        activeIndex != _lastScrolledIndex &&
        _lyricsScrollController.hasClients) {
      _lastScrolledIndex = activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_lyricsScrollController.hasClients && !_userIsScrolling) {
          // 76px per row: 56px min-height + 20px vertical margin
          final targetOffset = (activeIndex * 76.0) - 160.0;
          final clamped = targetOffset.clamp(
            0.0,
            _lyricsScrollController.position.maxScrollExtent,
          );
          _lyricsScrollController.animateTo(
            clamped,
            duration: const Duration(milliseconds: 750),
            curve: Curves.easeInOutCubic,
          );
        }
      });
    }

    return Stack(
      children: [
        // 1. Ambient Blurred Album Cover Art Background
        Positioned.fill(
          child: Opacity(
            opacity: isDark ? 0.22 : 0.12,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
              child: _buildCoverArt(task, isDark),
            ),
          ),
        ),

        // Deep Gradient Shade for Maximum Contrast and Legibility
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  (isDark ? const Color(0xFF0F1117) : Colors.white).withValues(alpha: 0.78),
                  (isDark ? const Color(0xFF0F1117) : Colors.white).withValues(alpha: 0.96),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),

        // 2. Content: Loading, Empty, or Synced Lyrics List
        if (player.isLoadingLyrics)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryBlue.withValues(alpha: 0.15),
                  ),
                  child: const CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Şarkı Sözleri Yükleniyor...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'YouTube altyazıları taranıyor',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          )
        else if (lyrics == null || lyrics.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryBlue.withValues(alpha: 0.12),
                    ),
                    child: const Icon(Icons.lyrics_rounded, size: 36, color: AppColors.primaryBlue),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Şarkı Sözü Bulunamadı',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bu parçanın YouTube videosunda altyazı veya açıklama sözleri yer almıyor.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Tekrar Dene'),
                    onPressed: () => player.refreshLyrics(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            children: [
              // Lyrics Source Badge
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      lyrics.isSynced ? Icons.auto_awesome_rounded : Icons.description_rounded,
                      size: 13,
                      color: AppColors.primaryBlue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      lyrics.source,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryBlue,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Flowing Synced Lyrics List
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is UserScrollNotification &&
                        notification.direction != ScrollDirection.idle) {
                      _userIsScrolling = true;
                      _userScrollDebounce?.cancel();
                      _userScrollDebounce = Timer(const Duration(milliseconds: 3500), () {
                        if (mounted) {
                          setState(() => _userIsScrolling = false);
                        }
                      });
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _lyricsScrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(top: 16, bottom: 125, left: 24, right: 24),
                    itemCount: lyrics.lines.length,
                    itemBuilder: (context, index) {
                      final line = lyrics.lines[index];
                      final isActive = (index == activeIndex);
                      final isPast = (activeIndex >= 0 && index < activeIndex);

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticService.light();
                          player.seek(line.time);
                        },
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: isActive ? 0.0 : 1.0, end: isActive ? 1.0 : 0.0),
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeInOutCubic,
                          builder: (context, activeT, _) {
                            // fontSize: inactive=18, active=23 — smooth interpolation
                            final fontSize = 18.0 + (activeT * 5.0);
                            // opacity: past=0.28, upcoming=0.50, active=1.0
                            final opacity = isPast
                                ? (0.28 + activeT * 0.72)
                                : (0.50 + activeT * 0.50);
                            // Vertical scale: subtly expands active line
                            final scaleY = 1.0 + (activeT * 0.04);

                            return Transform.scale(
                              scaleY: scaleY,
                              alignment: Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 56),
                                margin: const EdgeInsets.symmetric(vertical: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: AppColors.primaryBlue.withValues(alpha: 0.16 * activeT),
                                ),
                                child: Text(
                                  line.text,
                                  textAlign: TextAlign.left,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    fontWeight: activeT > 0.5 ? FontWeight.w800 : FontWeight.w600,
                                    height: 1.35,
                                    letterSpacing: -0.3 * activeT,
                                    color: (isDark ? Colors.white : const Color(0xFF0F172A))
                                        .withValues(alpha: opacity),
                                    shadows: isDark && activeT > 0.3
                                        ? [
                                            Shadow(
                                              color: AppColors.primaryBlue.withValues(alpha: 0.85 * activeT),
                                              blurRadius: 20,
                                            ),
                                            Shadow(
                                              color: Colors.white.withValues(alpha: 0.6 * activeT),
                                              blurRadius: 4,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),

        // 3. Floating Bottom Mini-Player Pill (Glassmorphic)
        Positioned(
          left: 18,
          right: 18,
          bottom: 12,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (isDark ? const Color(0xFF1E293B) : Colors.white).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 42,
                        height: 42,
                        child: _buildCoverArt(task, isDark),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.video.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_formatDuration(player.position)} / ${_formatDuration(player.duration)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, size: 26),
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      onPressed: player.playPrevious,
                    ),
                    IconButton(
                      icon: Icon(
                        player.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                        size: 38,
                      ),
                      color: AppColors.primaryBlue,
                      onPressed: player.togglePlayPause,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 26),
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      onPressed: () => player.playNext(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleToggleLoop(BuildContext context, PlayerProvider player) {
    HapticService.light();
    player.toggleLoopMode();
    String message;
    IconData icon;
    switch (player.loopMode) {
      case LoopMode.all:
        message = I18n.tr('loop_all');
        icon = Icons.repeat_rounded;
        break;
      case LoopMode.one:
        message = I18n.tr('loop_one');
        icon = Icons.repeat_one_rounded;
        break;
      case LoopMode.off:
        message = I18n.tr('loop_off');
        icon = Icons.repeat_rounded;
        break;
    }
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(message, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white)),
          ],
        ),
        duration: const Duration(milliseconds: 1100),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
      ),
    );
  }

  void _handleToggleShuffle(BuildContext context, PlayerProvider player) {
    HapticService.light();
    player.toggleShuffle();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shuffle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(player.isShuffle ? 'Karışık Çalma: Açık' : 'Karışık Çalma: Kapalı',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white)),
          ],
        ),
        duration: const Duration(milliseconds: 1100),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
      ),
    );
  }

  Widget _buildCoverArt(dynamic task, bool isDark) {
    if (task.localArtPath != null && File(task.localArtPath!).existsSync()) {
      return Image.file(
        File(task.localArtPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFallbackCover(task),
      );
    } else if (task.video.thumbnail != null && task.video.thumbnail.isNotEmpty) {
      return Image.network(
        task.video.thumbnail,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFallbackCover(task),
      );
    }
    return _buildFallbackCover(task);
  }

  Widget _buildFallbackCover(dynamic task) {
    final title = task.video.title as String;
    final initial = title.isNotEmpty ? title[0].toUpperCase() : '♪';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF4F46E5), Color(0xFF06B6D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              initial,
              style: const TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Icon(Icons.music_note_rounded, size: 28, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueView(PlayerProvider player, bool isDark) {
    final queue = player.queue;
    final currentTask = player.currentTask;

    if (queue.isEmpty) {
      return Center(
        child: Text(
          'Kuyrukta şarkı yok',
          style: TextStyle(color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: queue.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 60),
      itemBuilder: (context, index) {
        final item = queue[index];
        final isCurrent = item.id == currentTask?.id;

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isCurrent
                  ? AppColors.primaryBlue.withValues(alpha: 0.2)
                  : (isDark ? AppColors.darkCard : AppColors.lightCard),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildCoverArt(item, isDark),
            ),
          ),
          title: Text(
            item.video.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
              color: isCurrent
                  ? AppColors.primaryBlue
                  : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            ),
          ),
          subtitle: Text(
            item.video.channel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
          ),
          trailing: isCurrent
              ? const Icon(Icons.equalizer_rounded, color: AppColors.primaryBlue, size: 20)
              : null,
          onTap: () {
            player.playTask(item, queue: queue);
          },
        );
      },
    );
  }
}
