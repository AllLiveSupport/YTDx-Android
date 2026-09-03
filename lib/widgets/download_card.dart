import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/download_task.dart';
import '../providers/app_state.dart';
import '../theme/app_colors.dart';
import '../services/i18n.dart';
import '../screens/debug_logs_screen.dart';

class DownloadCard extends StatelessWidget {
  final DownloadTask task;

  const DownloadCard({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final percentText = task.status == DownloadStatus.queued
        ? I18n.tr('downloads_queued')
        : '${(task.progress * 100).toInt()}%';

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
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
            Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 100,
                    height: 58,
                    child: task.video.thumbnail.isNotEmpty
                        ? Image.network(
                            task.video.thumbnail,
                            fit: BoxFit.cover,
                            cacheWidth: 200,
                            errorBuilder: (_, _, _) => Container(
                              color: isDark ? const Color(0xFF1E2026) : const Color(0xFFE2E8F0),
                              child: const Icon(Icons.download, color: Colors.grey),
                            ),
                          )
                        : Container(
                            color: isDark ? const Color(0xFF1E2026) : const Color(0xFFE2E8F0),
                            child: const Icon(Icons.download, color: Colors.grey),
                          ),
                  ),
                ),
                const SizedBox(width: 14),

                // Title & Channel
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            task.video.channel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: (task.isAudio ? AppColors.greenMusic : AppColors.redVideo).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${task.format.toUpperCase()} ${task.quality.toUpperCase()}',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: task.isAudio ? AppColors.greenMusic : AppColors.redVideo,
                              ),
                            ),
                          ),
                          // Engine badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.cyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              task.engineUsed,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Colors.cyanAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Control Buttons (Cancel / Status Icon)
                if (task.status == DownloadStatus.queued) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Icon(Icons.hourglass_top_rounded, size: 14, color: Colors.amber),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => appState.cancelTask(task),
                        tooltip: I18n.tr('downloads_tooltip_dequeue'),
                      ),
                    ],
                  ),
                ] else if (task.isRunning) ...[
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: Colors.redAccent),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => appState.cancelTask(task),
                    tooltip: I18n.tr('downloads_tooltip_cancel'),
                  ),
                ] else if (task.status == DownloadStatus.completed) ...[
                  const Icon(Icons.check_circle_rounded, color: AppColors.greenMusic, size: 20),
                ] else if (task.status == DownloadStatus.failed) ...[
                  IconButton(
                    icon: const Icon(Icons.error_outline_rounded, color: AppColors.redVideo, size: 20),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => appState.cancelTask(task),
                    tooltip: I18n.tr('downloads_tooltip_remove'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Progress Bar & Percentage
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: task.status == DownloadStatus.queued
                          ? null
                          : (task.progress > 0 ? task.progress : null),
                      minHeight: 5,
                      backgroundColor: isDark ? const Color(0xFF282B33) : const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        task.status == DownloadStatus.queued
                            ? Colors.amber
                            : (task.isAudio ? AppColors.greenMusic : AppColors.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  percentText,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Size, Speed, ETA Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${I18n.tr('downloads_size')} ${task.sizeInfo}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
                Text(
                  task.status == DownloadStatus.queued
                      ? I18n.tr('downloads_waiting')
                      : '${I18n.tr('downloads_speed')} ${task.speed}  •  ${I18n.tr('downloads_eta_full')} ${task.eta}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),

            // Error info banner with direct link to Debug Logs
            if (task.status == DownloadStatus.failed) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: isDark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'İndirme Hatası:',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const DebugLogsScreen()),
                            );
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: const [
                                Icon(Icons.bug_report_outlined, size: 13, color: Colors.redAccent),
                                SizedBox(width: 3),
                                Text(
                                  'Detaylı Loglar →',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.redAccent,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (task.errorMessage != null && task.errorMessage!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      SelectableText(
                        task.errorMessage!,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                        ),
                      ),
                      if (task.errorMessage!.contains('Google Hesabı')) ...[
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.vpn_key_rounded, size: 14),
                          label: Text(I18n.tr('download_google_auth_btn'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => appState.setTabIndex(4),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

