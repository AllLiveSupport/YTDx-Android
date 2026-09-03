import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/download_task.dart';
import '../models/video_item.dart';
import '../providers/app_state.dart';
import '../theme/app_colors.dart';
import 'quality_modal.dart';

class VideoCard extends StatelessWidget {
  final VideoItem video;
  final bool showCheckbox;
  final Function(bool)? onCheckboxChanged;

  const VideoCard({
    super.key,
    required this.video,
    this.showCheckbox = false,
    this.onCheckboxChanged,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail Stack
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      video.thumbnail,
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                      errorBuilder: (_, _, _) => Container(
                        color: isDark ? const Color(0xFF1E2026) : const Color(0xFFE2E8F0),
                        child: const Icon(Icons.movie_creation_outlined, size: 36, color: Colors.grey),
                      ),
                    ),
                  ),
                ),

              // Duration Badge (Bottom Right)
              if (video.duration.isNotEmpty)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      video.duration,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // Selection Checkbox for Playlist
              if (showCheckbox)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Checkbox(
                      value: video.isSelected,
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        if (onCheckboxChanged != null) {
                          onCheckboxChanged!(val ?? false);
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),

          // Metadata & Action Buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),

                // Channel Name
                Row(
                  children: [
                    CircleAvatar(
                      radius: 8,
                      backgroundColor: AppColors.purpleAccent.withValues(alpha: 0.3),
                      child: Text(
                        video.channel.isNotEmpty ? video.channel[0].toUpperCase() : 'Y',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        video.channel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Action Buttons: Green Music (🎵) & Red Video (🎬)
                Row(
                  children: [
                    // Green Audio Download Button
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.music_note, size: 14, color: Colors.white),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            appState.settings.defaultAudioFormat.toUpperCase(),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.greenMusic,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          showQualityModal(
                            context,
                            video: video,
                            initialIsAudio: true,
                            onConfirm: (fmt, qlt) {
                              final isAud = DownloadTask.isAudioFormat(fmt);
                              appState.startDownload(
                                video: video,
                                isAudio: isAud,
                                format: fmt,
                                quality: qlt,
                                outputPath: appState.settings.downloadPath,
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Red Video Download Button
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.videocam, size: 14, color: Colors.white),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('MP4', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.redVideo,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          showQualityModal(
                            context,
                            video: video,
                            initialIsAudio: false,
                            onConfirm: (fmt, qlt) {
                              final isAud = DownloadTask.isAudioFormat(fmt);
                              appState.startDownload(
                                video: video,
                                isAudio: isAud,
                                format: fmt,
                                quality: qlt,
                                outputPath: appState.settings.downloadPath,
                              );
                            },
                          );
                        },
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
  );
}
}
