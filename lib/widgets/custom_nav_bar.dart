import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class CustomFloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final List<CustomNavItem> items;

  const CustomFloatingNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xDC14161D)
                  : Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.06),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (index) {
                final item = items[index];
                final isSelected = selectedIndex == index;

                return Expanded(
                  child: InkWell(
                    onTap: () => onItemSelected(index),
                    borderRadius: BorderRadius.circular(18),
                    splashColor: AppColors.primaryBlue.withValues(alpha: 0.15),
                    highlightColor: Colors.transparent,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryBlue.withValues(alpha: isDark ? 0.18 : 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        border: isSelected
                            ? Border.all(
                                color: AppColors.primaryBlue.withValues(alpha: 0.3),
                                width: 1,
                              )
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Icon with Badge
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedScale(
                                scale: isSelected ? 1.15 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutBack,
                                child: Icon(
                                  isSelected ? item.selectedIcon : item.icon,
                                  size: 22,
                                  color: isSelected
                                      ? AppColors.primaryBlue
                                      : (isDark
                                          ? AppColors.darkTextMuted
                                          : AppColors.lightTextMuted),
                                ),
                              ),
                              if (item.badgeCount != null && item.badgeCount! > 0)
                                Positioned(
                                  top: -3,
                                  right: -6,
                                  child: Container(
                                    padding: const EdgeInsets.all(3.5),
                                    decoration: const BoxDecoration(
                                      color: AppColors.primaryBlue,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      item.badgeCount! > 9 ? '9+' : '${item.badgeCount}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          // Label
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: isSelected ? 10.5 : 9.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primaryBlue
                                  : (isDark
                                      ? AppColors.darkTextMuted
                                      : AppColors.lightTextMuted),
                              fontFamily: 'Inter',
                            ),
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class CustomNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int? badgeCount;

  const CustomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount,
  });
}
