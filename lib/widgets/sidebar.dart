import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_colors.dart';
import '../services/i18n.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final currentTabIndex = context.select<AppState, int>((s) => s.currentTabIndex);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final navItems = [
      _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, title: I18n.tr('nav_home'), index: 0),
      _NavItem(icon: Icons.search_outlined, activeIcon: Icons.search, title: I18n.tr('nav_search'), index: 1),
      _NavItem(icon: Icons.download_outlined, activeIcon: Icons.download, title: I18n.tr('nav_downloads'), index: 2),
      _NavItem(icon: Icons.playlist_play_outlined, activeIcon: Icons.playlist_play, title: I18n.tr('nav_playlists'), index: 3),
      _NavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, title: I18n.tr('nav_settings'), index: 4),
    ];

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSidebar : AppColors.lightSidebar,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App Brand / Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/icons/app_icon.png',
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'YTDx Downloader',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Navigation Links
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: navItems.map((item) {
                final isSelected = currentTabIndex == item.index;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => context.read<AppState>().setTabIndex(item.index),
                      hoverColor: isDark ? AppColors.darkCardHover : AppColors.lightCardHover,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark ? AppColors.darkCardHover : AppColors.lightCardHover)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? item.activeIcon : item.icon,
                              size: 20,
                              color: isSelected
                                  ? AppColors.primary
                                  : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  color: isSelected
                                      ? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)
                                      : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String title;
  final int index;

  _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.title,
    required this.index,
  });
}
