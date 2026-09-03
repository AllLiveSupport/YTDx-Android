import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../theme/app_colors.dart';
import '../services/file_launcher.dart';
import '../main.dart' show isMobileDevice;
import 'now_playing_sheet.dart';

class PlayerBar extends StatefulWidget {
  const PlayerBar({super.key});

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
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

    if (!player.isVisible || player.currentTask == null) {
      return const SizedBox.shrink();
    }

    final task = player.currentTask!;
    final pos = player.position;
    final dur = player.duration;
    final totalSec = dur.inSeconds > 0 ? dur.inSeconds.toDouble() : 1.0;
    final displaySec = (_dragSec ?? pos.inSeconds.toDouble()).clamp(0.0, totalSec);
    final isMobile = isMobileDevice(context);

    if (isMobile) {
      // Modern interactive Mini-Player for mobile
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => NowPlayingSheet.show(context),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14161C) : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Interactive Seek / Progress bar
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3.5,
                    activeTrackColor: AppColors.primaryBlue,
                    inactiveTrackColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                    thumbColor: AppColors.primaryBlue,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5, pressedElevation: 4),
                    overlayColor: AppColors.primaryBlue.withValues(alpha: 0.2),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: SizedBox(
                    height: 12,
                    child: Slider(
                      value: displaySec,
                      min: 0.0,
                      max: totalSec,
                      onChanged: (val) => setState(() => _dragSec = val),
                      onChangeEnd: (val) {
                        player.seek(Duration(seconds: val.toInt()));
                        setState(() => _dragSec = null);
                      },
                    ),
                  ),
                ),

                // Controls and Info Row
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
                  child: Row(
                    children: [
                      // Album art
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildArt(task, 44),
                      ),
                      const SizedBox(width: 12),

                      // Title & Subtitle + Elapsed Time
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
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  '${_formatDuration(Duration(seconds: displaySec.toInt()))} / ${_formatDuration(dur)}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '• ${task.video.channel}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Action Buttons: Previous, Play/Pause, Next, Close
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded, size: 24),
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        tooltip: 'Önceki',
                        onPressed: player.playPrevious,
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryBlue,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryBlue.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 24,
                            color: Colors.white,
                          ),
                          onPressed: player.togglePlayPause,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, size: 24),
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        tooltip: 'Sonraki',
                        onPressed: () => player.playNext(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        tooltip: 'Kapat',
                        onPressed: player.closePlayer,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }


    // Desktop full player bar
    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14161C) : const Color(0xFFFFFFFF),
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // 1. Left Section: Track Info & Artwork
          Expanded(
            flex: 30,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: task.video.thumbnail.isNotEmpty
                        ? Image.network(
                            task.video.thumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: AppColors.primaryBlue.withValues(alpha: 0.2),
                              child: const Icon(Icons.music_note, color: AppColors.primaryBlue),
                            ),
                          )
                        : Container(
                            color: AppColors.primaryBlue.withValues(alpha: 0.2),
                            child: const Icon(Icons.music_note, color: AppColors.primaryBlue),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: (task.isAudio ? AppColors.greenMusic : AppColors.redVideo).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              task.format.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: task.isAudio ? AppColors.greenMusic : AppColors.redVideo,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              task.video.channel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Center Section: Playback Controls & Seek Bar
          Expanded(
            flex: 46,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Control Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Shuffle Button (Desktop)
                    IconButton(
                      icon: Icon(
                        Icons.shuffle_rounded,
                        size: 19,
                        color: player.isShuffle
                            ? AppColors.primaryBlue
                            : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                      ),
                      tooltip: 'Karışık Oynat (${player.isShuffle ? "Açık" : "Kapalı"})',
                      onPressed: player.toggleShuffle,
                    ),
                    const SizedBox(width: 4),

                    // Previous Track Button (Desktop)
                    IconButton(
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        size: 22,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                      tooltip: 'Önceki Şarkı',
                      onPressed: player.playPrevious,
                    ),
                    const SizedBox(width: 4),

                    // Play/Pause Big Button
                    InkWell(
                      onTap: player.togglePlayPause,
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryBlue,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryBlue.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Next Track Button (Desktop)
                    IconButton(
                      icon: Icon(
                        Icons.skip_next_rounded,
                        size: 22,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                      tooltip: 'Sonraki Şarkı',
                      onPressed: () => player.playNext(),
                    ),
                    const SizedBox(width: 4),

                    // Loop Mode Toggle (Desktop)
                    IconButton(
                      icon: Icon(
                        player.loopMode == LoopMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        size: 19,
                        color: player.loopMode != LoopMode.off
                            ? AppColors.primaryBlue
                            : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                      ),
                      tooltip: player.loopMode == LoopMode.one
                          ? 'Döngü: Tek Şarkı'
                          : (player.loopMode == LoopMode.all ? 'Döngü: Tüm Liste' : 'Döngü: Kapalı'),
                      onPressed: player.toggleLoopMode,
                    ),
                  ],
                ),

                // Seek Progress Bar + Timestamps
                Row(
                  children: [
                    Text(
                      _formatDuration(Duration(seconds: displaySec.toInt())),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                          activeTrackColor: AppColors.primaryBlue,
                          inactiveTrackColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          thumbColor: AppColors.primaryBlue,
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
                    ),
                    Text(
                      _formatDuration(dur),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3. Right Section: Volume & Quick External Actions
          Expanded(
            flex: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Volume Icon
                Icon(
                  player.volume == 0
                      ? Icons.volume_off_rounded
                      : (player.volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                  size: 18,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
                const SizedBox(width: 4),

                // Volume Slider
                SizedBox(
                  width: 80,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                      activeTrackColor: AppColors.primaryBlue,
                      inactiveTrackColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                      thumbColor: AppColors.primaryBlue,
                    ),
                    child: Slider(
                      value: player.volume,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (val) => player.setVolume(val),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Open Folder Button
                IconButton(
                  icon: Icon(
                    Icons.folder_open_rounded,
                    size: 18,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                  tooltip: 'Klasörde Aç',
                  onPressed: () {
                    if (task.filePath != null) {
                      FileLauncher.openFolder(task.filePath!);
                    } else {
                      FileLauncher.openFolder(task.outputPath);
                    }
                  },
                ),

                // Close Player Button
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                  tooltip: 'Oynatıcıyı Kapat',
                  onPressed: player.closePlayer,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
