import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/playlist_manager.dart';
import '../services/haptic_service.dart';
import '../services/i18n.dart';
import '../theme/app_colors.dart';

class AddToPlaylistDialog {
  static void show(BuildContext context, String filePath, {String? trackTitle}) {
    HapticService.light();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Consumer<PlaylistManager>(
          builder: (ctx, manager, _) {
            final playlists = manager.playlists;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      I18n.tr('playlist_add_to'),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    if (trackTitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        trackTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: playlists.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (ctx, index) {
                        final pl = playlists[index];
                        final isInPlaylist = pl.trackPaths.contains(filePath);
                        final plColor = Color(pl.colorValue);

                        return Material(
                          color: Colors.transparent,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            tileColor: isInPlaylist
                                ? plColor.withValues(alpha: isDark ? 0.16 : 0.1)
                                : Colors.transparent,
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: plColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                pl.isFavorites ? Icons.favorite_rounded : Icons.queue_music_rounded,
                                color: plColor,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              pl.getLocalizedTitle(),
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                              ),
                            ),
                            subtitle: Text(
                              I18n.tr('playlist_count_tracks', args: [pl.trackPaths.length.toString()]),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                              ),
                            ),
                            trailing: Checkbox(
                              value: isInPlaylist,
                              activeColor: plColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                              onChanged: (val) async {
                                HapticService.selection();
                                if (isInPlaylist) {
                                  await manager.removeTrackFromPlaylist(pl.id, filePath);
                                } else {
                                  await manager.addTrackToPlaylist(pl.id, filePath);
                                }
                              },
                            ),
                            onTap: () async {
                              HapticService.selection();
                              if (isInPlaylist) {
                                await manager.removeTrackFromPlaylist(pl.id, filePath);
                              } else {
                                await manager.addTrackToPlaylist(pl.id, filePath);
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
