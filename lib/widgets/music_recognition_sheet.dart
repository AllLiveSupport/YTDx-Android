import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shazam_identifier/shazam_identifier.dart';
import '../models/download_task.dart';
import '../providers/app_state.dart';
import '../services/song_recognition_service.dart';
import '../services/youtube_service.dart';
import '../services/i18n.dart';
import '../theme/app_colors.dart';
import 'quality_modal.dart';

/// Shows the Shazam-powered Music Recognition modal bottom sheet
Future<void> showMusicRecognitionSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (ctx) => const MusicRecognitionSheet(),
  );
}

class MusicRecognitionSheet extends StatefulWidget {
  const MusicRecognitionSheet({super.key});

  @override
  State<MusicRecognitionSheet> createState() => _MusicRecognitionSheetState();
}

class _MusicRecognitionSheetState extends State<MusicRecognitionSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final SongRecognitionService _recognitionService = SongRecognitionService.instance;

  bool _isListening = false;
  bool _isProcessing = false;
  int _countdownSeconds = 6;
  Timer? _countdownTimer;

  RecognitionResult? _result;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOutQuad,
    );

    // Auto-start listening on modal open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startRecognition();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startRecognition() async {
    setState(() {
      _isListening = true;
      _isProcessing = false;
      _errorMessage = null;
      _result = null;
      _countdownSeconds = 6;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_countdownSeconds > 1) {
          _countdownSeconds--;
        } else {
          _isListening = false;
          _isProcessing = true;
          timer.cancel();
        }
      });
    });

    try {
      final status = await _recognitionService.recognize();
      _countdownTimer?.cancel();

      if (!mounted) return;

      if (status.state == RecognitionStatusState.success && status.result != null) {
        HapticFeedback.mediumImpact();
        setState(() {
          _isListening = false;
          _isProcessing = false;
          _result = status.result;
          _errorMessage = null;
        });
      } else if (status.state == RecognitionStatusState.noMatch) {
        HapticFeedback.selectionClick();
        setState(() {
          _isListening = false;
          _isProcessing = false;
          _errorMessage = "Ortamdaki müzik tespit edilemedi. Lütfen mikrofona biraz daha yaklaşın.";
        });
      } else {
        setState(() {
          _isListening = false;
          _isProcessing = false;
          _errorMessage = status.message ?? "Müzik tanıma sırasında bir sorun oluştu.";
        });
      }
    } catch (e) {
      _countdownTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _isProcessing = false;
        _errorMessage = "Hata: $e";
      });
    }
  }

  void _searchAndDownload(BuildContext context, AppState appState) async {
    if (_result == null) return;
    final query = "${_result!.artist} ${_result!.title}";

    // Show loading dialog while searching
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      ),
    );

    try {
      final videos = await YouTubeService.searchVideos(query);
      if (context.mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading
      }

      if (videos.isNotEmpty && context.mounted) {
        Navigator.of(context).pop(); // Close recognition sheet
        showQualityModal(
          context,
          video: videos.first,
          initialIsAudio: true,
          onConfirm: (fmt, qlt) {
            final isAud = DownloadTask.isAudioFormat(fmt);
            appState.startDownload(
              video: videos.first,
              isAudio: isAud,
              format: fmt,
              quality: qlt,
              outputPath: appState.settings.downloadPath,
            );
          },
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18n.tr('recognition_not_found'))),
        );
      }
    } catch (e) {
      if (context.mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18n.tr('recognition_search_error', args: [e.toString()]))),
        );
      }
    }
  }

  void _searchInApp(BuildContext context, AppState appState) {
    if (_result == null) return;
    final query = "${_result!.artist} ${_result!.title}";
    Navigator.of(context).pop();
    appState.search(query);
    appState.setTabIndex(1);
  }

  void _copyToClipboard(BuildContext context) {
    if (_result == null) return;
    final text = "${_result!.artist} - ${_result!.title}";
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(I18n.tr('recognition_copied', args: [text]))),
          ],
        ),
        backgroundColor: const Color(0xFF1E2230),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appState = Provider.of<AppState>(context, listen: false);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13151D) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: isDark ? const Color(0xFF262A36) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
            blurRadius: 30,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 20,
        top: 12,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header Capsule Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryBlue.withValues(alpha: isDark ? 0.22 : 0.12),
                  AppColors.purpleAccent.withValues(alpha: isDark ? 0.22 : 0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: isDark ? 0.35 : 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.graphic_eq_rounded, size: 16, color: AppColors.primaryBlue),
                const SizedBox(width: 8),
                Text(
                  'YTDx Shazam Motoru • Çevrimdışı STFT',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.primaryBlue,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Dynamic Body based on State
          if (_isListening || _isProcessing)
            _buildListeningView(isDark)
          else if (_result != null)
            _buildResultView(context, isDark, appState)
          else
            _buildErrorOrEmptyView(isDark),
        ],
      ),
    );
  }

  // Listening & Processing Animation View
  Widget _buildListeningView(bool isDark) {
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Ripple Ring 1
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  final scale = 1.0 + (_pulseAnimation.value * 0.7);
                  final opacity = (1.0 - _pulseAnimation.value).clamp(0.0, 1.0);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primaryBlue.withValues(alpha: opacity * 0.5),
                          width: 2,
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Outer Ripple Ring 2
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  final val = (_pulseAnimation.value + 0.5) % 1.0;
                  final scale = 1.0 + (val * 0.6);
                  final opacity = (1.0 - val).clamp(0.0, 1.0);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.purpleAccent.withValues(alpha: opacity * 0.4),
                          width: 2,
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Glowing Center Radar Button
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryBlue, AppColors.purpleAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _isProcessing ? Icons.auto_awesome_rounded : Icons.mic_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Text(
          _isProcessing ? I18n.tr('recognition_processing') : I18n.tr('recognition_listening'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.lightTextPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isProcessing
              ? I18n.tr('recognition_db_match')
              : I18n.tr('recognition_hold_near', args: [_countdownSeconds.toString()]),
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  // Result Success View
  Widget _buildResultView(BuildContext context, bool isDark, AppState appState) {
    final result = _result!;
    final coverUrl = result.coverArtHqUrl ?? result.coverArtUrl;

    return Column(
      children: [
        // Album Cover Art
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: coverUrl != null && coverUrl.isNotEmpty
                ? Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => _buildFallbackCover(),
                  )
                : _buildFallbackCover(),
          ),
        ),
        const SizedBox(height: 16),

        // Track Title
        Text(
          result.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.lightTextPrimary,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),

        // Artist Name
        Text(
          result.artist,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryBlue,
          ),
        ),
        const SizedBox(height: 24),

        // Primary Action: Download Audio / Video
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 20, color: Colors.white),
            label: Text(
              I18n.tr('modal_title_video'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.greenMusic,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: () => _searchAndDownload(context, appState),
          ),
        ),
        const SizedBox(height: 10),

        // Secondary Actions Row
        Row(
          children: [
            // Search in App
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.search_rounded, size: 18),
                label: Text(I18n.tr('recognition_view_results'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white : AppColors.lightTextPrimary,
                  side: BorderSide(color: isDark ? const Color(0xFF2E3242) : const Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _searchInApp(context, appState),
              ),
            ),
            const SizedBox(width: 10),

            // Copy Title
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: Text(I18n.tr('recognition_copy'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white : AppColors.lightTextPrimary,
                  side: BorderSide(color: isDark ? const Color(0xFF2E3242) : const Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _copyToClipboard(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Listen Again
        TextButton.icon(
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text(I18n.tr('recognition_try_another'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
          onPressed: _startRecognition,
        ),
      ],
    );
  }

  // Error or Not Found View
  Widget _buildErrorOrEmptyView(bool isDark) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.redAccent.withValues(alpha: isDark ? 0.15 : 0.10),
          ),
          child: const Icon(Icons.music_off_rounded, size: 36, color: Colors.redAccent),
        ),
        const SizedBox(height: 16),

        Text(
          'Şarkı Tespit Edilemedi',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 8),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _errorMessage ?? 'Ortamdaki ses çok kısık olabilir. Müziğin çaldığı hoparlöre biraz daha yaklaşıp tekrar deneyin.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 22),

        // Retry Button
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.mic_rounded, size: 18, color: Colors.white),
            label: const Text(
              'Tekrar Dinle',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: _startRecognition,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildFallbackCover() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryBlue, AppColors.purpleAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note_rounded, size: 60, color: Colors.white),
      ),
    );
  }
}
