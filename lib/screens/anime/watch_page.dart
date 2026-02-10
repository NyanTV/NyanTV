// ignore_for_file: invalid_use_of_protected_member
// lib/screens/anime/watch_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:nyantv/screens/anime/widgets/media_indicator_old.dart';
import 'package:nyantv/utils/logger.dart';
import 'dart:io';
import 'package:nyantv/controllers/service_handler/params.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/models/Offline/Hive/video.dart' as model;
import 'package:nyantv/constants/contants.dart';
import 'package:nyantv/controllers/offline/offline_storage_controller.dart';
import 'package:nyantv/models/player/player_adaptor.dart';
import 'package:nyantv/controllers/settings/methods.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:nyantv/models/Media/media.dart' as nyantv;
import 'package:nyantv/models/Offline/Hive/episode.dart';
import 'package:nyantv/screens/anime/widgets/episode_watch_screen.dart';
import 'package:nyantv/screens/anime/widgets/video_slider.dart';
import 'package:nyantv/screens/settings/sub_settings/settings_player.dart';
import 'package:nyantv/utils/color_profiler.dart';
import 'package:nyantv/utils/shaders.dart';
import 'package:nyantv/utils/string_extensions.dart';
import 'package:nyantv/widgets/common/checkmark_tile.dart';
import 'package:nyantv/widgets/common/glow.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_titlebar.dart';
import 'package:nyantv/widgets/helper/platform_builder.dart';
import 'package:nyantv/widgets/helper/tv_wrapper.dart';
import 'package:nyantv/screens/anime/watch/controller/tv_remote_handler.dart';
import 'package:nyantv/widgets/custom_widgets/custom_button.dart';
import 'package:nyantv/widgets/custom_widgets/custom_text.dart';
import 'package:nyantv/widgets/custom_widgets/custom_textspan.dart';
import 'package:nyantv/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart' as d;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_progress.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:iconsax/iconsax.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:outlined_text/outlined_text.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:nyantv/utils/aniskip.dart' as aniskip;
import 'package:nyantv/utils/tv_scroll_mixin.dart';
import 'package:nyantv/controllers/discord/discord_rpc.dart';
import 'package:nyantv/main.dart';

class WatchPage extends StatefulWidget {
  final model.Video episodeSrc;
  final Episode currentEpisode;
  final List<Episode> episodeList;
  final nyantv.Media anilistData;
  final List<model.Video> episodeTracks;
  final bool shouldTrack;
  const WatchPage(
      {super.key,
      required this.episodeSrc,
      required this.episodeList,
      required this.anilistData,
      required this.currentEpisode,
      this.shouldTrack = true,
      required this.episodeTracks});

