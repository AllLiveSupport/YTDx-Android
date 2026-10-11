import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'providers/player_provider.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'widgets/sidebar.dart';
import 'widgets/player_bar.dart';
import 'widgets/unified_bottom_dock.dart';
import 'services/playlist_manager.dart';
import 'services/share_intent_service.dart';
import 'models/download_task.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_handler.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/downloads_screen.dart';
import 'screens/playlists_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';

YTDxAudioHandler? _globalAudioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid || Platform.isIOS) {
    // Initialize audio_service — this creates the real foreground service
    // that works on lock screen, HyperOS, MIUI, etc.
    _globalAudioHandler = await AudioService.init(
      builder: () => YTDxAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.alllivesupport.ytdxstudio.channel.audio',
        androidNotificationChannelName: 'YTDx Müzik Oynatıcı',
        androidNotificationChannelDescription: 'YTDx Studio Müzik Oynatıcı ve Kilit Ekranı',
        // ongoing: true makes Stop action appear as X dismiss button in notification
        androidNotificationOngoing: true,
        // When paused, allow swiping away the notification (stops service)
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'drawable/ic_stat_music',
        androidShowNotificationBadge: false,
        notificationColor: Color(0xFF1976D2),
        androidNotificationClickStartsActivity: true,
      ),
    );
  }

  await PlaylistManager.instance.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => PlayerProvider(audioHandler: _globalAudioHandler)),
        ChangeNotifierProvider.value(value: PlaylistManager.instance),
      ],
      child: const AuraApp(),
    ),
  );
}

class AuraApp extends StatelessWidget {
  const AuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeModeStr = context.select<AppState, String>((s) => s.settings.themeMode);

    ThemeMode mode;
    if (themeModeStr == 'light') {
      mode = ThemeMode.light;
    } else if (themeModeStr == 'dark') {
      mode = ThemeMode.dark;
    } else {
      mode = ThemeMode.system;
    }

    return MaterialApp(
      title: 'YTDx Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      home: const SplashScreen(),
    );
  }
}

// Global helper: is this a mobile/compact device?
bool isMobileDevice(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  return width < 720 || Platform.isAndroid || Platform.isIOS;
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycleListener;

  static const List<Widget> _screens = [
    HomeScreen(),
    SearchScreen(),
    DownloadsScreen(),
    PlaylistsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final status = await Permission.notification.status;
          if (!status.isGranted) {
            await Permission.notification.request();
          }
        } catch (_) {}

        // Listen for shared YouTube URLs from external apps
        ShareIntentService.init(callback: (sharedUrl) async {
          if (!mounted) return;
          final appState = context.read<AppState>();

          if (sharedUrl.contains('list=') || sharedUrl.contains('playlist')) {
            // 📥 Playlist Shared: Paste into Playlist Tab and scan playlist
            appState.loadPlaylist(sharedUrl);
            appState.setTabIndex(3);
          } else {
            // 🎬 Video Shared: Paste into Search Tab, search & show video card
            appState.search(sharedUrl);
            appState.setTabIndex(1);
          }
        });
      });
    }
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        PlayerProvider.cleanupAllAudioProcesses();
        return AppExitResponse.exit;
      },
      onDetach: () {
        PlayerProvider.cleanupAllAudioProcesses();
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycleListener.dispose();
    PlayerProvider.cleanupAllAudioProcesses();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached || state == AppLifecycleState.hidden) {
      PlayerProvider.cleanupAllAudioProcesses();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTabIndex = context.select<AppState, int>((s) => s.currentTabIndex);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = isMobileDevice(context);
    final activeDownloadsCount = context.select<AppState, int>(
      (s) => s.tasks.where((t) => t.status != DownloadStatus.completed).length,
    );

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: SafeArea(
        bottom: false, // NavigationBar handles bottom insets itself
        child: Column(
          children: [
            // Main Body: Sidebar (Desktop) + Active Screen
            Expanded(
              child: Row(
                children: [
                  // Fixed Left Modern Sidebar (Desktop only)
                  if (!isMobile) const Sidebar(),

                  // Active Page Content with smooth animated fade
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey<int>(currentTabIndex),
                        child: _screens[currentTabIndex],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Desktop Media Player Bar
            if (!isMobile) const PlayerBar(),

            // Mobile Unified Docked Player + Navigation Bar
            if (isMobile)
              UnifiedBottomDock(
                selectedIndex: currentTabIndex,
                onItemSelected: (index) => context.read<AppState>().setTabIndex(index),
                activeDownloadsCount: activeDownloadsCount,
              ),
          ],
        ),
      ),
    );
  }
}
