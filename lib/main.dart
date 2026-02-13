import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart'; 

import 'package:nyantv/controllers/cacher/cache_controller.dart';
import 'package:nyantv/controllers/discord/discord_rpc.dart';
import 'package:nyantv/controllers/offline/offline_storage_controller.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:nyantv/controllers/services/anilist/anilist_auth.dart';
import 'package:nyantv/controllers/ui/greeting.dart';
import 'package:nyantv/controllers/theme.dart';
import 'package:nyantv/models/player/player_adaptor.dart';
import 'package:nyantv/models/ui/ui_adaptor.dart';
import 'package:nyantv/models/Offline/Hive/custom_list.dart';
import 'package:nyantv/models/Offline/Hive/offline_media.dart';
import 'package:nyantv/models/Offline/Hive/chapter.dart';
import 'package:nyantv/models/Offline/Hive/episode.dart';
import 'package:nyantv/models/Offline/Hive/offline_storage.dart';
import 'package:nyantv/models/Offline/Hive/video.dart';
import 'package:nyantv/screens/anime/home_page.dart';
import 'package:nyantv/screens/extensions/ExtensionScreen.dart';
import 'package:nyantv/screens/library/my_library.dart';
import 'package:nyantv/controllers/services/anilist/anilist_data.dart';
import 'package:nyantv/screens/home_page.dart';
import 'package:nyantv/screens/nyan_dvd.dart';
import 'package:nyantv/utils/deeplink.dart';
import 'package:nyantv/utils/logger.dart';
import 'package:nyantv/utils/register_protocol/register_protocol.dart';
import 'package:nyantv/widgets/adaptive_wrapper.dart';
import 'package:nyantv/widgets/animation/more_page_transitions.dart';
import 'package:nyantv/widgets/common/glow.dart';
import 'package:nyantv/widgets/common/navbar.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_titlebar.dart';
import 'package:nyantv/widgets/helper/platform_builder.dart';
import 'package:nyantv/widgets/non_widgets/settings_sheet.dart';
import 'package:nyantv/widgets/non_widgets/snackbar.dart';
import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:iconly/iconly.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:isar_community/isar.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:window_manager/window_manager.dart';

WebViewEnvironment? webViewEnvironment;
late Isar isar;
bool isAndroidTV = false;

final _isInExcludedScreen = false.obs;
final _isInDVDMode = false.obs;
Timer? _autoIdleTimer;

bool get isInDVDMode => _isInDVDMode.value;

void setExcludedScreen(bool excluded) {
  _isInExcludedScreen.value = excluded;
}

void setDVDMode(bool enabled) {
  _isInDVDMode.value = enabled;
}

void _resetAutoIdleTimer() {
  _autoIdleTimer?.cancel();
  
  try {
    final settings = Get.find<Settings>();
    final idleMinutes = settings.autoIdleMinutes;
    
    Logger.i('Auto-idle timer reset. Minutes: $idleMinutes, Excluded: ${_isInExcludedScreen.value}');
    
    if (idleMinutes <= 0) return;
    if (_isInExcludedScreen.value) return;
    
    _autoIdleTimer = Timer(Duration(minutes: idleMinutes), () {
      Logger.i('Auto-idle timer triggered! Going to DVD mode...');
      if (!_isInExcludedScreen.value) {
        setDVDMode(true);
        Get.to(() => const InitialisingScreen(
          child: FilterScreen(),
          dvdMode: true,
        ));
      }
    });
  } catch (e) {
    Logger.e('Auto-idle error: $e');
  }
}

class MyHttpoverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, String host, int port) => true;
  }
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus
      };
}

void main(List<String> args) async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    MediaKit.ensureInitialized();

    await Logger.init();
    await dotenv.load(fileName: ".env");

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      isAndroidTV = androidInfo.systemFeatures.contains('android.software.leanback');
    }

    if (Platform.isWindows) {
      ['dar', 'nyantv', 'sugoireads', 'mangayomi']
          .forEach(registerProtocolHandler);
    }
    initDeepLinkListener();
    HttpOverrides.global = MyHttpoverrides();
    await initializeHive();
    _initializeGetxController();
    initializeDateFormatting();
    if (!Platform.isAndroid && !Platform.isIOS) {
      await windowManager.ensureInitialized();
      await NyantvTitleBar.initialize();
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.transparent,
          statusBarColor: Colors.transparent,
          statusBarBrightness: Brightness.dark));
    }

    FlutterError.onError = (FlutterErrorDetails details) async {
      FlutterError.presentError(details);
      Logger.e("FLUTTER ERROR: ${details.exceptionAsString()}");
      Logger.e("STACK: ${details.stack}");
    };

    runApp(
      ChangeNotifierProvider(
        create: (context) => ThemeProvider(),
        child: const MyAdaptiveWrapper(child: MainApp()),
      ),
    );
  }, (error, stackTrace) async {
    Logger.e("CRASH: $error");
    if (error.toString().contains('PathAccessException: lock failed')) {
      Hive.deleteFromDisk();
      await Hive.initFlutter('NyanTV');
      Hive.deleteFromDisk();
    }
    Logger.e("STACK: $stackTrace");
  }, zoneSpecification: ZoneSpecification(
    print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
      Logger.i(line);
    },
  ));
}

