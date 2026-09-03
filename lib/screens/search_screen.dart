import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/video_card.dart';
import '../services/i18n.dart';
import '../main.dart' show isMobileDevice;

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _lastSyncedQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      final appState = context.read<AppState>();
      if (!appState.isLoadingMore && appState.searchResults.isNotEmpty) {
        appState.loadMoreSearchResults();
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _triggerSearch(AppState appState) {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _lastSyncedQuery = query;
      appState.search(query);
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = isMobileDevice(context);

    if (_lastSyncedQuery != appState.searchQuery) {
      _lastSyncedQuery = appState.searchQuery;
      _searchController.text = appState.searchQuery;
    }

    return Column(
      children: [
        // Top Search Bar - fixed at top on mobile
        Container(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 12 : 36,
            isMobile ? 12 : 24,
            isMobile ? 12 : 36,
            isMobile ? 10 : 16,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
            border: Border(
              bottom: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMobile) ...[
                Text(
                  I18n.tr('search_title'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              // Search Bar
              Container(
                height: isMobile ? 46 : 42,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(Icons.search, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: I18n.tr('search_placeholder'),
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (_) => _triggerSearch(appState),
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                    // Paste button (compact on mobile)
                    if (!isMobile)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.paste, size: 14),
                        label: Text(I18n.tr('home_paste_btn'), style: const TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data != null && data.text != null) {
                            _searchController.text = data.text!;
                            _triggerSearch(appState);
                          }
                        },
                      ),
                    if (isMobile)
                      IconButton(
                        icon: const Icon(Icons.paste_rounded, size: 18),
                        color: AppColors.primary,
                        padding: EdgeInsets.zero,
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data != null && data.text != null) {
                            _searchController.text = data.text!;
                            _triggerSearch(appState);
                          }
                        },
                      ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      color: AppColors.primary,
                      padding: EdgeInsets.zero,
                      onPressed: () => _triggerSearch(appState),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Results
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.fromLTRB(
              isMobile ? 12 : 36,
              isMobile ? 12 : 20,
              isMobile ? 12 : 36,
              isMobile ? 120 : 36,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (appState.isSearching)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  )
                else if (appState.searchResults.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 80),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            I18n.tr('search_no_results'),
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isMobile ? 2 : 4,
                      crossAxisSpacing: isMobile ? 10 : 18,
                      mainAxisSpacing: isMobile ? 10 : 18,
                      childAspectRatio: isMobile ? 0.72 : 0.88,
                    ),
                    itemCount: appState.searchResults.length,
                    itemBuilder: (context, index) {
                      return VideoCard(video: appState.searchResults[index]);
                    },
                  ),

                if (appState.isLoadingMore)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryBlue),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            I18n.tr('search_loading_more'),
                            style: const TextStyle(fontSize: 12.5, color: AppColors.primaryBlue, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
