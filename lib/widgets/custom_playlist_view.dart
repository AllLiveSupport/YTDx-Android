import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/custom_playlist.dart';
import '../models/local_track.dart';
import '../providers/player_provider.dart';
import '../services/playlist_manager.dart';
import '../services/local_audio_scanner.dart';
import '../services/haptic_service.dart';
import '../theme/app_colors.dart';
import '../main.dart' show isMobileDevice;

class CustomPlaylistView extends StatefulWidget {
  const CustomPlaylistView({super.key});

  @override
  State<CustomPlaylistView> createState() => _CustomPlaylistViewState();
}

class _CustomPlaylistViewState extends State<CustomPlaylistView> {
  CustomPlaylist? _selectedPlaylist;
  List<LocalTrack> _resolvedTracks = [];
  bool _isLoadingTracks = false;

  final List<int> _colorPalette = [
    0xFF3B82F6, // Blue
    0xFFEF4444, // Red
    0xFF8B5CF6, // Purple
    0xFF10B981, // Green
    0xFFF59E0B, // Amber
    0xFF06B6D4, // Cyan
    0xFFEC4899, // Pink
  ];

  final List<Map<String, dynamic>> _iconList = [
    {'name': 'music_note', 'icon': Icons.music_note_rounded},
    {'name': 'favorite', 'icon': Icons.favorite_rounded},
    {'name': 'directions_car', 'icon': Icons.directions_car_rounded},
    {'name': 'fitness_center', 'icon': Icons.fitness_center_rounded},
    {'name': 'whatshot', 'icon': Icons.whatshot_rounded},
    {'name': 'star', 'icon': Icons.star_rounded},
    {'name': 'headset', 'icon': Icons.headset_rounded},
    {'name': 'nightlife', 'icon': Icons.nightlife_rounded},
  ];

  IconData _getIconData(String name) {
    final match = _iconList.firstWhere(
      (e) => e['name'] == name,
      orElse: () => {'icon': Icons.queue_music_rounded},
    );
    return match['icon'] as IconData;
  }