void initDeepLinkListener() async {
  final appLinks = AppLinks();
  if (Platform.isLinux) return;

  try {
    final initialUri = await appLinks.getInitialLink();
    if (initialUri != null) Deeplink.handleDeepLink(initialUri);
  } catch (err) {
    errorSnackBar('Error getting initial deep link: $err');
  }

  appLinks.uriLinkStream.listen(
    (uri) => Deeplink.handleDeepLink(uri),
    onError: (err) => errorSnackBar('Error Opening link: $err'),
  );
}

Future<void> initializeHive() async {
  await Hive.initFlutter('NyanTV');
  Hive.registerAdapter(VideoAdapter());
  Hive.registerAdapter(TrackAdapter());
  Hive.registerAdapter(UISettingsAdapter());
  Hive.registerAdapter(PlayerSettingsAdapter());
  Hive.registerAdapter(OfflineStorageAdapter());
  Hive.registerAdapter(OfflineMediaAdapter());
  Hive.registerAdapter(CustomListAdapter());
  Hive.registerAdapter(ChapterAdapter());
  Hive.registerAdapter(EpisodeAdapter());
  await Hive.openBox('themeData');
  await Hive.openBox('loginData');
  await Hive.openBox('auth');
  await Hive.openBox('preferences');
  await Hive.openBox<UISettings>("UiSettings");
  await Hive.openBox<PlayerSettings>("PlayerSettings");
}

void _initializeGetxController() async {
  Get.put(OfflineStorageController());
  Get.put(AnilistAuth());
  Get.put(AnilistData());
  Get.put(DiscordRPCController());
  Get.put(SourceController());
  Get.put(Settings());
  Get.put(ServiceHandler());
  Get.put(GreetingController());
  Get.lazyPut(() => CacheController());
}

class UIScaleBypass extends InheritedWidget {
  final bool bypassScale;
  
  const UIScaleBypass({
    super.key,
    required this.bypassScale,
    required super.child,
  });

  static UIScaleBypass? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<UIScaleBypass>();
  }

  @override
  bool updateShouldNotify(UIScaleBypass oldWidget) {
    return bypassScale != oldWidget.bypassScale;
  }
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      child: Listener(
        onPointerDown: (_) => _resetAutoIdleTimer(),
        onPointerMove: (_) => _resetAutoIdleTimer(),
        onPointerHover: (_) => _resetAutoIdleTimer(),
        child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: (KeyEvent event) async {
            _resetAutoIdleTimer();
            
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                Get.back();
              } else if (event.logicalKey == LogicalKeyboardKey.f11) {
                bool isFullScreen = await windowManager.isFullScreen();
                NyantvTitleBar.setFullScreen(!isFullScreen);
              } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                final isAltPressed = HardwareKeyboard.instance.logicalKeysPressed
                        .contains(LogicalKeyboardKey.altLeft) ||
                    HardwareKeyboard.instance.logicalKeysPressed
                        .contains(LogicalKeyboardKey.altRight);
                if (isAltPressed) {
                  bool isFullScreen = await windowManager.isFullScreen();
                  NyantvTitleBar.setFullScreen(!isFullScreen);
                }
              }
            }
          },
          child: GetMaterialApp(
            scrollBehavior: MyCustomScrollBehavior(),
            debugShowCheckedModeBanner: false,
            title: "NyanTV",
            theme: theme.lightTheme,
            darkTheme: theme.darkTheme,
            themeMode: theme.isSystemMode
                ? ThemeMode.system
                : theme.isLightMode
                    ? ThemeMode.light
                    : ThemeMode.dark,
            home: const InitialisingScreen(child: FilterScreen()),
            builder: (context, child) {
              if (PlatformDispatcher.instance.views.length > 1) {
                return child!;
              }

              final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

              Widget finalChild = GetBuilder<Settings>(
                init: Get.find<Settings>(),
                builder: (settings) {
                  final scale = settings.uiScale;

                  if (scale <= 0.0 || scale > 3.0 || scale == 1.0) {
                    return UIScaleBypass(
                      bypassScale: false,
                      child: child!,
                    );
                  }

                  final originalSize = MediaQuery.of(context).size;
                  final scaledSize = Size(
                    originalSize.width / scale,
                    originalSize.height / scale,
                  );

                  return UIScaleBypass(
                    bypassScale: true,
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: scaledSize,
                        padding: EdgeInsets.zero,
                        viewInsets: EdgeInsets.zero,
                        viewPadding: EdgeInsets.zero,
                      ),
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.topLeft,
                        child: OverflowBox(
                          minWidth: 0,
                          maxWidth: double.infinity,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: scaledSize.width,
                            height: scaledSize.height,
                            child: child!,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );

              if (isDesktop) {
                return Stack(
                  children: [
                    finalChild,
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.transparent,
                        child: NyantvTitleBar.titleBar(),
                      ),
                    ),
                  ],
                );
              }

              return finalChild;
            },
            enableLog: true,
            logWriterCallback: (text, {isError = false}) async {
              Logger.d(text);
            },
          ),
        ),
      ),
    );
  }
}

