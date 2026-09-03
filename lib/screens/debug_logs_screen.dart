import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../services/app_logger.dart';
import '../theme/app_colors.dart';

class DebugLogsScreen extends StatefulWidget {
  const DebugLogsScreen({super.key});

  @override
  State<DebugLogsScreen> createState() => _DebugLogsScreenState();
}

class _DebugLogsScreenState extends State<DebugLogsScreen> {
  final ScrollController _scrollController = ScrollController();
  LogLevel? _filterLevel;

  @override
  void initState() {
    super.initState();
    // Listen for new log entries and auto-scroll to bottom
    AppLogger.instance.addListener(_onNewLog);
  }

  void _onNewLog() {
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    AppLogger.instance.removeListener(_onNewLog);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allEntries = AppLogger.instance.entries;
    final entries = _filterLevel == null
        ? allEntries
        : allEntries.where((e) => e.level == _filterLevel).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0F14) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF13141A) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Debug Logları', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              '${entries.length} kayıt',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ],
        ),
        actions: [
          // Notification test button
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined, color: Colors.amberAccent),
            tooltip: 'Bildirim Testi',
            onPressed: () async {
              final status = await Permission.notification.request();
              AppLogger.info('NotificationTest', 'POST_NOTIFICATIONS İzin Durumu: ${status.name}');
              if (!context.mounted) return;
              final player = Provider.of<PlayerProvider>(context, listen: false);
              await player.testNotification();
              if (!context.mounted) return;
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                    title: const Row(
                      children: [
                        Icon(Icons.notifications_active_rounded, color: Colors.blueAccent),
                        SizedBox(width: 8),
                        Text('Bildirim Testi Başlatıldı', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• Bildirim İzni: ${status.isGranted ? "Verildi ✅" : "Verilmedi ❌"}'),
                        const SizedBox(height: 8),
                        const Text('• Üst bildirim panelinde ve kilit ekranında YTDx Studio müzik çalar kontrolü (Oynat/Durdur/İleri/Geri/X Kapat) görünmelidir.'),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Xiaomi / HyperOS / MIUI için İpucu:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber)),
                              SizedBox(height: 4),
                              Text('1. Ayarlar > Uygulamalar > YTDx Studio > Bildirimler bölümünden "Kilit ekranı bildirimleri" ve "Kalıcı bildirimler"i açın.\n2. Pil Tasarrufu ayarını "Kısıtlama Yok" yapın.', style: TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Tamam'),
                      ),
                    ],
                  ),
                );
            },
          ),
          // Filter buttons
          PopupMenuButton<LogLevel?>(
            icon: Icon(
              Icons.filter_list_rounded,
              color: _filterLevel != null ? AppColors.primary : null,
            ),
            tooltip: 'Filtrele',
            onSelected: (level) => setState(() => _filterLevel = level),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Tümü')),
              const PopupMenuItem(value: LogLevel.info, child: Text('ℹ Bilgi')),
              const PopupMenuItem(value: LogLevel.warning, child: Text('⚠ Uyarı')),
              const PopupMenuItem(value: LogLevel.error, child: Text('✗ Hata')),
              const PopupMenuItem(value: LogLevel.success, child: Text('✓ Başarı')),
            ],
          ),
          // Copy all
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Tümünü Kopyala',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: AppLogger.exportAll()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Loglar panoya kopyalandı'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          // Clear
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Temizle',
            onPressed: () {
              AppLogger.clear();
              setState(() {});
            },
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bug_report_outlined,
                    size: 56,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Henüz log yok.\nBir indirme başlatın.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _LogEntryTile(entry: entry, isDark: isDark);
              },
            ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;
  final bool isDark;

  const _LogEntryTile({required this.entry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: entry.levelColor.withValues(alpha: isDark ? 0.06 : 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: entry.levelColor.withValues(alpha: isDark ? 0.18 : 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Level icon
          Text(
            entry.levelIcon,
            style: TextStyle(fontSize: 13, color: entry.levelColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tag + Time row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: entry.levelColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        entry.tag,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: entry.levelColor,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      entry.timeStr,
                      style: TextStyle(
                        fontSize: 9,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // Message
                SelectableText(
                  entry.message,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? const Color(0xFFCDD6F4) : const Color(0xFF2D3748),
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