  Future<void> _loadTracksForPlaylist(CustomPlaylist playlist) async {
    setState(() {
      _isLoadingTracks = true;
      _resolvedTracks = [];
    });

    final list = <LocalTrack>[];
    for (final path in playlist.trackPaths) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          final track = await LocalAudioScanner.createTrackFromFile(file);
          list.add(track);
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        _resolvedTracks = list;
        _isLoadingTracks = false;
      });
    }
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    HapticService.light();
    final titleController = TextEditingController();
    final descController = TextEditingController();
    int selectedColor = _colorPalette[0];
    String selectedIcon = 'music_note';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Color(selectedColor).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_getIconData(selectedIcon), color: Color(selectedColor), size: 22),
                ),
                const SizedBox(width: 12),
                const Text('Yeni Çalma Listesi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Liste Adı (Örn: Spor, Araba)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Açıklama (İsteğe bağlı)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Renk Seçin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _colorPalette.map((c) {
                      final isSel = selectedColor == c;
                      return GestureDetector(
                        onTap: () {
                          HapticService.selection();
                          setDialogState(() => selectedColor = c);
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: isSel ? Border.all(color: Colors.white, width: 3) : null,
                            boxShadow: isSel
                                ? [BoxShadow(color: Color(c).withValues(alpha: 0.5), blurRadius: 8)]
                                : null,
                          ),
                          child: isSel ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('İkon Seçin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _iconList.map((item) {
                      final isSel = selectedIcon == item['name'];
                      return GestureDetector(
                        onTap: () {
                          HapticService.selection();
                          setDialogState(() => selectedIcon = item['name'] as String);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSel ? Color(selectedColor).withValues(alpha: 0.25) : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(10),
                            border: isSel ? Border.all(color: Color(selectedColor), width: 1.5) : null,
                          ),
                          child: Icon(item['icon'] as IconData, size: 20, color: isSel ? Color(selectedColor) : (isDark ? Colors.white70 : Colors.black54)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('İptal'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Color(selectedColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final title = titleController.text.trim();
                  if (title.isNotEmpty) {
                    HapticService.medium();
                    await PlaylistManager.instance.createPlaylist(
                      title: title,
                      description: descController.text.trim(),
                      iconName: selectedIcon,
                      colorValue: selectedColor,
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  }
                },
                child: const Text('Oluştur'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _playPlaylist(PlayerProvider player, {bool shuffle = false}) {
    if (_resolvedTracks.isEmpty) return;
    HapticService.medium();
    final queue = _resolvedTracks.map((t) => t.toDownloadTask()).toList();
    if (shuffle) {
      final randTrack = _resolvedTracks[DateTime.now().millisecond % _resolvedTracks.length];
      player.playTask(randTrack.toDownloadTask(), queue: queue);
    } else {
      player.playTask(_resolvedTracks.first.toDownloadTask(), queue: queue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistManager = context.watch<PlaylistManager>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = isMobileDevice(context);

    if (_selectedPlaylist != null) {
      return _buildPlaylistDetailView(context, playlistManager, isDark, isMobile);
    }

    final playlists = playlistManager.playlists;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 36,
        isMobile ? 10 : 20,
        isMobile ? 14 : 36,
        isMobile ? 120 : 36,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Create Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Özel Çalma Listeleri',
                    style: TextStyle(
                      fontSize: isMobile ? 18 : 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${playlists.length} çalma listesi',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Yeni Liste', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _showCreatePlaylistDialog(context),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Playlists Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isMobile ? 2 : 4,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: isMobile ? 0.95 : 1.1,
            ),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final pl = playlists[index];
              final isFav = pl.isFavorites;
              final plColor = Color(pl.colorValue);

              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  HapticService.light();
                  setState(() => _selectedPlaylist = pl);
                  _loadTracksForPlaylist(pl);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : AppColors.lightCard,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isFav
                          ? Colors.redAccent.withValues(alpha: 0.4)
                          : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      width: isFav ? 1.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: plColor.withValues(alpha: isDark ? 0.15 : 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Row: Icon badge + options
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [plColor, plColor.withValues(alpha: 0.7)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: plColor.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(_getIconData(pl.iconName), color: Colors.white, size: 24),
                          ),
                          if (!isFav)
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded, size: 18, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              color: isDark ? AppColors.darkCard : AppColors.lightCard,
                              onSelected: (val) {
                                if (val == 'delete') {
                                  HapticService.heavy();
                                  PlaylistManager.instance.deletePlaylist(pl.id);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                                      SizedBox(width: 8),
                                      Text('Listeyi Sil', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),

                      // Title & Track Count
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pl.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${pl.trackPaths.length} şarkı',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistDetailView(
    BuildContext context,
    PlaylistManager playlistManager,
    bool isDark,
    bool isMobile,
  ) {
    final pl = _selectedPlaylist!;
    final player = context.watch<PlayerProvider>();
    final plColor = Color(pl.colorValue);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 36,
        isMobile ? 10 : 20,
        isMobile ? 14 : 36,
        isMobile ? 120 : 36,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back Button + Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                onPressed: () {
                  HapticService.light();
                  setState(() => _selectedPlaylist = null);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pl.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isMobile ? 19 : 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    if (pl.description != null && pl.description!.isNotEmpty)
                      Text(
                        pl.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Hero Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [plColor.withValues(alpha: 0.25), plColor.withValues(alpha: 0.08)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: plColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: plColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: plColor.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Icon(_getIconData(pl.iconName), color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pl.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_resolvedTracks.length} şarkı mevcut',
                        style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Play All & Shuffle Actions
          if (_resolvedTracks.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(
                      'Tümünü Çal (${_resolvedTracks.length})',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: plColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _playPlaylist(player, shuffle: false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    label: const Text(
                      'Karışık Çal',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: plColor,
                      side: BorderSide(color: plColor.withValues(alpha: 0.5), width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _playPlaylist(player, shuffle: true),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 16),

          // Track List
          if (_isLoadingTracks)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(color: AppColors.primaryBlue),
              ),
            )
          else if (_resolvedTracks.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Icon(Icons.queue_music_rounded, size: 48, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                    const SizedBox(height: 12),
                    Text(
                      'Bu listede henüz şarkı yok.',
                      style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Yerel müzikler veya indirmelerden şarkı ekleyebilirsiniz.',
                      style: TextStyle(color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _resolvedTracks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final track = _resolvedTracks[index];
                final isPlayingThis = player.currentTask?.filePath == track.filePath && player.isPlaying;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isPlayingThis
                        ? AppColors.primaryBlue.withValues(alpha: isDark ? 0.14 : 0.08)
                        : (isDark ? AppColors.darkCard : AppColors.lightCard),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isPlayingThis
                          ? AppColors.primaryBlue.withValues(alpha: 0.4)
                          : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Album Art
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: track.pictureBytes != null
                            ? Image.memory(track.pictureBytes!, width: 42, height: 42, fit: BoxFit.cover)
                            : Container(
                                width: 42,
                                height: 42,
                                color: plColor.withValues(alpha: 0.2),
                                child: Icon(Icons.music_note_rounded, color: plColor, size: 20),
                              ),
                      ),
                      const SizedBox(width: 10),

                      // Track Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isPlayingThis ? AppColors.primaryBlue : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                            ),
                          ],
                        ),
                      ),

                      // Play/Pause Action
                      IconButton(
                        icon: Icon(
                          isPlayingThis ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                          size: 30,
                          color: isPlayingThis ? AppColors.primaryBlue : plColor,
                        ),
                        onPressed: () {
                          HapticService.light();
                          final queue = _resolvedTracks.map((t) => t.toDownloadTask()).toList();
                          if (isPlayingThis) {
                            player.togglePlayPause();
                          } else {
                            player.playTask(track.toDownloadTask(), queue: queue);
                          }
                        },
                      ),

                      // Remove from Playlist
                      IconButton(
                        icon: Icon(Icons.remove_circle_outline_rounded, size: 20, color: Colors.redAccent.withValues(alpha: 0.7)),
                        tooltip: 'Listeden Çıkar',
                        onPressed: () async {
                          HapticService.light();
                          await playlistManager.removeTrackFromPlaylist(pl.id, track.filePath);
                          setState(() {
                            _resolvedTracks.removeAt(index);
                          });
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