class FilterScreen extends StatefulWidget {
  const FilterScreen({super.key});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  int _selectedIndex = 1;
  int _mobileSelectedIndex = 0;

  @override
  void initState() {
    super.initState();
    setExcludedScreen(false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetAutoIdleTimer();
    });

  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onMobileItemTapped(int index) {
    setState(() {
      _mobileSelectedIndex = index;
    });
  }

  final routes = [
    const SizedBox.shrink(),
    const HomePage(),
    const AnimeHomePage(),
    const MyLibrary(),
    const ExtensionScreen(disableGlow: true),
  ];

  final mobileRoutes = [
    const HomePage(),
    const AnimeHomePage(),
    const MyLibrary()
  ];

  @override
  void dispose() {
    _autoIdleTimer?.cancel();
    Logger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Get.find<ServiceHandler>();
    final isSimkl = false;
    return Glow(
      child: PlatformBuilder(
        strictMode: false,
        desktopBuilder: _buildDesktopLayout(context, authService, isSimkl),
        androidBuilder: isAndroidTV 
            ? _buildDesktopLayout(context, authService, isSimkl) 
            : _buildAndroidLayout(isSimkl),
      ),
    );
  }

  Scaffold _buildDesktopLayout(
      BuildContext context, ServiceHandler authService, bool isSimkl) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Provider.of<ThemeProvider>(context).isOled
          ? Colors.black
          : Colors.transparent,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Obx(() => SizedBox(
                width: 120,
                child: SuperListView(
                  children: [
                    ResponsiveNavBar(
                      isDesktop: true,
                      currentIndex: _selectedIndex,
                      margin: const EdgeInsets.fromLTRB(20, 30, 15, 10),
                      items: [
                        NavItem(
                            unselectedIcon: IconlyBold.profile,
                            selectedIcon: IconlyBold.profile,
                            onTap: (index) {
                              return SettingsSheet.show(context);
                            },
                            label: 'Profile',
                            altIcon: CircleAvatar(
                                radius: 24,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainer
                                    .withValues(alpha: 0.3),
                                child: authService.isLoggedIn.value
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(59),
                                        child: CachedNetworkImage(
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          errorWidget: (context, url, error) =>
                                              const Icon(IconlyBold.profile),
                                          imageUrl: authService
                                                  .profileData.value.avatar ??
                                              ''),
                                      )
                                    : const Icon((IconlyBold.profile)))),
                        NavItem(
                          unselectedIcon: IconlyLight.home,
                          selectedIcon: IconlyBold.home,
                          onTap: _onItemTapped,
                          label: 'Home',
                        ),
                        NavItem(
                          unselectedIcon: Icons.movie_filter_outlined,
                          selectedIcon: Icons.movie_filter_rounded,
                          onTap: _onItemTapped,
                          label: 'Anime',
                        ),
                        NavItem(
                          unselectedIcon: HugeIcons.strokeRoundedLibrary,
                          selectedIcon: HugeIcons.strokeRoundedLibrary,
                          onTap: _onItemTapped,
                          label: 'Library',
                        ),
                        if (sourceController.shouldShowExtensions.value)
                          NavItem(
                            unselectedIcon: Icons.extension_outlined,
                            selectedIcon: Icons.extension_rounded,
                            onTap: _onItemTapped,
                            label: "Extensions",
                          ),
                      ],
                    ),
                  ],
                ))),
          Expanded(
              child: SmoothPageEntrance(
                  style: PageEntranceStyle.slideUpGentle,
                  key: Key(_selectedIndex.toString()),
                  child: routes[_selectedIndex])),
        ],
      ),
    );
  }

  Scaffold _buildAndroidLayout(bool isSimkl) {
    return Scaffold(
        body: SmoothPageEntrance(
            style: PageEntranceStyle.slideUpGentle,
            key: Key(_mobileSelectedIndex.toString()),
            child: mobileRoutes[_mobileSelectedIndex]),
        extendBody: true,
        bottomNavigationBar: ResponsiveNavBar(
          isDesktop: false,
          currentIndex: _mobileSelectedIndex,
          margin: const EdgeInsets.symmetric(vertical: 40, horizontal: 40),
          items: [
            NavItem(
              unselectedIcon: IconlyBold.home,
              selectedIcon: IconlyBold.home,
              onTap: _onMobileItemTapped,
              label: 'Home',
            ),
            NavItem(
              unselectedIcon: Icons.movie_filter_rounded,
              selectedIcon: Icons.movie_filter_rounded,
              onTap: _onMobileItemTapped,
              label: 'Anime',
            ),
            NavItem(
              unselectedIcon: HugeIcons.strokeRoundedLibrary,
              selectedIcon: HugeIcons.strokeRoundedLibrary,
              onTap: _onMobileItemTapped,
              label: 'Library',
            ),
          ],
        ));
  }
}