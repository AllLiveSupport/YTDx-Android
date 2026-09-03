import 'package:flutter/material.dart';
import '../models/video_item.dart';
import '../theme/app_colors.dart';
import '../services/i18n.dart';
import '../main.dart' show isMobileDevice;

/// Show QualityModal: bottom sheet on mobile, dialog on desktop
void showQualityModal(
  BuildContext context, {
  required VideoItem video,
  bool initialIsAudio = false,
  required Function(String format, String quality) onConfirm,
}) {
  final isMobile = isMobileDevice(context);
  if (isMobile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QualityModal(
        video: video,
        initialIsAudio: initialIsAudio,
        onConfirm: onConfirm,
      ),
    );
  } else {
    showDialog(
      context: context,
      builder: (_) => QualityModal(
        video: video,
        initialIsAudio: initialIsAudio,
        onConfirm: onConfirm,
      ),
    );
  }
}

class QualityModal extends StatefulWidget {
  final VideoItem video;
  final bool initialIsAudio;
  final Function(String format, String quality) onConfirm;

  const QualityModal({
    super.key,
    required this.video,
    this.initialIsAudio = false,
    required this.onConfirm,
  });

  @override
  State<QualityModal> createState() => _QualityModalState();
}

class _QualityModalState extends State<QualityModal> {
  late bool _isAudio;

  @override
  void initState() {
    super.initState();
    _isAudio = widget.initialIsAudio;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = isMobileDevice(context);
    final screenHeight = MediaQuery.of(context).size.height;

    final audioOptions = [
      // MP3 Options
      {
        'format': 'mp3',
        'quality': '320k',
        'title': I18n.tr('modal_mp3_320_title'),
        'desc': I18n.tr('modal_mp3_320_sub'),
        'badge': I18n.tr('modal_badge_ultra'),
        'color': Colors.orangeAccent,
        'icon': Icons.audiotrack_rounded,
      },
      {
        'format': 'mp3',
        'quality': '192k',
        'title': I18n.tr('modal_mp3_192_title'),
        'desc': I18n.tr('modal_mp3_192_sub'),
        'badge': '192k',
        'color': Colors.amber,
        'icon': Icons.audiotrack_rounded,
      },
      {
        'format': 'mp3',
        'quality': '128k',
        'title': I18n.tr('modal_mp3_128_title'),
        'desc': I18n.tr('modal_mp3_128_sub'),
        'badge': I18n.tr('modal_badge_fast'),
        'color': Colors.yellow,
        'icon': Icons.audiotrack_rounded,
      },
      // M4A Options
      {
        'format': 'm4a',
        'quality': '256k',
        'title': I18n.tr('modal_m4a_256_title'),
        'desc': I18n.tr('modal_m4a_256_sub'),
        'badge': I18n.tr('modal_badge_recommended'),
        'color': AppColors.greenMusic,
        'icon': Icons.music_note_rounded,
      },
      {
        'format': 'm4a',
        'quality': '128k',
        'title': I18n.tr('modal_m4a_128_title'),
        'desc': I18n.tr('modal_m4a_128_sub'),
        'badge': I18n.tr('modal_badge_fast'),
        'color': Colors.tealAccent,
        'icon': Icons.music_note_rounded,
      },
      // Opus Options
      {
        'format': 'opus',
        'quality': '160k',
        'title': I18n.tr('modal_opus_160_title'),
        'desc': I18n.tr('modal_opus_160_sub'),
        'badge': I18n.tr('modal_badge_max_clarity'),
        'color': Colors.purpleAccent,
        'icon': Icons.graphic_eq_rounded,
      },
      {
        'format': 'opus',
        'quality': '70k',
        'title': I18n.tr('modal_opus_70_title'),
        'desc': I18n.tr('modal_opus_70_sub'),
        'badge': I18n.tr('modal_badge_saver'),
        'color': Colors.indigoAccent,
        'icon': Icons.graphic_eq_rounded,
      },
    ];

    final videoOptions = [
      {
        'format': 'mp4',
        'quality': 'auto',
        'title': I18n.tr('modal_auto_best'),
        'desc': I18n.tr('modal_auto_best_sub'),
        'badge': I18n.tr('modal_badge_recommended'),
        'color': Colors.amber,
      },
      {
        'format': 'mp4',
        'quality': '4320p',
        'title': I18n.tr('quality_8k_title'),
        'desc': I18n.tr('quality_8k_desc'),
        'badge': '8K',
        'color': Colors.purpleAccent,
      },
      {
        'format': 'mp4',
        'quality': '2160p',
        'title': I18n.tr('quality_4k_title'),
        'desc': I18n.tr('quality_4k_desc'),
        'badge': '4K',
        'color': AppColors.redVideo,
      },
      {
        'format': 'mp4',
        'quality': '1440p',
        'title': I18n.tr('quality_2k_title'),
        'desc': I18n.tr('quality_2k_desc'),
        'badge': '2K',
        'color': AppColors.primaryBlue,
      },
      {
        'format': 'mp4',
        'quality': '1080p',
        'title': I18n.tr('quality_1080p_title'),
        'desc': I18n.tr('quality_1080p_desc'),
        'badge': '1080p',
        'color': Colors.tealAccent,
      },
      {
        'format': 'mp4',
        'quality': '720p',
        'title': I18n.tr('quality_720p_title'),
        'desc': I18n.tr('quality_720p_desc'),
        'badge': null,
        'color': Colors.grey,
      },
      {
        'format': 'mp4',
        'quality': '480p',
        'title': I18n.tr('quality_480p_title'),
        'desc': I18n.tr('quality_480p_desc'),
        'badge': null,
        'color': Colors.grey,
      },
      {
        'format': 'mp4',
        'quality': '360p',
        'title': I18n.tr('quality_360p_title'),
        'desc': I18n.tr('quality_360p_desc'),
        'badge': null,
        'color': Colors.grey,
      },
    ];

    final options = _isAudio ? audioOptions : videoOptions;

    // Mobile: bottom sheet style; Desktop: centered dialog
    if (isMobile) {
      return Container(
        height: screenHeight * 0.78,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: _QualityModalContent(
                video: widget.video,
                isAudio: _isAudio,
                options: options,
                isDark: isDark,
                isMobile: true,
                onToggle: () => setState(() => _isAudio = !_isAudio),
                onConfirm: (fmt, qlt) {
                  Navigator.of(context).pop();
                  widget.onConfirm(fmt, qlt);
                },
              ),
            ),
          ],
        ),
      );
    }

    return Dialog(
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
      ),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 640),
        padding: const EdgeInsets.all(22),
        child: _QualityModalContent(
          video: widget.video,
          isAudio: _isAudio,
          options: options,
          isDark: isDark,
          isMobile: false,
          onToggle: () => setState(() => _isAudio = !_isAudio),
          onConfirm: (fmt, qlt) {
            Navigator.of(context).pop();
            widget.onConfirm(fmt, qlt);
          },
        ),
      ),
    );
  }
}

