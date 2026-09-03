import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../main.dart' show MainShell;
import '../theme/app_colors.dart';
import '../services/haptic_service.dart';
import '../services/i18n.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _mainController;
  late final AnimationController _pulseController;
  late final AnimationController _equalizerController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<double> _equalizerFade;
  late final Animation<double> _progressAnimation;

  Timer? _navigationTimer;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    // 1. Entrance timeline controller (1400ms)
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _logoScale = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
    );

    _logoFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
    );

    _textFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic),
    );

    _equalizerFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOutCubic),
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeInOutCubic),
      ),
    );

    // 2. Ambient breathing halo pulse (2400ms repeat reverse)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    // 3. Mini equalizer dancing bars (700ms repeat reverse)
    _equalizerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _mainController.forward();

    // Auto navigate after 2.3 seconds
    _navigationTimer = Timer(const Duration(milliseconds: 2300), _proceedToApp);
  }

  void _proceedToApp() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _navigationTimer?.cancel();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) => const MainShell(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _mainController.dispose();
    _pulseController.dispose();
    _equalizerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticService.selection();
        _proceedToApp();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF08090D),
        body: Stack(
          children: [
            // Ambient Radial Gradients
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  final pulse = _pulseController.value;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.15),
                        radius: 1.1 + (pulse * 0.2),
                        colors: [
                          AppColors.primaryBlue.withValues(alpha: 0.18 + (pulse * 0.08)),
                          const Color(0xFF6366F1).withValues(alpha: 0.08 + (pulse * 0.04)),
                          const Color(0xFF08090D),
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Subtle Cyber Grid / Radial Dot Accent in Background
            Positioned.fill(
              child: CustomPaint(
                painter: _AmbientGlowPainter(pulse: _pulseController),
              ),
            ),

            // Main Brand Center Content
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // Animated Glowing Logo Box
                  AnimatedBuilder(
                    animation: Listenable.merge([_mainController, _pulseController]),
                    builder: (context, child) {
                      final scale = _logoScale.value;
                      final fade = _logoFade.value;
                      final pulse = _pulseController.value;

                      return Opacity(
                        opacity: fade.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: scale,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer expanding ripple halo
                              Container(
                                width: 155 + (pulse * 24),
                                height: 155 + (pulse * 24),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primaryBlue.withValues(
                                      alpha: (0.35 - pulse * 0.25).clamp(0.0, 1.0),
                                    ),
                                    width: 1.5,
                                  ),
                                ),
                              ),

                              // Inner soft glow ring
                              Container(
                                width: 130 + (pulse * 12),
                                height: 130 + (pulse * 12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.cyanAccent.withValues(
                                      alpha: (0.5 - pulse * 0.2).clamp(0.0, 1.0),
                                    ),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryBlue.withValues(
                                        alpha: 0.25 + (pulse * 0.15),
                                      ),
                                      blurRadius: 35,
                                      spreadRadius: 6,
                                    ),
                                  ],
                                ),
                              ),

                              // Center Glassmorphic Circular Logo Capsule
                              Container(
                                width: 104,
                                height: 104,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                    BoxShadow(
                                      color: AppColors.primaryBlue.withValues(alpha: 0.6),
                                      blurRadius: 28,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Image.asset(
                                      'assets/icons/app_icon.png',
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // Brand Title & Tagline
                  FadeTransition(
                    opacity: _textFade,
                    child: Column(
                      children: [
                        // App Title with Gradient Shimmer
                        ShaderMask(
                          shaderCallback: (bounds) {
                            return const LinearGradient(
                              colors: [
                                Colors.white,
                                Color(0xFFE0F2FE),
                                Color(0xFF38BDF8),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'YTDx Studio',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: Colors.white,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Subtitle Tagline
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            I18n.tr('splash_subtitle'),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.0,
                              color: Colors.white.withValues(alpha: 0.75),
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Animated Mini Equalizer Bars
                  FadeTransition(
                    opacity: _equalizerFade,
                    child: AnimatedBuilder(
                      animation: _equalizerController,
                      builder: (context, _) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(7, (index) {
                            final phase = (index * 0.5) % math.pi;
                            final value = math.sin(_equalizerController.value * math.pi + phase).abs();
                            final height = 6.0 + (value * 18.0);

                            return Container(
                              width: 3.5,
                              height: height,
                              margin: const EdgeInsets.symmetric(horizontal: 2.5),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primaryBlue,
                                    Colors.cyanAccent.withValues(alpha: 0.8),
                                  ],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ),

                  const Spacer(flex: 4),

                  // Bottom Slim Progress Bar & Footer Badge
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: AnimatedBuilder(
                      animation: _progressAnimation,
                      builder: (context, _) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            height: 3,
                            color: Colors.white.withValues(alpha: 0.08),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: _progressAnimation.value.clamp(0.05, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primaryBlue,
                                      Colors.cyanAccent,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.cyanAccent.withValues(alpha: 0.6),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Footer Version & Architecture Badge
                  FadeTransition(
                    opacity: _textFade,
                    child: Column(
                      children: [
                        Text(
                          I18n.tr('splash_engine_badge'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'AllLiveSupport / YTDx Studio',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientGlowPainter extends CustomPainter {
  final Animation<double> pulse;

  _AmbientGlowPainter({required this.pulse}) : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.42);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF38BDF8).withValues(alpha: 0.08 + (pulse.value * 0.04)),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: 180 + pulse.value * 30));

    canvas.drawCircle(center, 180 + pulse.value * 30, paint);
  }

  @override
  bool shouldRepaint(covariant _AmbientGlowPainter oldDelegate) => true;
}