  @override
  State<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage> with TickerProviderStateMixin, TVScrollMixin {
  late Rx<model.Video> episode;
  late Rx<Episode> currentEpisode;
  late RxList<model.Video> episodeTracks;
  late RxList<Episode> episodeList;
  late Rx<nyantv.Media> anilistData;
  RxList<model.Track?> subtitles = <model.Track>[].obs;

  final offlineStorage = Get.find<OfflineStorageController>();
  late ServicesType mediaService;
  late DiscordRPCController discordRPC;

  late Player player;
  late VideoController playerController;
  final isPlaying = true.obs;
  final currentPosition = const Duration(milliseconds: 0).obs;
  final episodeDuration = const Duration(minutes: 24).obs;
  final formattedTime = "00:00".obs;
  final formattedDuration = "24:00".obs;
  final showControls = true.obs;
  final isBuffering = true.obs;
  final bufferred = const Duration(milliseconds: 0).obs;
  final playbackSpeed = 1.0.obs;
  final isFullscreen = false.obs;
  final selectedSubIndex = (-1).obs;
  final selectedAudioIndex = 0.obs;
  final settings = Get.find<Settings>();
  final RxString resizeMode = "Cover".obs;
  late PlayerSettings playerSettings;
  late FocusNode _keyboardListenerFocusNode;
  aniskip.EpisodeSkipTimes? skipTimes;
  final isOPSkippedOnce = false.obs;
  final isEDSkippedOnce = false.obs;

  final RxBool _volumeIndicator = false.obs;
  final RxBool _brightnessIndicator = false.obs;
  Timer? _volumeTimer;
  Timer? _brightnessTimer;
  var _volumeInterceptEventStream = false;
  final RxDouble _volumeValue = 0.0.obs;
  final RxDouble _brightnessValue = 0.0.obs;
  late AnimationController _leftAnimationController;
  late AnimationController _rightAnimationController;
  RxInt skipDuration = 10.obs;
  final isLocked = false.obs;
  RxList<String> subtitleText = [''].obs;
  RxInt subtitleDelay = 0.obs;
  FocusNode? _lastControlsFocusNode;

  final doubleTapLabel = 0.obs;
  Timer? doubleTapTimeout;
  final isLeftSide = false.obs;
  Timer? _hideControlsTimer;
  final pressed2x = false.obs;

  final sourceController = Get.find<SourceController>();
  final isEpisodeDialogOpen = false.obs;
  late bool isLoggedIn;
  final leftOriented = true.obs;
  late TVRemoteHandler? _tvRemoteHandler;

  Timer? _discordUpdateTimer;
  bool _isUpdatingDiscord = false;
  DateTime? _lastDiscordUpdate;
  final _minUpdateInterval = const Duration(seconds: 2);

  final currentVisualProfile = 'natural'.obs;
  RxMap<String, int> customSettings = <String, int>{}.obs;

  bool get isMobile => !settings.isTV.value && (Platform.isAndroid || Platform.isIOS);

  void applySavedProfile() => ColorProfileManager()
      .applyColorProfile(currentVisualProfile.value, player);


  void navigateToNextEpisode() {
    if (playerSettings.autoSkipFiller) {
      final targetEpisode = _getNextNonFillerEpisode();
      if (targetEpisode != null) {
        _switchToEpisode(targetEpisode);
      } else if (_hasNextEpisode()) {
        _switchToEpisode(_getNextEpisode()!);
      }
    } else {
      if (_hasNextEpisode()) {
        _switchToEpisode(_getNextEpisode()!);
      }
    }
  }

  bool _hasNextEpisode() {
    return currentEpisode.value.number.toInt() < episodeList.value.last.number.toInt();
  }

  Episode? _getNextEpisode() {
    final currentIndex = episodeList.value.indexOf(currentEpisode.value);
    return currentIndex < episodeList.value.length - 1 
        ? episodeList.value[currentIndex + 1] 
        : null;
  }

  Episode? _getNextNonFillerEpisode() {
    final currentIndex = episodeList.value.indexOf(currentEpisode.value);
    int skippedCount = 0;
    
    for (int i = currentIndex + 1; i < episodeList.value.length; i++) {
      final episode = episodeList.value[i];
      if (episode.filler != true) {
        if (skippedCount > 0) {
          snackBar('Skipped $skippedCount filler episode${skippedCount > 1 ? 's' : ''}');
        }
        return episode;
      }
      skippedCount++;
    }
    return _getNextEpisode();
  }

  Future<void> _switchToEpisode(Episode episode) async {
    isSwitchingEpisode = true;
    
    trackEpisode(currentPosition.value, episodeDuration.value, currentEpisode.value);
    
    setState(() {
      player.open(Media(''));
    });
    
    currentEpisode.value = episode;
    final resp = await sourceController.activeSource.value!.methods
        .getVideoList(d.DEpisode(
            episodeNumber: episode.number, url: episode.link));
    final video = resp.map((e) => model.Video.fromVideo(e)).toList();
    final preferredStream = video.firstWhere(
      (e) => e.quality == this.episode.value.quality,
      orElse: () {
        snackBar("Preferred Stream Not Found, Selecting ${video[0].quality}");
        return video[0];
      },
    );

    this.episode.value = preferredStream;
    episodeTracks.value = video;
    currentEpisode.value.source = sourceController.activeSource.value!.name;
    currentEpisode.value.currentTrack = preferredStream;
    currentEpisode.value.videoTracks = video;
    
    _initPlayer(false);
    
    _waitForPlayerReady().then((_) {
      if (mounted) {
        isSwitchingEpisode = false;
        Logger.i('Episode switched, updating Discord presence...');
        _scheduleDiscordUpdate(isPaused: false);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    initTVScroll();
    final settings = Get.find<Settings>();
    mediaService = widget.anilistData.serviceType;
    discordRPC = DiscordRPCController.instance;
    
    if (settings.isTV.value) {
      resizeMode.value = "Contain";
      final tempDir = Directory.systemTemp;
      if (tempDir.existsSync()) {
        final cacheDir = Directory('${tempDir.path}/nyantv_cache');
        if (!cacheDir.existsSync()) {
          cacheDir.createSync(recursive: true);
        }
      }
      
      settings.preferences.put('shaders_enabled', false);
    }
    _initOrientations();
    _leftAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _rightAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    skipTimes = null;
    _initRxVariables();
    _initHiveVariables();
    _initPlayer(true);
    _attachListeners();
    applySavedProfile();
    if (isMobile) {
      _handleVolumeAndBrightness();
    }
    if (widget.currentEpisode.number.toInt() > 1) {
      final episodeNum = widget.currentEpisode.number.toInt() - 1;
      trackAnilistAndLocal(episodeNum, widget.currentEpisode);
    }
    _keyboardListenerFocusNode = FocusNode(
      canRequestFocus: !settings.isTV.value,
      skipTraversal: settings.isTV.value,
    );
    
  ever(showControls, (controlsVisible) {
    if (settings.isTV.value) {
      if (controlsVisible) {
        if (_keyboardListenerFocusNode.hasFocus) {
          _keyboardListenerFocusNode.unfocus();
        }
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted && _lastControlsFocusNode != null && _lastControlsFocusNode!.canRequestFocus) {
            _lastControlsFocusNode!.requestFocus();
          }
        });
      } else {
        final currentFocus = FocusScope.of(context).focusedChild;
        if (currentFocus != null && currentFocus != _keyboardListenerFocusNode) {
          _lastControlsFocusNode = currentFocus;
        }
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && !_keyboardListenerFocusNode.hasFocus) {
            FocusScope.of(context).requestFocus(_keyboardListenerFocusNode);
          }
        });
      }
    }
  });
    
    ever(isBuffering, (buffering) {
      if (showControls.value && !buffering) {
        _startHideControlsTimer();
        if (!settings.isTV.value) {
          _keyboardListenerFocusNode.requestFocus();
        }
      }
    });
    
    if (settings.isTV.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && !showControls.value) {
              FocusScope.of(context).requestFocus(_keyboardListenerFocusNode);
            }
          });
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_keyboardListenerFocusNode.hasFocus) {
          _keyboardListenerFocusNode.requestFocus();
        }
      });
    }
    
    if (settings.isTV.value) {
      _tvRemoteHandler = TVRemoteHandler(
        player: player,
        context: context,
        seekDuration: settings.seekDuration,
        onSeek: (duration) {
          player.seek(duration);
          currentPosition.value = duration;
          formattedTime.value = formatDuration(duration);
        },
        onToggleMenu: () {
          toggleControls();
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              if (showControls.value) {
                if (_keyboardListenerFocusNode.hasFocus) {
                  _keyboardListenerFocusNode.unfocus();
                }
              } else {
                FocusScope.of(context).requestFocus(_keyboardListenerFocusNode);
              }
            }
          });
        },
        onExitPlayer: () => Get.back(),
        getCurrentPosition: () => currentPosition.value,
        getVideoDuration: () => episodeDuration.value,
        isMenuVisible: () => showControls.value,
        isLocked: () => isLocked.value,
        onPlayPause: () => player.playOrPause(),
        onNextEpisode: () {
          if (currentEpisode.value.number.toInt() < episodeList.value.last.number.toInt()) {
            isSwitchingEpisode = true;
            player.pause().then((_) => fetchEpisode(false));
          }
        },
        onPreviousEpisode: () {
          if (currentEpisode.value.number.toInt() > 1) {
            isSwitchingEpisode = true;
            player.pause().then((_) => fetchEpisode(true));
          }
        },
        onSkipSegments: (isLeft) => _skipSegments(isLeft),
        onMenuInteraction: () => _startHideControlsTimer(),
      );
    }
  }

  void _scheduleDiscordUpdate({bool isPaused = false}) {
    _discordUpdateTimer?.cancel();
    
    if (_isUpdatingDiscord) {
      Logger.i('Discord update already in progress, skipping...');
      return;
    }
    
    if (_lastDiscordUpdate != null) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastDiscordUpdate!);
      if (timeSinceLastUpdate < _minUpdateInterval) {
        Logger.i('Discord update too soon, waiting...');
        final waitTime = _minUpdateInterval - timeSinceLastUpdate;
        _discordUpdateTimer = Timer(waitTime, () {
          _performDiscordUpdate(isPaused: isPaused);
        });
        return;
      }
    }
    
    _discordUpdateTimer = Timer(const Duration(milliseconds: 300), () {
      _performDiscordUpdate(isPaused: isPaused);
    });
  }

  Future<void> _waitForPlayerReady() async {
    int attempts = 0;
    while (attempts < 30) {
      if (episodeDuration.value.inMilliseconds > 0 && 
          currentEpisode.value.durationInMilliseconds != null &&
          currentEpisode.value.durationInMilliseconds! > 0) {
        await Future.delayed(const Duration(milliseconds: 300));
        Logger.i('Player ready check passed: Duration=${episodeDuration.value.inSeconds}s, Episode Duration=${currentEpisode.value.durationInMilliseconds}ms');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }
    Logger.i('Warning: Player ready timeout after ${attempts * 200}ms - proceeding anyway');
  }

  Future<void> _performDiscordUpdate({bool isPaused = false}) async {
    
    if (_isUpdatingDiscord) {
      Logger.i('Skipping Discord update - already updating');
      return;
    }
    
    if (episodeDuration.value.inMilliseconds == 0) {
      Logger.i('Skipping Discord update - duration not ready yet (episodeDuration=0)');
      return;
    }
    
    _isUpdatingDiscord = true;
    _lastDiscordUpdate = DateTime.now();
    
    try {
      final totalEps = episodeList.isNotEmpty 
          ? 'Total: ${episodeList.length} Episodes' 
          : '';
      
      Logger.i('=== DISCORD UPDATE START ===');
      Logger.i('Episode: ${currentEpisode.value.number}, Paused: $isPaused');
      Logger.i('Position: ${currentPosition.value.inSeconds}s / ${episodeDuration.value.inSeconds}s');
      Logger.i('Episode Duration (ms): ${currentEpisode.value.durationInMilliseconds}');
      Logger.i('Episode Position (ms): ${currentEpisode.value.timeStampInMilliseconds}');
      Logger.i('Discord Connected: ${discordRPC.isConnected}');
      
      if (isPaused) {
        Logger.i('Calling updateAnimePresencePaused...');
        await discordRPC.updateAnimePresencePaused(
          anime: anilistData.value,
          episode: currentEpisode.value,
          totalEpisodes: totalEps,
        );
      } else {
        Logger.i('Calling updateAnimePresence...');
        await discordRPC.updateAnimePresence(
          anime: anilistData.value,
          episode: currentEpisode.value,
          totalEpisodes: totalEps,
        );
      }
      
      Logger.i('=== DISCORD UPDATE SUCCESS ===');
    } catch (e, stackTrace) {
      Logger.i('=== DISCORD UPDATE FAILED ===');
      Logger.i('Error: $e');
      Logger.i('Stack: $stackTrace');
    } finally {
      _isUpdatingDiscord = false;
    }
  }

  void _initOrientations() async {
    if (!settings.isTV.value) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (settings.defaultPortraitMode) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      } else {
        final orientation = await _getClosestLandscapeOrientation();
        SystemChrome.setPreferredOrientations([orientation]);
      }
    }
  }

  Future<DeviceOrientation> _getClosestLandscapeOrientation() async {
    final event = await accelerometerEvents.first;

    double angle = math.atan2(event.y, event.x) * 180 / math.pi;

    if (angle < 0) angle += 360;

    if (angle >= 0 && angle < 180) {
      return DeviceOrientation.landscapeLeft;
    } else {
      return DeviceOrientation.landscapeRight;
    }
  }

  Future<void> trackEpisode(
      Duration position, Duration duration, Episode currentEpisode,
      {bool updateAL = true}) async {
    final percentageCompletion =
        (position.inMilliseconds / episodeDuration.value.inMilliseconds) * 100;

    bool crossed = percentageCompletion >= settings.markAsCompleted;
    final epNum = crossed
        ? currentEpisode.number.toInt()
        : currentEpisode.number.toInt() - 1;
    await trackAnilistAndLocal(epNum, currentEpisode, updateAL: updateAL);
  }

  Future<void> trackAnilistAndLocal(int epNum, Episode currentEpisode,
      {bool updateAL = true}) async {
    final temp = mediaService.onlineService.animeList
        .firstWhereOrNull((e) => e.id == anilistData.value.id);
    offlineStorage.addOrUpdateAnime(
        widget.anilistData, widget.episodeList, currentEpisode);
    offlineStorage.addOrUpdateWatchedEpisode(
        widget.anilistData.id, currentEpisode);
    if (currentEpisode.number.toInt() > ((temp?.episodeCount) ?? '1').toInt()) {
      if (updateAL && widget.shouldTrack) {
        await mediaService.onlineService.updateListEntry(UpdateListEntryParams(
            listId: anilistData.value.id,
            progress: epNum,
            isAnime: true,
            syncIds: [widget.anilistData.idMal]));
        mediaService.onlineService
            .setCurrentMedia(anilistData.value.id.toString());
      }
    }
  }

  PlayerConfiguration getPlayerConfig(bool shadersEnabled) {
    final settings = Get.find<Settings>();
    if (settings.isTV.value) {
      return const PlayerConfiguration(
        options: {
          "vo": "gpu",
          "hwdec": "no",
          "gpu-context": "android",
          "cache": "yes",
          "cache-secs": "30",
        },
        bufferSize: 32 * 1024 * 1024,
      );
    }
    
    if (shadersEnabled) {
      return const PlayerConfiguration();
    }

    return const PlayerConfiguration();
  }

