import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/download_task.dart';
import '../providers/app_state.dart';
import '../providers/player_provider.dart';
import '../theme/app_colors.dart';
import '../services/file_launcher.dart';
import '../services/haptic_service.dart';
import '../services/i18n.dart';

class HistoryCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onRemove;
  final bool isGrid;

  const HistoryCard({
    super.key,
    required this.task,
    required this.onRemove,
    this.isGrid = false,
  });

  String? _resolveFilePath() {
    if (task.filePath != null && File(task.filePath!).existsSync()) {
      return task.filePath;
    }
    try {
      final dir = Directory(task.outputPath);
      if (dir.existsSync()) {
        final cleanTitle = task.video.title
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
            .toLowerCase();
        for (var f in dir.listSync(recursive: true).whereType<File>()) {
          final name = f.uri.pathSegments.last.toLowerCase();
          if (name.contains(cleanTitle) || cleanTitle.contains(name.replaceAll(RegExp(r'\.[a-z0-9]+$'), ''))) {
            task.filePath = f.path;
            return f.path;
          }
        }
      }
    } catch (_) {}
    return task.filePath;
  }

  void _handlePlay(BuildContext context, PlayerProvider player) {
    HapticService.light();
    final path = _resolveFilePath();
    if (path != null && File(path).existsSync()) {
      task.filePath = path;
      if (task.isAudio) {
        final isThisTask = (player.currentTask?.id == task.id) ||
            (player.currentTask?.filePath != null && player.currentTask!.filePath == path);
        if (isThisTask) {
          player.togglePlayPause();
        } else {
          final audioQueue = context.read<AppState>().completedTasks.where((t) => t.isAudio).toList();
          player.playTask(task, queue: audioQueue);
        }
      } else {
        FileLauncher.openFile(path);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.tr('msg_file_not_found'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAudio = task.isAudio;
    final player = context.watch<PlayerProvider>();
    final path = _resolveFilePath();
    final isThisTask = (player.currentTask?.id == task.id) ||
        (path != null && player.currentTask?.filePath == path);
    final isThisPlaying = isThisTask && player.isPlaying;

    String? resolvedSize;
    if (path != null && File(path).existsSync()) {
      resolvedSize = '${(File(path).lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    if (!isGrid) {
      // 🌟 FULL-WIDTH LUXURY LIST TILE (Mobile Default)
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _handlePlay(context, player),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14171F) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isThisPlaying
                    ? AppColors.primaryBlue
                    : (isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.06)),
                width: isThisPlaying ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isThisPlaying
                      ? AppColors.primaryBlue.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: isThisPlaying ? 12 : 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // 1. Artwork with Format Badge
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: _buildThumbnail(),
                      ),
                    ),
                    Positioned(
                      bottom: 3,
                      right: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isAudio ? AppColors.greenMusic : AppColors.redVideo,
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          '${task.format.toUpperCase()} ${task.quality.toUpperCase()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 12),

                // 2. Info Block
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
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isThisPlaying
                              ? AppColors.primaryBlue
                              : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              task.video.channel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                              ),
                            ),
                          ),
                          if (resolvedSize != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              resolvedSize,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // 3. Action Buttons
                IconButton(
                  icon: Icon(
                    isThisPlaying
                        ? Icons.pause_circle_filled_rounded
                        : (isAudio ? Icons.play_circle_fill_rounded : Icons.play_arrow_rounded),
                    color: isThisPlaying
                        ? AppColors.primaryBlue
                        : (isDark ? Colors.white70 : AppColors.primaryBlue),
                    size: 32,
                  ),
                  onPressed: () => _handlePlay(context, player),
                ),

                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                  color: isDark ? const Color(0xFF1C1F28) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    HapticService.selection();
                    final path = _resolveFilePath();
                    if (val == 'open_file') {
                      if (path != null && File(path).existsSync()) {
                        FileLauncher.openFile(path);
                      }
                    } else if (val == 'open_folder') {
                      if (path != null && File(path).existsSync()) {
                        FileLauncher.openFolder(path);
                      } else if (task.outputPath.isNotEmpty) {
                        FileLauncher.openFolder(task.outputPath);
                      }
                    } else if (val == 'delete') {
                      onRemove();
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'open_file',
                      child: Row(
                        children: [
                          Icon(Icons.launch_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('Dış Uygulamada Aç', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'open_folder',
                      child: Row(
                        children: [
                          Icon(Icons.folder_open_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('Klasörde Göster', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                          const SizedBox(width: 10),
                          Text('Listeden Kaldır', style: TextStyle(fontSize: 13, color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 🌟 GRID CARD FORMAT (Desktop / Grid Mode)
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14171F) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isThisPlaying
                ? AppColors.primaryBlue
                : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
            width: isThisPlaying ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildThumbnail(),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isAudio ? AppColors.greenMusic : AppColors.redVideo).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${task.format.toUpperCase()} ${task.quality.toUpperCase()}',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
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
              task.video.channel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(isThisPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 16),
                    label: Text(isThisPlaying ? 'Durdur' : 'Oynat', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _handlePlay(context, player),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    if (task.localArtPath != null && File(task.localArtPath!).existsSync()) {
      return Image.file(
        File(task.localArtPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFallback(),
      );
    } else if (task.video.thumbnail.isNotEmpty) {
      return Image.network(
        task.video.thumbnail,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFallback(),
      );
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    return Container(
      color: const Color(0xFF1E293B),
      child: Center(
        child: Icon(
          task.isAudio ? Icons.music_note_rounded : Icons.movie_creation_rounded,
          color: Colors.white54,
          size: 28,
        ),
      ),
    );
  }
}
