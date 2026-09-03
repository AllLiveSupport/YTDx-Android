import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/download_task.dart';
import '../theme/app_colors.dart';
import '../widgets/download_card.dart';
import '../widgets/history_card.dart';
import '../services/file_launcher.dart';
import '../services/i18n.dart';
import '../services/haptic_service.dart';
import '../screens/debug_logs_screen.dart';
import '../screens/local_music_screen.dart';
import '../main.dart' show isMobileDevice;

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Debounce for bulk delete notifications — avoids SnackBar spam
  int _pendingDeleteCount = 0;
  Timer? _deleteDebounceTimer;
  late final TabController _tabController;

  void _onDeleteTask(AppState appState, DownloadTask task) {
    appState.deleteCompletedTask(task, deleteFromDisk: true);
    _pendingDeleteCount++;
    _deleteDebounceTimer?.cancel();
    _deleteDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final count = _pendingDeleteCount;
      _pendingDeleteCount = 0;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? I18n.tr('msg_file_deleted')
                : '$count müzik diskten silindi',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _deleteDebounceTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildDownloadsTab(BuildContext context, AppState appState, bool isDark, bool isMobile) {
    final activeTasks = appState.tasks.where((t) => t.status != DownloadStatus.completed).toList();
    final completedTasks = appState.completedTasks;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 36,
        isMobile ? 10 : 24,
        isMobile ? 14 : 36,
        isMobile ? 120 : 36,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header
          if (isMobile) ...[
            // Mobile compact header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        I18n.tr('downloads_title'),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.folder_outlined, size: 13, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              appState.settings.downloadPath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Action icon buttons on mobile
                IconButton(
                  icon: const Icon(Icons.bug_report_outlined),
                  color: Colors.cyanAccent,
                  tooltip: 'Debug Logları',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DebugLogsScreen()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open_rounded),
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  tooltip: I18n.tr('downloads_btn_open_folder'),
                  onPressed: () => FileLauncher.openFolder(appState.settings.downloadPath),
                ),
                if (activeTasks.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined),
                    color: Colors.orangeAccent,
                    tooltip: I18n.tr('downloads_btn_cancel_all'),
                    onPressed: () => appState.cancelAllTasks(),
                  ),
                if (completedTasks.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_all_rounded),
                    color: Colors.redAccent,
                    tooltip: I18n.tr('downloads_btn_clear'),
                    onPressed: () => appState.clearCompletedTasks(),
                  ),
              ],
            ),
          ] else ...[
            // Desktop wide header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      I18n.tr('downloads_title'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.folder_outlined, size: 14, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                        const SizedBox(width: 5),
                        Text(
                          '${I18n.tr('downloads_folder')} ${appState.settings.downloadPath}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.bug_report_outlined, size: 16),
                        label: Text(I18n.tr('downloads_debug_logs'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.cyanAccent,
                          side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DebugLogsScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        label: Text(I18n.tr('downloads_btn_open_folder'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF1E2128) : const Color(0xFFE2E8F0),
                          foregroundColor: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => FileLauncher.openFolder(appState.settings.downloadPath),
                      ),
                    if (activeTasks.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.stop_circle_outlined, size: 16),
                        label: Text(I18n.tr('downloads_btn_cancel_all'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orangeAccent,
                          side: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => appState.cancelAllTasks(),
                      ),
                    ],
                    if (completedTasks.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.clear_all_rounded, size: 16),
                        label: Text(I18n.tr('downloads_btn_clear'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => appState.clearCompletedTasks(),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],

          SizedBox(height: isMobile ? 16 : 24),

          // 1. ACTIVE DOWNLOADS SECTION
          if (activeTasks.isNotEmpty) ...[
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryBlue),
                ),
                const SizedBox(width: 8),
                Text(
                  '${I18n.tr('downloads_active')} (${activeTasks.length})',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activeTasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final task = activeTasks[index];
                return DownloadCard(task: task);
              },
            ),
            SizedBox(height: isMobile ? 18 : 28),
          ],

          // 2. COMPLETED DOWNLOADS HISTORY SECTION
          Text(
            '${I18n.tr('downloads_history')} (${completedTasks.length})',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 14),

          if (completedTasks.isEmpty && activeTasks.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Icon(
                      Icons.cloud_download_outlined,
                      size: 48,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      I18n.tr('downloads_empty_history'),
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (completedTasks.isNotEmpty)
            RepaintBoundary(
              child: isMobile
                  ? ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: completedTasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final task = completedTasks[index];
                        return HistoryCard(
                          task: task,
                          isGrid: false,
                          onRemove: () => _onDeleteTask(appState, task),
                        );
                      },
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: completedTasks.length,
                      itemBuilder: (context, index) {
                        final task = completedTasks[index];
                        return HistoryCard(
                          task: task,
                          isGrid: true,
                          onRemove: () => _onDeleteTask(appState, task),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = isMobileDevice(context);
    final activeCount = appState.tasks.where((t) => t.status != DownloadStatus.completed).length;

    return Column(
      children: [
        // Modern Floating Pill Tab Bar Header
        Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 16 : 36,
            isMobile ? 8 : 14,
            isMobile ? 16 : 36,
            4,
          ),
          child: Container(
            height: 42,
            padding: const EdgeInsets.all(3.5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14171F) : const Color(0xFFEFF2F8),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? AppColors.darkTextMuted : AppColors.lightTextSecondary,
              labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, fontFamily: 'Inter'),
              unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
              onTap: (_) => HapticService.light(),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_download_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text(I18n.tr('ytdx_downloads_tab')),
                      if (activeCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$activeCount',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.library_music_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text(I18n.tr('local_music_tab')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const BouncingScrollPhysics(),
            children: [
              _buildDownloadsTab(context, appState, isDark, isMobile),
              const LocalMusicScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
