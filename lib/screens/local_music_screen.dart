import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../providers/player_provider.dart';
import '../models/local_track.dart';
import '../services/local_audio_scanner.dart';
import '../services/native_folder_picker.dart';
import '../services/file_launcher.dart';
import '../theme/app_colors.dart';
import '../widgets/now_playing_sheet.dart';
import '../widgets/add_to_playlist_dialog.dart';
import '../services/playlist_manager.dart';
import '../services/haptic_service.dart';
import '../services/i18n.dart';
import '../main.dart' show isMobileDevice;

enum TrackSortOption { nameAsc, dateDesc, durationDesc }

class LocalMusicScreen extends StatefulWidget {
  const LocalMusicScreen({super.key});

  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends State<LocalMusicScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _searchController = TextEditingController();
  List<LocalTrack> _allTracks = [];
  List<LocalTrack> _filteredTracks = [];
  bool _isScanning = false;
  String? _error;
  TrackSortOption _sortOption = TrackSortOption.nameAsc;
  String? _lastScannedFolder;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoInitFolder();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _autoInitFolder() {
    final appState = context.read<AppState>();
    String path = appState.settings.localMusicPath.trim();

    if (path.isEmpty && Platform.isAndroid) {
      const defaultMusic = '/storage/emulated/0/Music';
      if (Directory(defaultMusic).existsSync()) {
        path = defaultMusic;
        appState.setLocalMusicPath(path);
      }
    }

    if (path.isNotEmpty && path != _lastScannedFolder) {
      _scanFolder(path);
    }
  }

  Future<void> _scanFolder(String folderPath, {bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _error = null;
    });

