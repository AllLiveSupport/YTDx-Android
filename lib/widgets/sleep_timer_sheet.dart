import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../services/haptic_service.dart';
import '../services/i18n.dart';
import '../theme/app_colors.dart';

class SleepTimerSheet extends StatefulWidget {
  const SleepTimerSheet({super.key});

  static void show(BuildContext context) {
    HapticService.light();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF14161C) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => const SleepTimerSheet(),
    );
  }

  @override
  State<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<SleepTimerSheet> with SingleTickerProviderStateMixin {
  int _selectedMinutes = 30;
  bool _isEndOfTrack = false;
  bool _fadeOut = true;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatRemaining(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final player = context.watch<PlayerProvider>();
    final isActive = player.isSleepTimerActive;
    final remaining = player.sleepTimerRemaining;
    final isEndOfTrackActive = player.isSleepTimerEndOfTrack;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Active Countdown View vs Configuration View
            if (isActive)
              _buildActiveTimerView(context, player, isDark, remaining, isEndOfTrackActive)
            else
              _buildSetupTimerView(context, player, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTimerView(
    BuildContext context,
    PlayerProvider player,
    bool isDark,
    Duration? remaining,
    bool isEndOfTrackActive,
  ) {
    return Column(
      children: [
        // Pulsing Glowing Crescent Moon
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryBlue.withValues(alpha: 0.22),
                      const Color(0xFF8B5CF6).withValues(alpha: 0.22),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.28),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.nightlight_round,
                    size: 40,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),

        Text(
          isEndOfTrackActive ? I18n.tr('sleep_timer_end_of_track') : _formatRemaining(remaining ?? Duration.zero),
          style: TextStyle(
            fontSize: isEndOfTrackActive ? 26 : 40,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: isEndOfTrackActive ? -0.5 : 1.2,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isEndOfTrackActive
              ? I18n.tr('sleep_timer_end_of_track_desc')
              : I18n.tr('sleep_timer_remaining_desc'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          ),
        ),

        // Fade-out indicator chip
        if (player.sleepTimerFadeOut) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.volume_down_rounded, size: 14, color: AppColors.primaryBlue),
                const SizedBox(width: 6),
                Text(
                  I18n.tr('sleep_timer_fadeout'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : AppColors.primaryBlue,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Quick add buttons (if not end of track)
        if (!isEndOfTrackActive)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildQuickAddChip('+5 dk', 5, player, isDark),
              const SizedBox(width: 10),
              _buildQuickAddChip('+10 dk', 10, player, isDark),
              const SizedBox(width: 10),
              _buildQuickAddChip('+15 dk', 15, player, isDark),
            ],
          ),

        const SizedBox(height: 24),

        // Cancel Timer Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () {
              HapticService.medium();
              player.cancelSleepTimer();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.close_rounded, size: 20),
            label: Text(
              I18n.tr('sleep_timer_cancel'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              backgroundColor: Colors.redAccent.withValues(alpha: 0.14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.25)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAddChip(String label, int minutes, PlayerProvider player, bool isDark) {
    return InkWell(
      onTap: () {
        HapticService.light();
        player.addSleepTimerMinutes(minutes);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildSetupTimerView(BuildContext context, PlayerProvider player, bool isDark) {
    final presets = [15, 30, 45, 60];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.nightlight_round, size: 22, color: AppColors.primaryBlue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    I18n.tr('sleep_timer_title'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    I18n.tr('sleep_timer_subtitle'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Duration Presets Chips
        Text(
          I18n.tr('sleep_timer_choose_duration'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 10),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...presets.map((min) {
              final isSelected = !_isEndOfTrack && _selectedMinutes == min;
              return ChoiceChip(
                label: Text(I18n.tr('sleep_timer_minutes', args: [min.toString()])),
                selected: isSelected,
                selectedColor: AppColors.primaryBlue,
                backgroundColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                labelStyle: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primaryBlue
                        : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                  ),
                ),
                onSelected: (val) {
                  HapticService.light();
                  setState(() {
                    _selectedMinutes = min;
                    _isEndOfTrack = false;
                  });
                },
              );
            }),

            // End of track chip
            ChoiceChip(
              avatar: Icon(
                Icons.music_note_rounded,
                size: 16,
                color: _isEndOfTrack
                    ? Colors.white
                    : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
              ),
              label: Text(I18n.tr('sleep_timer_end_of_track')),
              selected: _isEndOfTrack,
              selectedColor: AppColors.primaryBlue,
              backgroundColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
              labelStyle: TextStyle(
                color: _isEndOfTrack
                    ? Colors.white
                    : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                fontWeight: _isEndOfTrack ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: _isEndOfTrack
                      ? AppColors.primaryBlue
                      : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                ),
              ),
              onSelected: (val) {
                HapticService.light();
                setState(() {
                  _isEndOfTrack = true;
                });
              },
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Custom minute slider if not end of track
        if (!_isEndOfTrack) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                I18n.tr('sleep_timer_custom'),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                ),
              ),
              Text(
                I18n.tr('sleep_timer_custom_min', args: [_selectedMinutes.toString()]),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlue,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primaryBlue,
              inactiveTrackColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
              thumbColor: AppColors.primaryBlue,
              overlayColor: AppColors.primaryBlue.withValues(alpha: 0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: _selectedMinutes.toDouble().clamp(5.0, 120.0),
              min: 5,
              max: 120,
              divisions: 23,
              onChanged: (val) {
                setState(() {
                  _selectedMinutes = val.toInt();
                  _isEndOfTrack = false;
                });
              },
            ),
          ),
        ],

        // Fade-out toggle switch card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.volume_down_rounded, size: 18, color: AppColors.primaryBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      I18n.tr('sleep_timer_fadeout'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      I18n.tr('sleep_timer_subtitle'),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _fadeOut,
                activeTrackColor: AppColors.primaryBlue,
                onChanged: (val) {
                  HapticService.light();
                  setState(() => _fadeOut = val);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        // Start Sleep Timer Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () {
              HapticService.medium();
              if (_isEndOfTrack) {
                player.startSleepTimerEndOfTrack(fadeOut: _fadeOut);
              } else {
                player.startSleepTimer(
                  Duration(minutes: _selectedMinutes),
                  fadeOut: _fadeOut,
                );
              }
              Navigator.pop(context);
            },
            icon: const Icon(Icons.check_circle_rounded, size: 20),
            label: Text(
              _isEndOfTrack
                  ? I18n.tr('sleep_timer_end_of_track')
                  : I18n.tr('sleep_timer_minutes', args: [_selectedMinutes.toString()]),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: AppColors.primaryBlue,
              elevation: 4,
              shadowColor: AppColors.primaryBlue.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
