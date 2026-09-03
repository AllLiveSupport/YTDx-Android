import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../theme/app_colors.dart';
import '../services/i18n.dart';
import '../services/haptic_service.dart';
import 'now_playing_sheet.dart';

class UnifiedBottomDock extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final int activeDownloadsCount;

  const UnifiedBottomDock({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.activeDownloadsCount,
  });

  @override
  State<UnifiedBottomDock> createState() => _UnifiedBottomDockState();
}

class _UnifiedBottomDockState extends State<UnifiedBottomDock> {
  double? _dragSec;

  String _formatDuration(Duration d) {
    if (d.inSeconds <= 0) return '00:00';
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildArt(dynamic task, double size) {
    if (task.localArtPath != null && File(task.localArtPath!).existsSync()) {
      return Image.file(
        File(task.localArtPath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFallbackArt(task, size),
      );
    } else if (task.video.thumbnail != null && task.video.thumbnail.isNotEmpty) {
      return Image.network(
        task.video.thumbnail,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFallbackArt(task, size),
      );
    }
    return _buildFallbackArt(task, size);
  }

  Widget _buildFallbackArt(dynamic task, double size) {
    final title = task.video.title as String;
    final initial = title.isNotEmpty ? title[0].toUpperCase() : '♪';
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.45,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasPlayer = player.isVisible && player.currentTask != null;

    final navItems = [
      _NavItemData(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: I18n.tr('nav_home')),
      _NavItemData(icon: Icons.search_outlined, selectedIcon: Icons.search_rounded, label: I18n.tr('nav_search')),
      _NavItemData(
        icon: Icons.download_outlined,
        selectedIcon: Icons.download_rounded,
        label: I18n.tr('nav_downloads'),
        badgeCount: widget.activeDownloadsCount > 0 ? widget.activeDownloadsCount : null,
      ),
      _NavItemData(icon: Icons.queue_music_outlined, selectedIcon: Icons.queue_music_rounded, label: I18n.tr('nav_playlists')),
      _NavItemData(icon: Icons.settings_outlined, selectedIcon: Icons.settings_rounded, label: I18n.tr('nav_settings')),
    ];

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xF212141A) : Colors.white.withValues(alpha: 0.92),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Integrated Mini Player (if playing)
                if (hasPlayer) ...[
                  _buildMiniPlayer(context, player, isDark),
                  Divider(
                    height: 1,
                    thickness: 0.8,
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
                  ),
                ],

                // 2. Navigation Bar Row
                Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(navItems.length, (index) {
                      final item = navItems[index];
                      final isSelected = widget.selectedIndex == index;

                      return Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticService.light();
                            widget.onItemSelected(index);
                          },
                          borderRadius: BorderRadius.circular(14),
                          splashColor: AppColors.primaryBlue.withValues(alpha: 0.12),
                          highlightColor: Colors.transparent,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primaryBlue.withValues(alpha: isDark ? 0.16 : 0.1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Icon with Badge
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    AnimatedScale(
                                      scale: isSelected ? 1.12 : 1.0,
                                      duration: const Duration(milliseconds: 180),
                                      child: Icon(
                                        isSelected ? item.selectedIcon : item.icon,
                                        size: 21,
                                        color: isSelected
                                            ? AppColors.primaryBlue
                                            : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                                      ),
                                    ),
                                    if (item.badgeCount != null && item.badgeCount! > 0)
                                      Positioned(
                                        top: -3,
                                        right: -7,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryBlue,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            item.badgeCount! > 9 ? '9+' : '${item.badgeCount}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              height: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                // Label
                                Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: isSelected ? 10 : 9,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected
                                        ? AppColors.primaryBlue
                                        : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniPlayer(BuildContext context, PlayerProvider player, bool isDark) {
    final task = player.currentTask!;
    final pos = player.position;
    final dur = player.duration;
    final totalSec = dur.inSeconds > 0 ? dur.inSeconds.toDouble() : 1.0;
    final displaySec = (_dragSec ?? pos.inSeconds.toDouble()).clamp(0.0, totalSec);
    final progressFraction = (displaySec / totalSec).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticService.light();
        NowPlayingSheet.show(context);
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -250) {
          // Swipe Left -> Next Track
          HapticService.medium();
          player.playNext(autoAdvance: false);
        } else if (velocity > 250) {
          // Swipe Right -> Previous Track
          HapticService.medium();
          player.playPrevious();
        }
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200) {
          // Swipe Up -> Expand Full Screen
          HapticService.light();
          NowPlayingSheet.show(context);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Interactive Mini Scrubber (Tap & Drag Seek)
          LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              void handleSeek(double localDx) {
                final fraction = (localDx / trackWidth).clamp(0.0, 1.0);
                final newSec = fraction * totalSec;
                setState(() => _dragSec = newSec);
                HapticService.selection();
                player.seek(Duration(seconds: newSec.toInt()));
              }

              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (details) => handleSeek(details.localPosition.dx),
                onHorizontalDragUpdate: (details) {
                  final fraction = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                  final newSec = fraction * totalSec;
                  setState(() => _dragSec = newSec);
                },
                onHorizontalDragEnd: (_) {
                  if (_dragSec != null) {
                    player.seek(Duration(seconds: _dragSec!.toInt()));
                    HapticService.light();
                    setState(() => _dragSec = null);
                  }
                },
                child: Container(
                  height: 12,
                  color: Colors.transparent,
                  alignment: Alignment.center,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                    child: Stack(
                      children: [
                        FractionallySizedBox(
                          widthFactor: progressFraction,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppColors.primaryBlue, AppColors.purpleAccent],
                              ),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // Mini Player Controls Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                // Album Art
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildArt(task, 38),
                ),
                const SizedBox(width: 10),

                // Title & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        task.video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 1.5),
                      Row(
                        children: [
                          Text(
                            _formatDuration(Duration(seconds: displaySec.toInt())),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          Text(
                            ' / ${_formatDuration(dur)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '• ${task.video.channel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Previous Button
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  onPressed: () {
                    HapticService.light();
                    player.playPrevious();
                  },
                ),

                // Play / Pause Circular Button
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryBlue,
                  ),
                  child: IconButton(
                    icon: Icon(
                      player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      HapticService.medium();
                      player.togglePlayPause();
                    },
                  ),
                ),

                // Next Button
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  onPressed: () {
                    HapticService.light();
                    player.playNext(autoAdvance: false);
                  },
                ),

                // Close Button
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  tooltip: 'Kapat',
                  onPressed: () {
                    HapticService.light();
                    player.closePlayer();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int? badgeCount;

  _NavItemData({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount,
  });
}
