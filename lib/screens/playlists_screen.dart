import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/video_item.dart';
import '../theme/app_colors.dart';
import '../services/native_folder_picker.dart';
import '../services/youtube_service.dart';
import '../services/i18n.dart';
import '../services/haptic_service.dart';
import '../widgets/custom_playlist_view.dart';
import '../main.dart' show isMobileDevice;

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  late TabController _screenTabController;

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _filterController = TextEditingController();
  bool _isLoading = false;
  List<VideoItem> _playlistVideos = [];
  String _playlistTitle = '';
  final Set<String> _selectedVideoIds = {};
  String _filterQuery = '';

  // Batch download presets
  String _selectedFormat = 'm4a'; // 'm4a', 'mp4'
  String _selectedQuality = '256k'; // '256k', 'auto', '1080p'
  String? _customOutputPath;
  bool _createSubfolder = true;

  @override
  void initState() {
    super.initState();
    _screenTabController = TabController(length: 2, vsync: this);
    _screenTabController.addListener(() {
      if (!_screenTabController.indexIsChanging) {
        setState(() {});
      }
    });
    _filterController.addListener(() {
      setState(() {
        _filterQuery = _filterController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _screenTabController.dispose();
    _urlController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _fetchPlaylist() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _playlistVideos = [];
      _selectedVideoIds.clear();
      _playlistTitle = '';
      _filterQuery = '';
      _filterController.clear();
    });

    try {
      final res = await YouTubeService.fetchPlaylist(url);
      if (res.videos.isNotEmpty) {
        setState(() {
          _playlistTitle = res.title;
          _playlistVideos = res.videos;
          _selectedVideoIds.addAll(res.videos.map((e) => e.id));
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(I18n.tr('playlist_not_found_or_empty'))),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18n.tr('playlist_error_loading'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startBatchDownload(AppState appState) {
    if (_selectedVideoIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.tr('playlist_select_at_least_one'))),
      );
      return;
    }

    final isAudio = _selectedFormat == 'mp3' || _selectedFormat == 'm4a' || _selectedFormat == 'opus';
    final selectedItems = _playlistVideos.where((v) => _selectedVideoIds.contains(v.id)).toList();

    String finalPath = _customOutputPath ?? appState.settings.downloadPath;
    if (_createSubfolder && _playlistTitle.isNotEmpty) {
      final safeTitle = _playlistTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      finalPath = '$finalPath/$safeTitle';
    }

    final result = appState.startBatchDownload(
      selectedVideos: selectedItems,
      isAudio: isAudio,
      format: _selectedFormat,
      quality: _selectedQuality,
      outputPath: finalPath,
    );

    if (result.skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            I18n.tr('playlist_queued_with_skip', args: [result.queued.toString(), result.skipped.toString()]),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.tr('playlist_queued_count', args: [result.queued.toString()])),
        ),
      );
    }

    // Switch to Downloads tab to see live queue
    appState.setTabIndex(2);
  }

  List<VideoItem> get _filteredVideos {
    if (_filterQuery.isEmpty) return _playlistVideos;
    return _playlistVideos.where((v) {
      return v.title.toLowerCase().contains(_filterQuery) ||
          v.channel.toLowerCase().contains(_filterQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = isMobileDevice(context);

    // Sync external / shared playlist URL
    if (appState.currentPlaylistUrl != null &&
        appState.currentPlaylistUrl!.isNotEmpty &&
        appState.currentPlaylistUrl != _urlController.text) {
      _urlController.text = appState.currentPlaylistUrl!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _screenTabController.index != 1) {
          _screenTabController.animateTo(1);
        }
      });
      if (appState.playlistVideos.isNotEmpty && _playlistVideos != appState.playlistVideos) {
        _playlistVideos = List.from(appState.playlistVideos);
      }
    }

    return Column(
      children: [
        // Top Floating Pill Tab Switcher
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
              controller: _screenTabController,
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
                      const Icon(Icons.queue_music_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text(I18n.tr('playlist_tab_custom')),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_download_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text(I18n.tr('playlist_tab_youtube')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Body: TabBarView
        Expanded(
          child: TabBarView(
            controller: _screenTabController,
            children: [
              const CustomPlaylistView(),
              _buildYouTubePlaylistView(context, appState, isDark, isMobile),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildYouTubePlaylistView(
    BuildContext context,
    AppState appState,
    bool isDark,
    bool isMobile,
  ) {
    final currentPath = _customOutputPath ?? appState.settings.downloadPath;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 36,
        isMobile ? 8 : 16,
        isMobile ? 12 : 36,
        isMobile ? 120 : 36,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.purpleAccent, AppColors.primaryBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      I18n.tr('playlist_title'),
                      style: TextStyle(
                        fontSize: isMobile ? 19 : 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      I18n.tr('playlist_subtitle'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Playlist URL Input Pill Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14171F) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.link_rounded,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    onSubmitted: (_) => _fetchPlaylist(),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: isMobile ? 'YouTube Playlist linki yapıştırın...' : I18n.tr('playlist_placeholder'),
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (_urlController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    onPressed: () {
                      _urlController.clear();
                      setState(() {});
                    },
                  ),
                // Paste button
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2129) : const Color(0xFFEBF1F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    tooltip: I18n.tr('home_paste_btn'),
                    icon: const Icon(Icons.content_paste_rounded, size: 16, color: AppColors.primaryBlue),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _urlController.text = data!.text!;
                        _fetchPlaylist();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 4),
                // Fetch button
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryBlue, AppColors.purpleAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isLoading ? null : _fetchPlaylist,
                    child: _isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.flash_on_rounded, size: 15, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                isMobile ? 'Getir' : I18n.tr('playlist_fetch_btn'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.white),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Content Area: Empty vs Loaded Playlist
          if (_isLoading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 80),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const CircularProgressIndicator(color: AppColors.primaryBlue, strokeWidth: 3),
                  const SizedBox(height: 18),
                  Text(
                    I18n.tr('playlist_scanning'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'YouTube oynatma listesi taranıyor...',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            )
          else if (_playlistVideos.isEmpty)
            // 🌟 LUXURY HERO DISCOVERY CARD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF141824), const Color(0xFF1B162E)]
                      : [const Color(0xFFF1F5F9), const Color(0xFFEDE9FE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.cloud_download_rounded,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Toplu Playlist İndirme',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'YouTube\'dan albüm, sanatçı listesi veya oynatma listesi linkini yapıştırarak tüm parçaları tek tıkla yüksek kalitede toplu indirin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Feature badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildFeatureBadge(I18n.tr('playlist_badge_high_speed'), isDark),
                      _buildFeatureBadge(I18n.tr('playlist_badge_formats'), isDark),
                      _buildFeatureBadge(I18n.tr('playlist_badge_cover_art'), isDark),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Direct action button
                  ElevatedButton.icon(
                    icon: const Icon(Icons.content_paste_rounded, size: 16),
                    label: Text(I18n.tr('playlist_paste_start'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                      shadowColor: AppColors.primaryBlue.withValues(alpha: 0.4),
                    ),
                    onPressed: () async {
                      HapticService.selection();
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null && data!.text!.isNotEmpty) {
                        _urlController.text = data.text!;
                        _fetchPlaylist();
                      } else {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(I18n.tr('playlist_clipboard_empty'))),
                        );
                      }
                    },
                  ),
                ],
              ),
            )
          else
            // Responsive Layout: 1-Column on Mobile, 2-Column on Desktop
            isMobile
                ? _buildMobileLayout(context, appState, isDark, currentPath)
                : _buildDesktopLayout(context, appState, isDark, currentPath),
        ],
      ),
    );
  }

  Widget _buildFeatureBadge(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        ),
      ),
    );
  }

  // ── MOBILE LAYOUT (Single Column, Full Width, Highly Usable) ──
  Widget _buildMobileLayout(BuildContext context, AppState appState, bool isDark, String currentPath) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Playlist Hero Summary Card
        _buildPlaylistHeroCard(isDark),

        const SizedBox(height: 14),

        // 2. Batch Settings & Download Card
        _buildBatchControlCard(context, appState, isDark, currentPath, isMobile: true),

        const SizedBox(height: 18),

        // 3. Search & Video List Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Parça Listesi (${_filteredVideos.length})',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            if (_filterQuery.isNotEmpty)
              InkWell(
                onTap: () => _filterController.clear(),
                child: const Text(
                  'Filtreyi Temizle',
                  style: TextStyle(fontSize: 11, color: AppColors.primaryBlue, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),

        const SizedBox(height: 8),

        // 4. Video Items List
        _buildVideosList(isDark),
      ],
    );
  }

  // ── DESKTOP LAYOUT (2 Column Side-by-Side) ──
  Widget _buildDesktopLayout(BuildContext context, AppState appState, bool isDark, String currentPath) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Hero Overview & Video List
        Expanded(
          flex: 62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPlaylistHeroCard(isDark),
              const SizedBox(height: 16),
              _buildVideosList(isDark),
            ],
          ),
        ),

        const SizedBox(width: 24),

        // Right Column: Batch Control Panel
        Expanded(
          flex: 38,
          child: _buildBatchControlCard(context, appState, isDark, currentPath, isMobile: false),
        ),
      ],
    );
  }

  // ── PLAYLIST HERO CARD ──
  Widget _buildPlaylistHeroCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Playlist Cover
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: _playlistVideos.isNotEmpty
                      ? Image.network(
                          _playlistVideos.first.thumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: AppColors.primaryBlue.withValues(alpha: 0.2),
                            child: const Icon(Icons.music_note, color: AppColors.primaryBlue, size: 28),
                          ),
                        )
                      : Container(
                          color: AppColors.primaryBlue.withValues(alpha: 0.2),
                          child: const Icon(Icons.music_note, color: AppColors.primaryBlue, size: 28),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _playlistTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _InfoBadge(
                          icon: Icons.video_library_rounded,
                          text: '${_playlistVideos.length} Parça',
                          color: AppColors.primaryBlue,
                        ),
                        _InfoBadge(
                          icon: Icons.check_circle_rounded,
                          text: '${_selectedVideoIds.length} Seçildi',
                          color: AppColors.greenMusic,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Divider(height: 1, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          const SizedBox(height: 10),

          // Filter Box & Select All / Deselect All
          Row(
            children: [
              // Filter TextField
              Expanded(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF101217) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 15, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _filterController,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Listede ara...',
                            hintStyle: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_filterQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () => _filterController.clear(),
                          child: const Icon(Icons.close, size: 14),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Select All Button
              _QuickSelectButton(
                label: 'Tümü',
                icon: Icons.done_all_rounded,
                color: AppColors.primaryBlue,
                onTap: () {
                  setState(() {
                    _selectedVideoIds.addAll(_playlistVideos.map((v) => v.id));
                  });
                },
              ),
              const SizedBox(width: 6),
              // Deselect All Button
              _QuickSelectButton(
                label: 'Kaldır',
                icon: Icons.remove_done_rounded,
                color: Colors.redAccent,
                onTap: () {
                  setState(() {
                    _selectedVideoIds.clear();
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── BATCH DOWNLOAD SETTINGS CARD ──
  Widget _buildBatchControlCard(BuildContext context, AppState appState, bool isDark, String currentPath, {required bool isMobile}) {
    // Build quality items according to selected format
    List<DropdownMenuItem<String>> qualityItems;
    if (_selectedFormat == 'mp4') {
      qualityItems = [
        DropdownMenuItem(value: 'auto', child: Text(I18n.tr('modal_auto_best'))),
        DropdownMenuItem(value: '1080p', child: Text(I18n.tr('quality_1080p_title'))),
        DropdownMenuItem(value: '720p', child: Text(I18n.tr('quality_720p_title'))),
        DropdownMenuItem(value: '480p', child: Text(I18n.tr('quality_480p_title'))),
        DropdownMenuItem(value: '360p', child: Text(I18n.tr('quality_360p_title'))),
      ];
    } else if (_selectedFormat == 'mp3') {
      qualityItems = [
        DropdownMenuItem(value: '320k', child: Text(I18n.tr('modal_mp3_320_title'))),
        DropdownMenuItem(value: '192k', child: Text(I18n.tr('modal_mp3_192_title'))),
        DropdownMenuItem(value: '128k', child: Text(I18n.tr('modal_mp3_128_title'))),
      ];
    } else if (_selectedFormat == 'opus') {
      qualityItems = [
        DropdownMenuItem(value: '160k', child: Text(I18n.tr('modal_opus_160_title'))),
        DropdownMenuItem(value: '70k', child: Text(I18n.tr('modal_opus_70_title'))),
      ];
    } else {
      // m4a
      qualityItems = [
        DropdownMenuItem(value: '256k', child: Text(I18n.tr('modal_m4a_256_title'))),
        DropdownMenuItem(value: '128k', child: Text(I18n.tr('modal_m4a_128_title'))),
      ];
    }

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune_rounded, size: 17, color: AppColors.primaryBlue),
              ),
              const SizedBox(width: 8),
              Text(
                I18n.tr('playlist_panel_title'),
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Format Selector Chips
          Text(
            'Format',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FormatChip(
                  label: 'MP3 (Ses)',
                  icon: Icons.audiotrack_rounded,
                  isSelected: _selectedFormat == 'mp3',
                  color: Colors.orangeAccent,
                  onTap: () => setState(() {
                    _selectedFormat = 'mp3';
                    _selectedQuality = '320k';
                  }),
                ),
                const SizedBox(width: 8),
                _FormatChip(
                  label: 'M4A (Ses)',
                  icon: Icons.music_note_rounded,
                  isSelected: _selectedFormat == 'm4a',
                  color: AppColors.greenMusic,
                  onTap: () => setState(() {
                    _selectedFormat = 'm4a';
                    _selectedQuality = '256k';
                  }),
                ),
                const SizedBox(width: 8),
                _FormatChip(
                  label: 'Opus (Ses)',
                  icon: Icons.graphic_eq_rounded,
                  isSelected: _selectedFormat == 'opus',
                  color: Colors.purpleAccent,
                  onTap: () => setState(() {
                    _selectedFormat = 'opus';
                    _selectedQuality = '160k';
                  }),
                ),
                const SizedBox(width: 8),
                _FormatChip(
                  label: 'MP4 (Video)',
                  icon: Icons.videocam_rounded,
                  isSelected: _selectedFormat == 'mp4',
                  color: AppColors.redVideo,
                  onTap: () => setState(() {
                    _selectedFormat = 'mp4';
                    _selectedQuality = 'auto';
                  }),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Quality Selector
          Text(
            (_selectedFormat == 'mp4') ? 'Video Kalitesi' : 'Ses Kalitesi',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14161C) : const Color(0xFFF1F4F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedQuality,
                dropdownColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                items: qualityItems,
                onChanged: (val) {
                  if (val != null) setState(() => _selectedQuality = val);
                },
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Output Folder Picker
          Text(
            'İndirme Konumu',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14161C) : const Color(0xFFF1F4F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_rounded, size: 16, color: AppColors.primaryBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () async {
                    final picked = await NativeFolderPicker.pickDirectory(
                      initialPath: currentPath,
                      title: 'Playlist İndirme Klasörünü Seçin',
                    );
                    if (picked != null) {
                      setState(() {
                        _customOutputPath = picked;
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Gözat',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Subfolder Switch
          InkWell(
            onTap: () => setState(() => _createSubfolder = !_createSubfolder),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: _createSubfolder,
                    activeColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: (val) => setState(() => _createSubfolder = val ?? true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Playlist adına özel alt klasör oluştur',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Big Glowing Batch Download Button
          Builder(
            builder: (context) {
              List<Color> gradientColors;
              Color glowColor;
              if (_selectedFormat == 'mp3') {
                gradientColors = [Colors.orangeAccent, Colors.deepOrangeAccent];
                glowColor = Colors.orangeAccent;
              } else if (_selectedFormat == 'opus') {
                gradientColors = [Colors.purpleAccent, Colors.deepPurpleAccent];
                glowColor = Colors.purpleAccent;
              } else if (_selectedFormat == 'm4a') {
                gradientColors = [AppColors.greenMusic, const Color(0xFF00BFA5)];
                glowColor = AppColors.greenMusic;
              } else {
                gradientColors = [AppColors.redVideo, AppColors.purpleAccent];
                glowColor = AppColors.redVideo;
              }

              return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_download_rounded, size: 18, color: Colors.white),
                  label: Text(
                    'Seçilen ${_selectedVideoIds.length} Parçayı İndir',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _selectedVideoIds.isEmpty ? null : () => _startBatchDownload(appState),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── VIDEO ITEMS LIST ──
  Widget _buildVideosList(bool isDark) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredVideos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final video = _filteredVideos[index];
        final isSelected = _selectedVideoIds.contains(video.id);

        return RepaintBoundary(
          child: InkWell(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _selectedVideoIds.remove(video.id);
                } else {
                  _selectedVideoIds.add(video.id);
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? const Color(0xFF1E2435) : const Color(0xFFE9F2FF))
                    : (isDark ? AppColors.darkCard : AppColors.lightCard),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryBlue.withValues(alpha: 0.8)
                      : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  width: isSelected ? 1.4 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  // Track Index
                  SizedBox(
                    width: 24,
                    child: Text(
                      '#${index + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? AppColors.primaryBlue
                            : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                      ),
                    ),
                  ),

                  // Custom Checkbox
                  Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryBlue : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primaryBlue
                            : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                        width: 1.5,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),

                  // Thumbnail with Duration Overlay
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      children: [
                        Image.network(
                          video.thumbnail,
                          width: 72,
                          height: 42,
                          fit: BoxFit.cover,
                          cacheWidth: 160,
                          errorBuilder: (_, _, _) => Container(
                            width: 72,
                            height: 42,
                            color: Colors.black26,
                            child: const Icon(Icons.movie_creation_outlined, size: 18),
                          ),
                        ),
                        if (video.duration.isNotEmpty)
                          Positioned(
                            bottom: 2,
                            right: 3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                video.duration,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Title & Channel Metadata
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.person_rounded,
                              size: 11,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                video.channel,
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
          ),
        );
      },
    );
  }
}

class _FormatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _FormatChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.25),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: isSelected ? Colors.white : color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoBadge({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickSelectButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickSelectButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