void _initPlayer(bool firstTime) async {
    final areShadersEnabled =
        settings.preferences.get('shaders_enabled', defaultValue: false);
    Episode? savedEpisode = offlineStorage.getWatchedEpisode(
        widget.anilistData.id, currentEpisode.value.number);
    
    int startTimeMilliseconds =
        (savedEpisode?.number ?? 0) == currentEpisode.value.number
            ? savedEpisode?.timeStampInMilliseconds ?? 0
            : 0;
    
    final bool hasInitialSeek = startTimeMilliseconds > 0;
    
    if (firstTime) {
      player = Player(
        configuration: getPlayerConfig(areShadersEnabled),
      );
      if (settings.isTV.value) {
        playerController = VideoController(player,
            configuration: const VideoControllerConfiguration(
              androidAttachSurfaceAfterVideoParameters: false,
              enableHardwareAcceleration: false,
            ));
      } else {
        playerController = VideoController(player,
            configuration: const VideoControllerConfiguration(
                androidAttachSurfaceAfterVideoParameters: true));
      }
    } else {
      currentPosition.value = Duration.zero;
      episodeDuration.value = Duration.zero;
      bufferred.value = Duration.zero;
    }
    
    player.open(Media(episode.value.url,
        httpHeaders: episode.value.headers ??
            {'Referer': sourceController.activeSource.value?.baseUrl ?? ''}));
    
    await _performInitialSeek(startTimeMilliseconds);
    
    _initSubs();
    player.setRate(prevRate.value);
    isOPSkippedOnce.value = false;
    isEDSkippedOnce.value = false;
    
    final skipQuery = aniskip.SkipSearchQuery(
        idMAL: widget.anilistData.idMal,
        episodeNumber: currentEpisode.value.number);
    aniskip.AniSkipApi().getSkipTimes(skipQuery).then((skipTimeResult) {
      skipTimes = skipTimeResult;
    }).onError((error, stackTrace) {
      debugPrint("An error occurred: $error");
      debugPrint("Stack trace: $stackTrace");
    });
    
    if (areShadersEnabled) {
      final key = (PlayerShaders.getShaders()
          .indexWhere((e) => e == settings.selectedShader));
      setShaders(key, showMessage: false);
    }

    if (firstTime) {
      StreamSubscription? initSub;
      bool discordUpdateHandled = false;
      
      initSub = player.stream.duration.listen((duration) {
        if (duration.inMilliseconds > 0 && !discordUpdateHandled) {
          discordUpdateHandled = true;
          Logger.i('Player ready with duration: ${duration.inSeconds}s');
          initSub?.cancel();
          
          _waitForPlayerReady().then((_) {
            if (mounted) {
              if (!hasInitialSeek) {
                _waitForBufferingAfterSeek().then((_) {
                  if (mounted && !isSwitchingEpisode) {
                    Logger.i('Player fully ready (no initial seek), performing Discord update...');
                    isSwitchingEpisode = false;
                    _performDiscordUpdate(isPaused: false);
                  }
                });
              } else {
                isSwitchingEpisode = false;
                Logger.i('Initial seek completed, Discord already updated');
              }
            }
          });
        }
      });
      
      Future.delayed(const Duration(seconds: 10), () {
        if (!discordUpdateHandled && mounted) {
          Logger.i('Duration stream timeout, forcing Discord update');
          discordUpdateHandled = true;
          initSub?.cancel();
          isSwitchingEpisode = false;
          if (!hasInitialSeek) {
            _performDiscordUpdate(isPaused: false);
          }
        }
      });
    }
  }

  StreamSubscription? _initialSeekSubscription;
  bool _hasPerformedInitialSeek = false;

  Future<void> _performInitialSeek(int startTimeMilliseconds) async {
    if (startTimeMilliseconds <= 0) {
      Logger.i('No initial seek needed, starting from beginning');
      _hasPerformedInitialSeek = true;
      return;
    }
    
    Logger.i('Setting up initial seek to: ${startTimeMilliseconds}ms');
    _hasPerformedInitialSeek = false;
    _initialSeekSubscription?.cancel();
    
    final completer = Completer<void>();
    
    StreamSubscription? durationSub;
    StreamSubscription? bufferSub;
    bool durationReady = false;
    bool bufferReady = false;
    
    void trySeek() async {
      if (durationReady && bufferReady && !_hasPerformedInitialSeek) {
        _hasPerformedInitialSeek = true;
        durationSub?.cancel();
        bufferSub?.cancel();
        
        final seekPosition = Duration(milliseconds: startTimeMilliseconds);
        
        await Future.delayed(const Duration(milliseconds: 300));
        
        if (mounted) {
          Logger.i('Performing initial seek to: ${seekPosition.inSeconds}s');
          player.seek(seekPosition);
          
          await Future.delayed(const Duration(milliseconds: 500));
          
          if (mounted && currentPosition.value.inMilliseconds < startTimeMilliseconds - 1000) {
            Logger.i('Seek verification failed, retrying...');
            player.seek(seekPosition);
            await Future.delayed(const Duration(milliseconds: 500));
          }
          
          Logger.i('Initial seek completed');
          
          if (mounted) {
            await _waitForBufferingAfterSeek();
            Logger.i('Initial seek done, triggering Discord update');
            _performDiscordUpdate(isPaused: false);
          }
          
          completer.complete();
        }
      }
    }
    
    durationSub = player.stream.duration.listen((duration) {
      if (duration.inMilliseconds > 0) {
        durationReady = true;
        Logger.i('Duration ready: ${duration.inSeconds}s');
        trySeek();
      }
    });
    
    bufferSub = player.stream.buffer.listen((buffer) {
      if (buffer.inMilliseconds > startTimeMilliseconds || 
          buffer.inMilliseconds > 3000) {
        bufferReady = true;
        Logger.i('Buffer ready: ${buffer.inSeconds}s');
        trySeek();
      }
    });
    
    Future.delayed(const Duration(milliseconds: 7500), () {
      if (!_hasPerformedInitialSeek && mounted) {
        Logger.i('Initial seek timeout, forcing seek');
        _hasPerformedInitialSeek = true;
        durationSub?.cancel();
        bufferSub?.cancel();
        player.seek(Duration(milliseconds: startTimeMilliseconds));
        
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        });
      }
    });

    return completer.future;
  }

  int lastProcessedMinute = 0;
  bool isSwitchingEpisode = false;
  StreamSubscription<Duration>? _positionSubscription;
  bool _isSeeking = false;
  bool _isManualSeeking = false;
  int lastProcessedSecond = -1;
  Duration _lastPosition = Duration.zero;
  DateTime _lastUIUpdate = DateTime.now();

  void _attachListeners() {
    _positionSubscription = player.stream.position.listen((e) {
      if (_isSeeking) return;

      if (_lastPosition.inSeconds != e.inSeconds) {
        _lastPosition = e;
        currentEpisode.value.timeStampInMilliseconds = e.inMilliseconds;

        if (e.inSeconds % 30 == 0 && isPlaying.value && !isSwitchingEpisode) {
          trackEpisode(e, episodeDuration.value, currentEpisode.value);
        }

        if (isPlaying.value && skipTimes != null && !isSwitchingEpisode) {
          _handleAutoSkip();
        }
      }

      final now = DateTime.now();
      if (mounted && now.difference(_lastUIUpdate).inMilliseconds >= 1000) {
        _lastUIUpdate = now;
        currentPosition.value = e;
        formattedTime.value = formatDuration(e);
        Logger.i('UI Updated with accurate stream position: ${e.inSeconds}s');
      }

      if (e.inSeconds >= episodeDuration.value.inSeconds - 1) {
        if (!isSwitchingEpisode && episodeDuration.value.inMinutes >= 1) {
          isSwitchingEpisode = true;
          Future.delayed(const Duration(milliseconds: 500), () {
            navigateToNextEpisode();
          });
        }
      }
    });

    player.stream.playing.listen((e) {
      isPlaying.value = e;

      if (e) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            isSwitchingEpisode = false;
          }
        });
      }
      
      if (!_isManualSeeking) {
        _scheduleDiscordUpdate(isPaused: !e);
      }
    });

    player.stream.duration.listen((e) {
      episodeDuration.value = e;
      currentEpisode.value.durationInMilliseconds = e.inMilliseconds;
      formattedDuration.value = formatDuration(e);
    });

    playerController.player.stream.buffering.listen((e) {
      isBuffering.value = e;
    });

    player.stream.buffer.listen((e) {
      bufferred.value = e;
    });

    player.stream.rate.listen((e) {
      playbackSpeed.value = e;
    });

    player.stream.subtitle.listen((e) {
      subtitleText.value = e;
    });
  }

  void startSeeking() {
    _isSeeking = true;
  }

  void endSeeking(Duration position) {
    currentPosition.value = position;
    formattedTime.value = formatDuration(position);
    currentEpisode.value.timeStampInMilliseconds = position.inSeconds * 1000;

    _isSeeking = false;
  }

  void _initRxVariables() {
    episode = Rx<model.Video>(widget.episodeSrc);
    episodeList = RxList<Episode>(widget.episodeList);
    anilistData = Rx<nyantv.Media>(widget.anilistData);
    currentEpisode = Rx<Episode>(widget.currentEpisode);
    currentEpisode.value.source = sourceController.activeSource.value!.name;
    episodeTracks = RxList<model.Video>(widget.episodeTracks);
    currentEpisode.value.currentTrack = episode.value;
    currentEpisode.value.videoTracks = episodeTracks;
  }

  void _initSubs() async {
    subtitles.clear();
    selectedSubIndex.value = 0;
    player.setSubtitleTrack(SubtitleTrack.no());
    final List<String> labels = [];

    for (var e in episodeTracks) {
      final subs = e.subtitles;
      if (subs != null) {
        for (var s in subs) {
          if (!labels.contains(s.label)) {
            subtitles.add(s);
            labels.add(s.label ?? '');
          }
        }
      }
    }
    for (var i in subtitles.value) {
      if ((i?.label?.toLowerCase().contains('english') ??
              i?.label?.toLowerCase().contains('eng') ??
              false) &&
          i?.file != null) {
        final index = subtitles.indexOf(i);
        selectedSubIndex.value = index;
        await player.setSubtitleTrack(SubtitleTrack.uri(i!.file!));
        break;
      }
    }
  }

  void _initHiveVariables() {
    playerSettings = settings.playerSettings.value;
    resizeMode.value = settings.resizeMode;
    isLoggedIn = mediaService.onlineService.isLoggedIn.value;
    skipDuration.value = settings.seekDuration;
    prevRate.value = playerSettings.speed;
    currentVisualProfile.value = settings.preferences
        .get('currentVisualProfile', defaultValue: 'natural');
    customSettings.value = (settings.preferences
            .get('currentVisualSettings', defaultValue: {}) as Map)
        .cast<String, int>();
  }

  final Map<int, String> _durationCache = <int, String>{};

  String formatDuration(Duration duration) {
    final key = duration.inSeconds;
    if (_durationCache.containsKey(key)) {
      return _durationCache[key]!;
    }

    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    final result =
        duration.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';

    if (_durationCache.length > 100) {
      _durationCache.clear();
    }

    _durationCache[key] = result;
    return result;
  }

  String extractQuality(String quality) {
    final extractedQuality =
        quality.split(" ").firstWhere((e) => e.contains("p"));
    return extractedQuality;
  }

  Episode? navEpisode(bool prev) {
    if (prev) {
      final episode = episodeList.firstWhereOrNull((e) =>
          e.number == (currentEpisode.value.number.toInt() - 1).toString());
      return episode;
    } else {
      final episode = episodeList.firstWhereOrNull((e) =>
          e.number == (currentEpisode.value.number.toInt() + 1).toString());
      return episode;
    }
  }

  Future<void> fetchEpisode(bool prev) async {
    trackEpisode(
        currentPosition.value, episodeDuration.value, currentEpisode.value);
    
    isSwitchingEpisode = true;
    
    setState(() {
      player.open(Media(''));
    });
    
    final episodeToNav = navEpisode(prev);
    if (episodeToNav == null) {
      snackBar("No Streams Found");
      isSwitchingEpisode = false;
      return;
    }
    
    currentEpisode.value = episodeToNav;
    final resp = await sourceController.activeSource.value!.methods
        .getVideoList(d.DEpisode(
            episodeNumber: episodeToNav.number, url: episodeToNav.link));
    final video = resp.map((e) => model.Video.fromVideo(e)).toList();
    final preferredStream = video.firstWhere(
      (e) => e.quality == episode.value.quality,
      orElse: () {
        snackBar("Preferred Stream Not Found, Selecting ${video[0].quality}");
        return video[0];
      },
    );

    episode.value = preferredStream;
    episodeTracks.value = video;
    currentEpisode.value.source = sourceController.activeSource.value!.name;
    currentEpisode.value.currentTrack = preferredStream;
    currentEpisode.value.videoTracks = video;
    
    _initPlayer(false);
    
    _waitForPlayerReady().then((_) {
      if (mounted) {
        isSwitchingEpisode = false;
        Logger.i('Episode switched, updating Discord presence...');
        _scheduleDiscordUpdate(isPaused: false);
      }
    });
  }

  Future<void> setVolume(double value) async {
    try {
      VolumeController.instance.setVolume(value);
    } catch (_) {}
    _volumeValue.value = value;
    _volumeIndicator.value = true;
    _volumeInterceptEventStream = true;
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        _volumeIndicator.value = false;
        _volumeInterceptEventStream = false;
      }
    });
  }

  Future<void> setBrightness(double value) async {
    try {
      await ScreenBrightness.instance.setScreenBrightness(value);
    } catch (_) {}
    setState(() {
      _brightnessIndicator.value = true;
      _brightnessTimer?.cancel();
      _brightnessTimer = Timer(const Duration(milliseconds: 200), () {
        if (mounted) {
          _brightnessIndicator.value = false;
        }
      });
    });
  }

  void _handleVolumeAndBrightness() {
    Future.microtask(() async {
      try {
        VolumeController.instance.showSystemUI = false;
        _volumeValue.value = await VolumeController.instance.getVolume();
        VolumeController.instance.addListener((value) {
          if (mounted && !_volumeInterceptEventStream) {
            _volumeValue.value = value;
          }
        });
      } catch (_) {}
    });
    Future.microtask(() async {
      try {
        _brightnessValue.value = await ScreenBrightness.instance.current;
        ScreenBrightness.instance.onCurrentBrightnessChanged.listen((value) {
          if (mounted) {
            _brightnessValue.value = value;
          }
        });
      } catch (_) {}
    });
  }

  void _handleDoubleTap(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final tapPosition = details.globalPosition;
    final isLeft = tapPosition.dx < screenWidth / 2;
    _skipSegments(isLeft);
  }

  void _skipSegments(bool isLeft) {
    _isManualSeeking = true;
    
    player.pause();
    if (isLeftSide.value != isLeft) {
      doubleTapLabel.value = 0;
      skipDuration.value = 0;
    }

    isLeftSide.value = isLeft;
    doubleTapLabel.value += settings.seekDuration;
    skipDuration.value += settings.seekDuration;

    final currentSeconds = currentPosition.value.inSeconds;
    final maxSeconds = episodeDuration.value.inSeconds;

    final newSeekPosition = isLeft
        ? (currentSeconds - skipDuration.value).clamp(0, maxSeconds)
        : (currentSeconds + skipDuration.value).clamp(0, maxSeconds);

    formattedTime.value = formatDuration(Duration(seconds: newSeekPosition));
    player.seek(Duration(seconds: newSeekPosition));

    if (isLeft) {
      _leftAnimationController.forward(from: 0);
    } else {
      _rightAnimationController.forward(from: 0);
    }

    doubleTapTimeout?.cancel();
    doubleTapTimeout = Timer(const Duration(milliseconds: 800), () {
      _leftAnimationController.reset();
      _rightAnimationController.reset();
      doubleTapLabel.value = 0;
      skipDuration.value = 0;
      
      player.play();

      _waitForBufferingAfterSeek().then((_) {
        _isManualSeeking = false;
        if (mounted && !isSwitchingEpisode) {
          Logger.i('DoubleTap skip complete, updating Discord');
          _scheduleDiscordUpdate(isPaused: false);
        }
      });
    });
  }

  Future<void> _waitForBufferingAfterSeek() async {
    if (!isPlaying.value) return;
    
    int attempts = 0;
    const maxAttempts = 75;
    
    while (isBuffering.value && attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }
    
    await Future.delayed(const Duration(milliseconds: 200));
    
    Logger.i('Buffering complete after seek (${attempts * 100}ms)');
  }

  void _megaSkip(bool invert) {
    _isManualSeeking = true;
    
    if (invert) {
      final duration = Duration(
          seconds: currentPosition.value.inSeconds - settings.skipDuration);
      if (duration.inMilliseconds < 0) {
        currentPosition.value = const Duration(milliseconds: 0);
        player.seek(const Duration(seconds: 0));
      } else {
        currentPosition.value = duration;
        player.seek(duration);
      }
    } else {
      final duration = Duration(
          seconds: currentPosition.value.inSeconds + settings.skipDuration);
      currentPosition.value = duration;
      player.seek(duration);
    }

    _waitForBufferingAfterSeek().then((_) {
      _isManualSeeking = false;
      if (mounted && !isSwitchingEpisode && isPlaying.value) {
        Logger.i('MegaSkip complete, updating Discord');
        _scheduleDiscordUpdate(isPaused: false);
      }
    });
  }

  void _handleAutoSkip() {
    if (skipTimes?.op != null && playerSettings.autoSkipOP) {
      if (playerSettings.autoSkipOnce && isOPSkippedOnce.value) {
        return;
      }
      if (currentPosition.value.inSeconds > skipTimes!.op!.start &&
          currentPosition.value.inSeconds < skipTimes!.op!.end) {
        final skipNeeded = skipTimes!.op!.end - currentPosition.value.inSeconds;
        final duration =
            Duration(seconds: currentPosition.value.inSeconds + skipNeeded);
        currentPosition.value = duration;
        player.seek(duration);
        isOPSkippedOnce.value = true;
      }
    }
    if (skipTimes?.ed != null && playerSettings.autoSkipED) {
      if (playerSettings.autoSkipOnce && isEDSkippedOnce.value) {
        return;
      }
      if (currentPosition.value.inSeconds > skipTimes!.ed!.start &&
          currentPosition.value.inSeconds < skipTimes!.ed!.end) {
        final skipNeeded = skipTimes!.ed!.end - currentPosition.value.inSeconds;
        final duration =
            Duration(seconds: currentPosition.value.inSeconds + skipNeeded);
        currentPosition.value = duration;
        player.seek(duration);
        isEDSkippedOnce.value = true;
      }
    }
  }

  void toggleControls({bool? val}) {
    showControls.value = val ?? !showControls.value;

    if (showControls.value) {
      if (isPlaying.value) {
        _startHideControlsTimer();
      }
    }
  }

  void _startHideControlsTimer() {
    if (!isPlaying.value) {
      _hideControlsTimer?.cancel();
      return;
    }
    _hideControlsTimer?.cancel();

    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (isPlaying.value) {
        showControls.value = false;
      }
    });
  }

  @override
  void dispose() {
    _volumeTimer?.cancel();
    _brightnessTimer?.cancel();
    _hideControlsTimer?.cancel();
    doubleTapTimeout?.cancel();
    _positionSubscription?.cancel();
    _discordUpdateTimer?.cancel();
    _initialSeekSubscription?.cancel();
    disposeTVScroll();

    trackEpisode(
        currentPosition.value, episodeDuration.value, currentEpisode.value,
        updateAL: false);

    if (mounted) {
      try {
        discordRPC.updateMediaPresence(media: anilistData.value);
      } catch (e) {
        Logger.i('Discord update on dispose failed (expected on app close): $e');
      }
    }

    player.dispose();
    _leftAnimationController.dispose();
    _rightAnimationController.dispose();

    if (isMobile && !settings.isTV.value) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      ScreenBrightness.instance.resetScreenBrightness();
    } else {
      if (!isMobile) {
        NyantvTitleBar.setFullScreen(false);
      }
    }
    _tvRemoteHandler?.dispose();
    _tvRemoteHandler = null;
    _keyboardListenerFocusNode.dispose();
    super.dispose();
  }

  void setShaders(int key, {bool showMessage = true}) async {
    if (key == -1) {
      PlayerShaders.setShaders(player, '');
      if (showMessage) {
        snackBar("Cleared Shaders");
      }
      return;
    }
    final shaders = PlayerShaders.getShaders();
    PlayerShaders.setShaders(player, shaders[key]);
    if (showMessage) {
      snackBar('Applied ${shaders[key]}');
    }
  }

  KeyEventResult handlePlayerKeyEvent(FocusNode node, KeyEvent e) {
    if (settings.isTV.value) {
     return _tvRemoteHandler!.handleKeyEvent(node, e);
    }

    if (e is! KeyDownEvent) return KeyEventResult.ignored;

    final key = e.logicalKey;

    if (key == LogicalKeyboardKey.space) {
      player.playOrPause();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _skipSegments(true);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _skipSegments(false);
    } else if (key == LogicalKeyboardKey.period || e.character == '>') {
      _megaSkip(false);
    } else if (key == LogicalKeyboardKey.comma || e.character == '<') {
      _megaSkip(true);
    } else if (key == LogicalKeyboardKey.escape) {
      Get.back();
      return KeyEventResult.handled;
    }

    if (settings.preferences.get('shaders_enabled', defaultValue: false)) {
      final keyLabel = key.keyLabel;
      final allowedKeys = ["1", "2", "3", "4", "5", "6", "0"];
      if (allowedKeys.contains(keyLabel)) {
        setShaders(int.parse(keyLabel) - 1);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final canFocus = settings.isTV.value 
          ? !showControls.value
          : true;
      
      return Focus(
        focusNode: _keyboardListenerFocusNode,
        autofocus: !settings.isTV.value,
        canRequestFocus: canFocus,
        skipTraversal: settings.isTV.value && showControls.value,
        onKeyEvent: (node, event) {
          return handlePlayerKeyEvent(node, event);
        },
        child: PopScope(
          canPop: false,
          onPopInvoked: (didPop) {
            if (didPop) return;
            if (settings.isTV.value && showControls.value) {
              toggleControls(val: false);
            } else {
              if (widget.shouldTrack) {
                discordRPC.updateMediaPresence(media: anilistData.value);
              }
              Get.back();
            }
          },
          child: Scaffold(
            body: Stack(
              alignment: Alignment.center,
              children: [
                _buildPlayer(context),
                _buildOverlay(context),
                _buildControls(),
                _buildSubtitle(),
                _buildRippleEffect(),
                _build2xThingy(),
                if (isMobile && settings.enableSwipeControls) ...[
                  _buildBrightnessSlider(),
                  _buildVolumeSlider(),
                ],
                Obx(() => isBuffering.value && !showControls.value
                    ? _buildBufferingIndicator()
                    : const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      );
    });
  }

  Obx _build2xThingy() {
    return Obx(() {
      if (pressed2x.value) {
        return Positioned(
            top: 30,
            child: Container(
              width: 80,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  NyantvText(
                    text: "${(prevRate.value * 2).toInt()}x",
                    variant: TextVariant.semiBold,
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.fast_forward)
                ],
              ),
            ));
      } else {
        return const SizedBox.shrink();
      }
    });
  }

  Obx _buildPlayer(BuildContext context) {
    return Obx(() {
      if (settings.isTV.value) {
        return _buildTVPlayer(context);
      }
      
      return Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: isEpisodeDialogOpen.value
                ? Get.width *
                    getResponsiveSize(context,
                        mobileSize: 0.6, desktopSize: 0.7, isStrict: true)
                : Get.width,
            child: Video(
              controller: playerController,
              controls: null,
              fit: resizeModes[resizeMode.value] ?? BoxFit.cover,
              subtitleViewConfiguration: const SubtitleViewConfiguration(
                visible: false,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: isEpisodeDialogOpen.value
                ? Get.width *
                    getResponsiveSize(context,
                        mobileSize: 0.4, desktopSize: 0.3, isStrict: true)
                : 0,
            child: Focus(
              focusNode: FocusNode(
                  canRequestFocus: isEpisodeDialogOpen.value,
                  skipTraversal: !isEpisodeDialogOpen.value,
                  descendantsAreFocusable: isEpisodeDialogOpen.value,
                  descendantsAreTraversable: isEpisodeDialogOpen.value),
              child: EpisodeWatchScreen(
                episodeList: episodeList.value,
                anilistData: anilistData.value,
                currentEpisode: currentEpisode.value,
                onEpisodeSelected: (src, streamList, selectedEpisode) {
                  episode.value = src;
                  episodeTracks.value = streamList;
                  currentEpisode.value = selectedEpisode;
                  _initPlayer(false);
                },
              ),
            ),
          )
        ],
      );
    });
  }

  final prevRate = 1.0.obs;

  Obx _buildOverlay(BuildContext context) {
    return Obx(
      () => AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          left: 0,
          top: 0,
          bottom: 0,
          right: isEpisodeDialogOpen.value
              ? Get.width *
                  getResponsiveSize(context,
                      mobileSize: 0.4, desktopSize: 0.3, isStrict: true)
              : 0,
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (e) {
                pressed2x.value = true;
                player.setRate(prevRate.value * 2);
              },
              onLongPressEnd: (e) {
                pressed2x.value = false;
                player.setRate(prevRate.value);
              },
              onTap: () {
                if (settings.isTV.value) {
                  if (!_keyboardListenerFocusNode.hasFocus && !showControls.value) {
                    FocusScope.of(context).requestFocus(_keyboardListenerFocusNode);
                  }
                  
                  if (!showControls.value) {
                    toggleControls(val: true);
                  } else {
                    toggleControls(val: false);
                  }
                } else {
                  toggleControls();
                }
              },
              onDoubleTapDown: (e) => _handleDoubleTap(e),
              onVerticalDragUpdate: (e) async {
                if (isMobile && settings.enableSwipeControls) {
                  final screenHeight = MediaQuery.of(context).size.height;
                  final topBoundary = screenHeight * 0.2;
                  final bottomBoundary = screenHeight * 0.8;

                  final position = e.localPosition;
                  if (position.dy >= topBoundary &&
                      position.dy <= bottomBoundary) {
                    final delta = e.delta.dy;

                    if (position.dx <= MediaQuery.of(context).size.width / 2) {
                      final brightness = _brightnessValue - delta / 500;
                      final result = brightness.clamp(0.0, 1.0);
                      setBrightness(result.toDouble());
                    } else {
                      final volume = _volumeValue - delta / 500;
                      final result = volume.clamp(0.0, 1.0);
                      setVolume(result.toDouble());
                    }
                  }
                }
              },
              child: AnimatedOpacity(
                curve: Curves.easeInOut,
                duration: const Duration(milliseconds: 300),
                opacity: showControls.value ? 1 : 0,
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                ),
              ),
            )),
    );
  }

  Widget _buildVolumeSlider() {
    return Obx(() => AnimatedOpacity(
          curve: Curves.easeInOut,
          opacity: _volumeIndicator.value ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: MediaIndicatorBuilder(
            value: _volumeValue.value,
            isVolumeIndicator: true,
          ),
        ));
  }

  Widget _buildBrightnessSlider() {
    return Obx(() => AnimatedOpacity(
          curve: Curves.easeInOut,
          opacity: _brightnessIndicator.value ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: MediaIndicatorBuilder(
            value: _brightnessValue.value,
            isVolumeIndicator: false,
          ),
        ));
  }

  Obx _buildSubtitle() {
    return Obx(() => AnimatedPositioned(
          right: 0,
          left: 0,
          top: 0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          bottom: showControls.value ? 100 : (30 + settings.bottomMargin),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedOpacity(
              opacity: subtitleText[0].isEmpty ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: subtitleText[0].isEmpty
                      ? Colors.transparent
                      : colorOptions[settings.subtitleBackgroundColor],
                  borderRadius: BorderRadius.circular(12.multiplyRadius()),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeIn,
                  switchOutCurve: Curves.easeOut,
                  child: OutlinedText(
                    text: Text(
                      [
                        for (final line in subtitleText)
                          if (line.trim().isNotEmpty) line.trim(),
                      ].join('\n'),
                      key: ValueKey(subtitleText.join()),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: fontColorOptions[settings.subtitleColor],
                        fontSize: settings.subtitleSize.toDouble(),
                        fontFamily: "Poppins-Bold",
                      ),
                    ),
                    strokes: [
                      OutlinedTextStroke(
                          color:
                              fontColorOptions[settings.subtitleOutlineColor]!,
                          width: settings.subtitleOutlineWidth.toDouble())
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
  }

  Widget _buildRippleEffect() {
    return Obx(() {
      if (doubleTapLabel.value == 0) {
        return const SizedBox();
      }
      return AnimatedPositioned(
        left: isLeftSide.value ? 0 : MediaQuery.of(context).size.width / 1.5,
        width: MediaQuery.of(context).size.width / 2.5,
        top: 0,
        bottom: 0,
        duration: const Duration(milliseconds: 1000),
        child: AnimatedBuilder(
          animation: isLeftSide.value
              ? _leftAnimationController
              : _rightAnimationController,
          builder: (context, child) {
            final scale = Tween<double>(begin: 1.5, end: 1).animate(
              CurvedAnimation(
                parent: isLeftSide.value
                    ? _leftAnimationController
                    : _rightAnimationController,
                curve: Curves.easeInOut,
              ),
            );

            return GestureDetector(
              onDoubleTapDown: (t) => _handleDoubleTap(t),
              child: Opacity(
                opacity: 1.0 -
                    (isLeftSide.value
                        ? _leftAnimationController.value
                        : _rightAnimationController.value),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isLeftSide.value ? 0 : 100),
                      topRight: Radius.circular(isLeftSide.value ? 100 : 0),
                      bottomLeft: Radius.circular(isLeftSide.value ? 0 : 100),
                      bottomRight: Radius.circular(isLeftSide.value ? 100 : 0),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: scale,
                        child: Icon(
                          isLeftSide.value
                              ? Icons.fast_rewind_rounded
                              : Icons.fast_forward_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Text(
                          "${doubleTapLabel.value}s",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }

  void playerSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      clipBehavior: Clip.antiAlias,
      isScrollControlled: true,
      builder: (context) {
        return Wrap(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: const SettingsPlayer(isModal: true),
              ),
            ),
          ],
        );
      },
    );
  }

  showAudioSelector() {
    showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (context) {
          return SuperListView(
            padding: const EdgeInsets.all(20.0),
            children: [
              const Center(
                child: NyantvText(
                  text: "Choose Audio",
                  size: 18,
                  variant: TextVariant.bold,
                ),
              ),
              const SizedBox(height: 10),
              episode.value.audios != null
                  ? const SizedBox.shrink()
                  : SuperListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: episode.value.audios?.length ?? 0,
                      itemBuilder: (context, index) {
                        final e = episode.value.audios![index];
                        final isSelected = selectedAudioIndex.value == index;
                        return GestureDetector(
                          onTap: () {
                            selectedAudioIndex.value = index;
                            player.setAudioTrack(AudioTrack.uri(e.file!,
                                language: e.label ?? '??'));
                            Get.back();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5.0),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 2.5, horizontal: 10),
                              title: NyantvText(
                                text: e.label ?? '??',
                                variant: TextVariant.bold,
                                size: 16,
                                color: isSelected
                                    ? Colors.black
                                    : Theme.of(context).colorScheme.primary,
                              ),
                              tileColor: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainer,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              trailing: Icon(
                                Iconsax.music,
                                color: isSelected
                                    ? Colors.black
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ],
          );
        });
  }

  showTrackSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Center(
                  child: NyantvText(
                    text: "Choose Track",
                    size: 18,
                    variant: TextVariant.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: episodeTracks.map((e) {
                    final isSelected = episode.value.quality == e.quality;
                    return NyantvOnTap(
                      onTap: () {
                        episode.value = e;
                        player.open(Media(
                          e.url,
                          start: currentPosition.value,
                          end: episodeDuration.value,
                          httpHeaders: episode.value.headers ??
                              {
                                'Referer': sourceController
                                    .activeSource.value!.baseUrl!
                              },
                        ));
                        Get.back();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5.0),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 2.5, horizontal: 10),
                          title: NyantvText(
                            text: e.quality,
                            variant: TextVariant.bold,
                            size: 16,
                            color: isSelected
                                ? Colors.black
                                : Theme.of(context).colorScheme.primary,
                          ),
                          tileColor: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surfaceContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          trailing: Icon(
                            Iconsax.play5,
                            color: isSelected
                                ? Colors.black
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void showSubtitleSelector() {
    showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        isScrollControlled: true,
        builder: (context) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                const Center(
                  child: NyantvText(
                    text: "Choose Subtitle",
                    size: 18,
                    variant: TextVariant.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NyantvOnTap(
                      onTap: () {
                        selectedSubIndex.value = -1;
                        Get.back();
                        player.setSubtitleTrack(SubtitleTrack.no());
                      },
                      child: subtitleTile("None", Iconsax.subtitle5,
                          selectedSubIndex.value == -1),
                    ),
                    ...subtitles.asMap().entries.map((entry) {
                      final index = entry.key;
                      final e = entry.value;
                      return NyantvOnTap(
                        onTap: () {
                          selectedSubIndex.value = index;
                          Get.back();
                          player.setSubtitleTrack(SubtitleTrack.uri(e!.file!));
                        },
                        child: subtitleTile(e?.label ?? 'None',
                            Iconsax.subtitle5, selectedSubIndex.value == index),
                      );
                    }),
                    NyantvOnTap(
                      onTap: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: extensions,
                        );

                        if (result?.files.single.path != null) {
                          final file = result!.files.single;
                          final filePath = file.path!;
                          selectedSubIndex.value = subtitles.length + 1;
                          subtitles.add(
                              model.Track(file: filePath, label: file.name));
                          Get.back();
                          player.setSubtitleTrack(
                            SubtitleTrack(filePath, file.name, file.name,
                                uri: false, data: false),
                          );
                        } else {
                          snackBar('No subtitle file selected.',
                              duration: 2000);
                        }
                      },
                      child: subtitleTile("Add Subtitle", Iconsax.add,
                          selectedSubIndex.value == subtitles.length + 1),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
  }

  Widget subtitleTile(String text, IconData icon, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(vertical: 2.5, horizontal: 10),
        title: NyantvText(
          text: text,
          variant: TextVariant.bold,
          size: 16,
          color:
              isSelected ? Colors.black : Theme.of(context).colorScheme.primary,
        ),
        tileColor: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        trailing: Icon(icon,
            color: isSelected
                ? Colors.black
                : Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Color _getFgColor() {
    return settings.playerStyle == 0
        ? Colors.white
        : Theme.of(context).colorScheme.primary;
  }

  Widget _buildControls() {
    return Obx(() {
      final themeFgColor = _getFgColor().obs;

      return AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        left: 0,
        top: 0,
        bottom: 0,
        right: isEpisodeDialogOpen.value
            ? Get.width *
                getResponsiveSize(context,
                    mobileSize: 0.4, desktopSize: 0.3, isStrict: true)
            : 0,
        child: IgnorePointer(
          ignoring: !showControls.value,
          child: AnimatedOpacity(
            curve: Curves.easeInOut,
            opacity: showControls.value ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      transform: Matrix4.identity()
                        ..translate(0.0, showControls.value ? 0.0 : -100.0),
                      padding: EdgeInsets.symmetric(
                          vertical: 15.0,
                          horizontal: isEpisodeDialogOpen.value ? 0 : 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isLocked.value) ...[
                            BlurWrapper(
                              child: IconButton(
                                  onPressed: () {
                                    Get.back();
                                  },
                                  icon: const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      color: Colors.white)),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: getResponsiveSize(context,
                                  mobileSize: Get.width * 0.3,
                                  desktopSize: isEpisodeDialogOpen.value
                                      ? Get.width * 0.3
                                      : (Get.width * 0.6)),
                              padding: const EdgeInsets.only(top: 3.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  NyantvText(
                                    text:
                                        'Episode ${currentEpisode.value.number}: ${currentEpisode.value.title}',
                                    variant: TextVariant.semiBold,
                                    maxLines: 3,
                                    color: themeFgColor.value,
                                  ),
                                  NyantvText(
                                    text: anilistData.value.title.toUpperCase(),
                                    variant: TextVariant.bold,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const Spacer(),
                          BlurWrapper(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (!isLocked.value) ...[
                                  _buildIcon(
                                      onTap: () {
                                        isEpisodeDialogOpen.value =
                                            !isEpisodeDialogOpen.value;
                                        if (MediaQuery.of(context)
                                                .orientation ==
                                            Orientation.portrait) {
                                          isEpisodeDialogOpen.value = false;
                                          showModalBottomSheet(
                                              context: context,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20)),
                                              clipBehavior: Clip.antiAlias,
                                              builder: (context) {
                                                return EpisodeWatchScreen(
                                                  episodeList:
                                                      episodeList.value,
                                                  anilistData:
                                                      anilistData.value,
                                                  currentEpisode:
                                                      currentEpisode.value,
                                                  onEpisodeSelected: (src,
                                                      streamList,
                                                      selectedEpisode) {
                                                    episode.value = src;
                                                    episodeTracks.value =
                                                        streamList;
                                                    currentEpisode.value =
                                                        selectedEpisode;
                                                    _initPlayer(false);
                                                    isEpisodeDialogOpen.value =
                                                        false;
                                                  },
                                                );
                                              });
                                        }
                                      },
                                      icon: HugeIcons.strokeRoundedFolder03),
                                  _buildIcon(
                                      onTap: () {
                                        showPlaybackSpeedDialog(context);
                                      },
                                      icon: HugeIcons.strokeRoundedClock01),
                                ],
                                _buildIcon(
                                    onTap: () {
                                      isLocked.value = !isLocked.value;
                                    },
                                    icon: isLocked.value
                                        ? Icons.lock
                                        : Icons.lock_open),
              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      transform: Matrix4.identity()
                        ..translate(0.0, showControls.value ? 0.0 : 100.0),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              NyantvTextSpans(
                                maxLines: 1,
                                spans: [
                                  NyantvTextSpan(
                                      text: '${formattedTime.value} ',
                                      variant: TextVariant.semiBold,
                                      color:
                                          themeFgColor.value.withOpacity(0.8)),
                                  NyantvTextSpan(
                                    variant: TextVariant.semiBold,
                                    text: ' /  ${formattedDuration.value}',
                                  ),
                                ],
                              ),
                              if (!isLocked.value) _buildSkipButton(false),
                            ],
                          ),
                          IgnorePointer(
                            ignoring: isLocked.value,
                            child: SizedBox(
                              height: 27,
                              child: VideoSliderTheme(
                                  color: themeFgColor.value,
                                  inactiveTrackColor:
                                      _getBgColor().withOpacity(0.1),
                                  child: Slider(
                                    focusNode: FocusNode(
                                        canRequestFocus: false,
                                        skipTraversal: true),
                                    min: 0,
                                    value: currentPosition.value.inMilliseconds
                                        .toDouble(),
                                    max: (currentPosition.value.inMilliseconds >
                                                episodeDuration
                                                    .value.inMilliseconds
                                            ? currentPosition
                                                .value.inMilliseconds
                                            : episodeDuration
                                                .value.inMilliseconds)
                                        .toDouble(),
                                    secondaryTrackValue: bufferred
                                        .value.inMilliseconds
                                        .toDouble(),
                                    onChangeStart: (_) {
                                      startSeeking();
                                      _isManualSeeking = true;
                                    },
                                    onChangeEnd: (val) async {
                                      if (episodeDuration.value.inMilliseconds.toDouble() != 0.0) {
                                        final newPosition = Duration(milliseconds: val.toInt());
                                        player.seek(newPosition);
                                        endSeeking(newPosition);
                                        
                                        await _waitForBufferingAfterSeek();
                                        
                                        _isManualSeeking = false;
                                        if (mounted && !isSwitchingEpisode && isPlaying.value) {
                                          Logger.i('Slider seek complete, updating Discord');
                                          _scheduleDiscordUpdate(isPaused: false);
                                        }
                                      }
                                    },
                                    onChanged: (val) {
                                      if (episodeDuration.value.inMilliseconds
                                              .toDouble() !=
                                          0.0) {
                                        currentPosition.value =
                                            Duration(milliseconds: val.toInt());
                                        formattedTime.value = formatDuration(
                                            currentPosition.value);
                                      }
                                    },
                                  )),
                            ),
                          ),
                          const SizedBox(height: 5),
                          if (!isLocked.value)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                BlurWrapper(
                                  child: Row(
                                    children: [
                                      _buildIcon(
                                          onTap: () {
                                            playerSettingsSheet(context);
                                          },
                                          icon: HugeIcons
                                              .strokeRoundedSettings01),
                                      _buildIcon(
                                          onTap: () {
                                            showTrackSelector();
                                          },
                                          icon: HugeIcons
                                              .strokeRoundedFolderVideo),
                                      _buildIcon(
                                          onTap: () {
                                            showSubtitleSelector();
                                          },
                                          icon:
                                              HugeIcons.strokeRoundedSubtitle),
                                      if (episode.value.audios != null &&
                                          episode.value.audios!.isNotEmpty)
                                        _buildIcon(
                                            onTap: () {
                                              showAudioSelector();
                                            },
                                            icon: HugeIcons
                                                .strokeRoundedMusicNote01),
                                    ],
                                  ),
                                ),
                                BlurWrapper(
                                  child: Row(
                                    children: [
                                      if (Platform.isAndroid ||
                                          Platform.isIOS) ...[
                                        _buildIcon(
                                            onTap: () async {
                                              SystemChrome
                                                  .setPreferredOrientations([
                                                DeviceOrientation.portraitUp,
                                              ]);
                                            },
                                            icon: Icons.phone_android),
                                        _buildIcon(
                                            onTap: () async {
                                              leftOriented.value =
                                                  !leftOriented.value;
                                              if (!leftOriented.value) {
                                                SystemChrome
                                                    .setPreferredOrientations([
                                                  DeviceOrientation
                                                      .landscapeLeft,
                                                ]);
                                              } else {
                                                SystemChrome
                                                    .setPreferredOrientations([
                                                  DeviceOrientation
                                                      .landscapeRight,
                                                ]);
                                              }
                                            },
                                            icon: Icons.screen_rotation),
                                      ],
                                      _buildIcon(
                                          onTap: () =>
                                              showColorProfileSheet(context),
                                          icon: Icons.hdr_on_rounded),
                                      _buildIcon(
                                          onTap: () {
                                            final newIndex =
                                                (resizeModeList.indexOf(
                                                            resizeMode.value) +
                                                        1) %
                                                    resizeModeList.length;
                                            resizeMode.value =
                                                resizeModeList[newIndex];
                                          },
                                          icon: Icons.aspect_ratio_rounded),
                                      if (!Platform.isAndroid &&
                                          !Platform.isIOS)
                                        _buildIcon(
                                            onTap: () async {
                                              isFullscreen.value =
                                                  !isFullscreen.value;
                                              await NyantvTitleBar
                                                  .setFullScreen(
                                                      isFullscreen.value);
                                            },
                                            icon: !isFullscreen.value
                                                ? Icons.fullscreen
                                                : Icons
                                                    .fullscreen_exit_rounded),
                                    ],
                                  ),
                                ),
                              ],
                            )
                        ],
                      ),
                    )
                  ],
                ),
                if (!isLocked.value) ...[_buildPlaybackButtons()],
                if (settings.isTV.value)
                  Positioned(
                      right: 10,
                      top: MediaQuery.of(context).size.height * 0.48,
                      child: _buildIcon(icon: Icons.arrow_back_ios))
              ],
            ),
          ),
        ),
      );
    });
  }

  _buildSkipButton(bool invert) {
    return BlurWrapper(
      borderRadius: BorderRadius.circular(20.multiplyRoundness()),
      child: NyanTVButton(
        height: 50,
        width: 120,
        variant: ButtonVariant.simple,
        borderRadius: BorderRadius.circular(20.multiplyRoundness()),
        backgroundColor: Colors.transparent,
        onTap: () async {
          _isManualSeeking = true;
          
          if (invert) {
            final duration = Duration(
                seconds:
                    currentPosition.value.inSeconds - settings.skipDuration);
            if (duration.inMilliseconds < 0) {
              currentPosition.value = const Duration(milliseconds: 0);
              player.seek(const Duration(seconds: 0));
            } else {
              currentPosition.value = duration;
              player.seek(duration);
            }
          } else {
            final duration = Duration(
                seconds:
                    currentPosition.value.inSeconds + settings.skipDuration);
            currentPosition.value = duration;
            player.seek(duration);
          }
          
          await _waitForBufferingAfterSeek();
          _isManualSeeking = false;
          if (mounted && !isSwitchingEpisode && isPlaying.value) {
            Logger.i('Skip button complete, updating Discord');
            _scheduleDiscordUpdate(isPaused: false);
          }
        },
        child: invert
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.fast_rewind_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 5),
                  NyantvText(
                    text: "-${settings.skipDuration}s",
                    variant: TextVariant.semiBold,
                    color: Colors.white,
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  NyantvText(
                    text: "+${settings.skipDuration}s",
                    variant: TextVariant.semiBold,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.fast_forward_rounded,
                    color: Colors.white,
                  )
                ],
              ),
      ),
    );
  }

  void showPlaybackSpeedDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: getResponsiveValue(context,
                mobileValue: null, desktopValue: 500.0),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Playback Speed',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: SuperListView.builder(
                    shrinkWrap: true,
                    itemCount: cursedSpeed.length,
                    itemBuilder: (context, index) {
                      final e = cursedSpeed[index];

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0),
                        child: _buildSpeedOption(
                            context, player, e, playbackSpeed.value),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpeedOption(BuildContext context, Player playerController,
      double speed, double currentSpeed) {
    return ListTileWithCheckMark(
      active: speed == currentSpeed,
      leading: const Icon(Icons.speed),
      onTap: () {
        prevRate.value = speed;
        player.setRate(speed);
        Navigator.of(context).pop();
      },
      title: '${speed.toStringAsFixed(2)}x',
      color: Theme.of(context).colorScheme.primary,
    );
  }

  Color _getPlayFgColor() {
    return settings.playerStyle == 0
        ? Colors.white
        : Theme.of(context).colorScheme.onPrimary;
  }

  Color _getBgColor() {
    return settings.playerStyle == 0
        ? Colors.transparent
        : Theme.of(context).colorScheme.primary;
  }

  Widget _buildPlaybackButtons() {
    final themeFgColor = _getPlayFgColor().obs;
    final themeBgColor = _getBgColor().obs;

    return Positioned.fill(
      child: AnimatedContainer(
        transform: Matrix4.identity()
          ..translate(0.0, showControls.value ? 0.0 : 50.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: Alignment.center,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            _buildPlaybackButton(
              icon: Icons.skip_previous_rounded,
              color: currentEpisode.value.number.toInt() <= 1
                  ? Colors.grey[800]
                  : Colors.white,
              onTap: () async {
                if (currentEpisode.value.number.toInt() <= 1) {
                  snackBar(
                      "You're trying to rewind? You haven't even made it past the intro.");
                } else {
                  isSwitchingEpisode = true;
                  player.pause().then((_) {
                    fetchEpisode(true);
                  });
                }
              },
            ),
            Obx(
              () => isBuffering.value
                  ? _buildBufferingIndicator()
                  : buildPlayButton(
                      isPlaying: isPlaying,
                      color: themeBgColor.value,
                      iconColor: themeFgColor.value,
                    ),
            ),
            _buildPlaybackButton(
              icon: Icons.skip_next_rounded,
              color: currentEpisode.value.number.toInt() >=
                      episodeList.value.last.number.toInt()
                  ? Colors.grey[800]
                  : Colors.white,
              onTap: () async {
                if (currentEpisode.value.number.toInt() >=
                    episodeList.value.last.number.toInt()) {
                  snackBar(
                      "That's it, genius. You ran out of episodes. Try a book next time.");
                } else {
                  isSwitchingEpisode = true;
                  player.pause().then((_) {
                    fetchEpisode(false);
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget buildPlayButton({
    required RxBool isPlaying,
    Color? color,
    Color? iconColor,
  }) {
    final isMobile = !settings.isTV.value && (Platform.isAndroid || Platform.isIOS);
    final padding = getResponsiveSize(
      context,
      mobileSize: 10,
      desktopSize: 20,
      isStrict: true,
    );
    final radius = getResponsiveSize(
      context,
      mobileSize: 20.multiplyRadius(),
      desktopSize: 40.multiplyRadius(),
      isStrict: true,
    );

    return Obx(() {
      return Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 50),
        child: BlurWrapper(
          borderRadius: BorderRadius.circular(radius),
          child: NyantvOnTap(
            onTap: () {
              player.playOrPause();
            },
            bgColor: Colors.transparent,
            focusedBorderColor: Colors.transparent,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: IconButton(
                key: ValueKey(isPlaying.value),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  padding: EdgeInsets.all(padding),
                ),
                onPressed: () {
                  player.playOrPause();
                },
                icon: Icon(
                  isPlaying.value
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: iconColor ?? color,
                  size: getResponsiveSize(
                    context,
                    mobileSize: 40,
                    desktopSize: 80,
                    isStrict: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildTVPlayer(BuildContext context) {
    final view = View.of(context);
    final physicalSize = view.physicalSize;
    final devicePixelRatio = view.devicePixelRatio;
    final realWidth = physicalSize.width / devicePixelRatio;
    
    final settings = Get.find<Settings>();
    final scale = settings.uiScale;
    final effectiveWidth = scale != 1.0 ? realWidth / scale : realWidth;
    
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: isEpisodeDialogOpen.value
              ? effectiveWidth * 0.7
              : effectiveWidth,
          child: _buildTVVideoWidget(),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: isEpisodeDialogOpen.value
              ? effectiveWidth * 0.3
              : 0,
          child: Focus(
            focusNode: FocusNode(
                canRequestFocus: isEpisodeDialogOpen.value,
                skipTraversal: !isEpisodeDialogOpen.value,
                descendantsAreFocusable: isEpisodeDialogOpen.value,
                descendantsAreTraversable: isEpisodeDialogOpen.value),
            child: EpisodeWatchScreen(
              episodeList: episodeList.value,
              anilistData: anilistData.value,
              currentEpisode: currentEpisode.value,
              onEpisodeSelected: (src, streamList, selectedEpisode) {
                episode.value = src;
                episodeTracks.value = streamList;
                currentEpisode.value = selectedEpisode;
                _initPlayer(false);
              },
            ),
          ),
        )
      ],
    );
  }

  Widget _buildTVVideoWidget() {
    final uiScaleBypass = UIScaleBypass.of(context);
    final shouldBypassScale = uiScaleBypass?.bypassScale ?? false;

    if (shouldBypassScale) {
      final view = View.of(context);
      final physicalSize = view.physicalSize;
      final devicePixelRatio = view.devicePixelRatio;
      final realScreenSize = physicalSize / devicePixelRatio;

      return SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Video(
          controller: playerController,
          controls: null,
          fit: BoxFit.contain,
          subtitleViewConfiguration: const SubtitleViewConfiguration(
            visible: false,
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Video(
        controller: playerController,
        controls: null,
        fit: BoxFit.contain,
        subtitleViewConfiguration: const SubtitleViewConfiguration(
          visible: false,
        ),
      ),
    );
  }

  Widget _buildPlaybackButton({
    required Function() onTap,
    IconData? icon,
    Color? color,
    Color? iconColor,
  }) {
    final isPlay =
        icon == Icons.play_arrow_rounded || icon == Icons.pause_rounded;
    final isMobile = !settings.isTV.value && (Platform.isAndroid || Platform.isIOS);
    final padding = getResponsiveSize(context,
        mobileSize: isPlay ? 10 : 5,
        desktopSize: isPlay ? 20 : 10,
        isStrict: true);
    final radius = getResponsiveSize(context,
        mobileSize: 20.multiplyRadius(),
        desktopSize: 40.multiplyRadius(),
        isStrict: true);

    return Container(
      decoration: BoxDecoration(
        color: isPlay
            ? color
            : settings.playerStyle == 0
                ? Colors.transparent
                : Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: isPlay ? [glowingShadow(context)] : [],
      ),
      clipBehavior: Clip.antiAlias,
      margin:
          EdgeInsets.symmetric(horizontal: isPlay ? (isMobile ? 20 : 50) : 0),
      child: BlurWrapper(
        borderRadius: BorderRadius.circular(radius),
        child: NyantvOnTap(
          onTap: onTap,
          bgColor: Colors.transparent,
          focusedBorderColor: Colors.transparent,
          child: IconButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
              padding: EdgeInsets.all(padding),
            ),
            onPressed: onTap,
            icon: Icon(
              icon,
              color: iconColor ?? color,
              size: getResponsiveSize(context,
                  mobileSize: 40, desktopSize: 80, isStrict: true),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBufferingIndicator() {
    final size = getResponsiveSize(context, mobileSize: 50, desktopSize: 70);
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal:
              getResponsiveSize(context, mobileSize: 25, desktopSize: 50)),
      child: SizedBox(
          height: size, width: size, child: const NyantvProgressIndicator()),
    );
  }

  Widget _buildIcon({VoidCallback? onTap, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 3),
      child: NyantvOnTap(
        onTap: () {
          onTap?.call();
        },
        child: IconButton(
            onPressed: onTap,
            icon: Icon(
              icon,
              color: Colors.white,
            )),
      ),
    );
  }

  void showColorProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ColorProfileBottomSheet(
        activeSettings: customSettings.value,
        currentProfile: currentVisualProfile.value,
        player: player,
        onProfileSelected: (profile) {
          currentVisualProfile.value = profile;
          settings.preferences.put('currentVisualProfile', profile);
        },
        onCustomSettingsChanged: (sett) {
          customSettings.value = sett;
          settings.preferences.put('currentVisualSettings', sett);
        },
      ),
    );
  }
}