    try {
      final tracks = await LocalAudioScanner.scanDirectory(folderPath, forceRefresh: forceRefresh);
      if (!mounted) return;
      _lastScannedFolder = folderPath;
      _allTracks = tracks;
      _applySortAndFilter();
      setState(() {
        _isScanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Tarama hatası: $e';
        _isScanning = false;
      });
    }
  }

  void _onSearchChanged() {
    _applySortAndFilter();
    setState(() {});
  }

  void _applySortAndFilter() {
    final query = _searchController.text.trim().toLowerCase();
    var list = _allTracks.where((t) {
      if (query.isEmpty) return true;
      return t.title.toLowerCase().contains(query) ||
          t.artist.toLowerCase().contains(query) ||
          t.album.toLowerCase().contains(query);
    }).toList();

    switch (_sortOption) {
      case TrackSortOption.nameAsc:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case TrackSortOption.dateDesc:
        list.sort((a, b) => b.dateModified.compareTo(a.dateModified));
        break;
      case TrackSortOption.durationDesc:
        list.sort((a, b) => b.duration.compareTo(a.duration));
        break;
    }

    _filteredTracks = list;
  }

  Future<void> _pickFolder(AppState appState) async {
    try {
      final selected = await NativeFolderPicker.pickDirectory(
        initialPath: appState.settings.localMusicPath.isNotEmpty ? appState.settings.localMusicPath : null,
        title: 'Müzik Klasörünü Seçin',
      );
      if (selected != null && selected.trim().isNotEmpty) {
        final path = selected.trim();
        appState.setLocalMusicPath(path);
        LocalAudioScanner.clearCache(path);
        await _scanFolder(path, forceRefresh: true);
      }
    } catch (e) {
      setState(() => _error = 'Klasör seçilemedi: $e');
    }
  }

  void _playAll(PlayerProvider player, {bool shuffle = false}) {
    if (_filteredTracks.isEmpty) return;
    final queue = _filteredTracks.map((t) => t.toDownloadTask()).toList();
    if (shuffle) {
      if (!player.isShuffle) player.toggleShuffle();
      final randomTrack = _filteredTracks[DateTime.now().millisecondsSinceEpoch % _filteredTracks.length];
      player.playTask(randomTrack.toDownloadTask(), queue: queue);
    } else {
      player.playTask(_filteredTracks.first.toDownloadTask(), queue: queue);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appState = context.watch<AppState>();
    final player = context.watch<PlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = isMobileDevice(context);
    final selectedFolder = appState.settings.localMusicPath;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 36,
        vertical: isMobile ? 12 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Folder Header Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.greenMusic.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.folder_open_rounded, size: 22, color: AppColors.greenMusic),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        I18n.tr('local_library_title'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectedFolder.isNotEmpty ? selectedFolder : I18n.tr('no_folder_selected'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selectedFolder.isNotEmpty)
                  IconButton(
                    icon: _isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.greenMusic),
                          )
                        : const Icon(Icons.refresh_rounded),
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    tooltip: 'Yenile ve Tara',
                    onPressed: _isScanning ? null : () => _scanFolder(selectedFolder, forceRefresh: true),
                  ),
                FilledButton.icon(
                  icon: const Icon(Icons.folder_rounded, size: 15),
                  label: Text(
                    selectedFolder.isEmpty ? I18n.tr('btn_select_folder') : I18n.tr('btn_change_folder'),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _pickFolder(appState),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 2. Search & Sort Bar (if tracks available)
          if (_allTracks.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : AppColors.lightCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '${I18n.tr('search_local_placeholder')} (${_allTracks.length})',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.primaryBlue),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Sort Menu
                PopupMenuButton<TrackSortOption>(
                  tooltip: 'Sırala',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  icon: Icon(Icons.sort_rounded, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                  onSelected: (opt) {
                    setState(() {
                      _sortOption = opt;
                      _applySortAndFilter();
                    });
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: TrackSortOption.nameAsc,
                      child: Row(
                        children: [
                          const Icon(Icons.sort_by_alpha_rounded, size: 16),
                          const SizedBox(width: 8),
                          Text(I18n.tr('sort_name'), style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: TrackSortOption.dateDesc,
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 16),
                          const SizedBox(width: 8),
                          Text(I18n.tr('sort_date'), style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: TrackSortOption.durationDesc,
                      child: Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 16),
                          const SizedBox(width: 8),
                          Text(I18n.tr('sort_duration'), style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 3. Quick Hero Play Actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(
                      '${I18n.tr('btn_play_all')} (${_filteredTracks.length})',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _playAll(player, shuffle: false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    label: Text(
                      I18n.tr('btn_shuffle_all'),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? AppColors.purpleAccent : AppColors.primaryBlue,
                      side: BorderSide(
                        color: (isDark ? AppColors.purpleAccent : AppColors.primaryBlue).withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _playAll(player, shuffle: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // 4. Content Area: List of Tracks
          Expanded(
            child: _buildBody(player, isDark, isMobile),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(PlayerProvider player, bool isDark, bool isMobile) {
    if (_isScanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primaryBlue, strokeWidth: 3),
            const SizedBox(height: 16),
            Text(
              I18n.tr('scanning_library'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Alt klasörler taranıyor',
              style: TextStyle(fontSize: 11, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    if (_allTracks.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.greenMusic.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.library_music_rounded, size: 36, color: AppColors.greenMusic),
              ),
              const SizedBox(height: 16),
              Text(
                'Müzik Klasörünüzü Seçin',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Cihazınızdaki (Music, İndirilenler vb.) herhangi bir klasörü seçerek tüm müziklerinizi albüm kapaklarıyla offline dinleyin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Desteklenen: MP3, M4A, FLAC, OGG, WAV, AAC, OPUS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.greenMusic,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: AppColors.darkTextMuted),
            const SizedBox(height: 12),
            Text(
              'Aramanıza uygun müzik bulunamadı',
              style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(bottom: isMobile ? 120 : 36),
      itemCount: _filteredTracks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final track = _filteredTracks[index];
        final isThisPlaying = player.currentTask?.filePath == track.filePath && player.isPlaying;
        final isThisPaused = player.currentTask?.filePath == track.filePath && player.isPaused;
        final isCurrent = isThisPlaying || isThisPaused;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              final queue = _filteredTracks.map((t) => t.toDownloadTask()).toList();
              if (isThisPlaying) {
                player.togglePlayPause();
              } else if (isThisPaused) {
                player.togglePlayPause();
              } else {
                player.playTask(track.toDownloadTask(), queue: queue);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isCurrent
                    ? AppColors.primaryBlue.withValues(alpha: isDark ? 0.12 : 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: isCurrent
                    ? Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.35))
                    : null,
              ),
              child: Row(
                children: [
                  // Cover Art Thumbnail
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildTrackArt(track),
                          if (isCurrent)
                            Container(
                              color: Colors.black.withValues(alpha: 0.35),
                              child: Center(
                                child: Icon(
                                  isThisPlaying ? Icons.equalizer_rounded : Icons.pause_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

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
                            fontSize: 13.5,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                            color: isCurrent
                                ? AppColors.primaryBlue
                                : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            // Format Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: (track.format == 'FLAC'
                                        ? AppColors.purpleAccent
                                        : AppColors.greenMusic)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                track.format,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: track.format == 'FLAC'
                                      ? AppColors.purpleAccent
                                      : AppColors.greenMusic,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${track.artist} • ${track.album}',
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

                  const SizedBox(width: 8),

                  // Favorite Heart Button
                  IconButton(
                    icon: Icon(
                      context.watch<PlaylistManager>().isFavorite(track.filePath)
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 19,
                      color: context.watch<PlaylistManager>().isFavorite(track.filePath)
                          ? Colors.redAccent
                          : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      HapticService.light();
                      context.read<PlaylistManager>().toggleFavorite(track.filePath);
                    },
                  ),

                  // Duration & Size
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        track.durationStr,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.sizeStr,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),

                  // Context Popup Menu
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: isDark ? AppColors.darkCard : AppColors.lightCard,
                    onSelected: (action) {
                      if (action == 'add_to_playlist') {
                        AddToPlaylistDialog.show(context, track.filePath, trackTitle: track.title);
                      } else if (action == 'now_playing') {
                        NowPlayingSheet.show(context);
                      } else if (action == 'open_folder') {
                        FileLauncher.openFolder(track.filePath);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'add_to_playlist',
                        child: Row(
                          children: [
                            const Icon(Icons.playlist_add_rounded, size: 16, color: AppColors.primaryBlue),
                            const SizedBox(width: 8),
                            Text(I18n.tr('playlist_add_to'), style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'now_playing',
                        child: Row(
                          children: [
                            const Icon(Icons.open_in_full_rounded, size: 16, color: AppColors.purpleAccent),
                            const SizedBox(width: 8),
                            Text(I18n.tr('playlist_open_player'), style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'open_folder',
                        child: Row(
                          children: [
                            const Icon(Icons.folder_open_rounded, size: 16),
                            const SizedBox(width: 8),
                            Text(I18n.tr('playlist_file_location'), style: const TextStyle(fontSize: 12)),
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
      },
    );
  }

  Widget _buildTrackArt(LocalTrack track) {
    if (track.pictureBytes != null && track.pictureBytes!.isNotEmpty) {
      return Image.memory(
        track.pictureBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFallbackTrackArt(track),
      );
    } else if (track.cachedArtPath != null && File(track.cachedArtPath!).existsSync()) {
      return Image.file(
        File(track.cachedArtPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFallbackTrackArt(track),
      );
    }
    return _buildFallbackTrackArt(track);
  }

  Widget _buildFallbackTrackArt(LocalTrack track) {
    final title = track.title;
    final initial = title.isNotEmpty ? title[0].toUpperCase() : '♪';
    return Container(
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
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