class _QualityModalContent extends StatelessWidget {
  final VideoItem video;
  final bool isAudio;
  final List<Map<String, dynamic>> options;
  final bool isDark;
  final bool isMobile;
  final VoidCallback onToggle;
  final Function(String, String) onConfirm;

  const _QualityModalContent({
    required this.video,
    required this.isAudio,
    required this.options,
    required this.isDark,
    required this.isMobile,
    required this.onToggle,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(isMobile ? 18 : 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: video.thumbnail.isNotEmpty
                    ? Image.network(
                        video.thumbnail,
                        width: 48,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 48,
                          height: 36,
                          color: Colors.grey.shade800,
                          child: const Icon(Icons.movie_creation_outlined, size: 20, color: Colors.white70),
                        ),
                      )
                    : Container(
                        width: 48,
                        height: 36,
                        color: Colors.grey.shade800,
                        child: const Icon(Icons.movie_creation_outlined, size: 20, color: Colors.white70),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAudio ? I18n.tr('modal_title_audio') : I18n.tr('modal_title_video'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, size: 20, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Tab Selector: Video / Müzik
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2129) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: isAudio ? onToggle : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: !isAudio ? AppColors.redVideo : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: !isAudio
                            ? [BoxShadow(color: AppColors.redVideo.withValues(alpha: 0.3), blurRadius: 4)]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.videocam_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            I18n.tr('modal_video_tab'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    onTap: !isAudio ? onToggle : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: isAudio ? AppColors.greenMusic : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: isAudio
                            ? [BoxShadow(color: AppColors.greenMusic.withValues(alpha: 0.3), blurRadius: 4)]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.music_note_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            I18n.tr('modal_audio_tab'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Scrollable Quality Options
          Expanded(
            child: ListView.separated(
              itemCount: options.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final opt = options[index];
                final badge = opt['badge'] as String?;
                final color = (opt['color'] as Color?) ?? AppColors.primaryBlue;

                return InkWell(
                  onTap: () => onConfirm(opt['format'] as String, opt['quality'] as String),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 14,
                      vertical: isMobile ? 14 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2129) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (opt['icon'] as IconData?) ??
                              (isAudio ? Icons.music_note_rounded : Icons.play_circle_outline_rounded),
                          color: color,
                          size: isMobile ? 26 : 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      opt['title'] as String,
                                      style: TextStyle(
                                        fontSize: isMobile ? 14 : 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                                      ),
                                    ),
                                  ),
                                  if (badge != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        badge,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                opt['desc'] as String,
                                style: TextStyle(
                                  fontSize: isMobile ? 11.5 : 11,
                                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
