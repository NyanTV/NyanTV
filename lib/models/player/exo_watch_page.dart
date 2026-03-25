// ignore_for_file: invalid_use_of_protected_member
import 'dart:async';
import 'dart:io';
import 'package:nyantv/utils/logger.dart';
import 'package:nyantv/controllers/service_handler/params.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/models/Offline/Hive/video.dart' as model;
import 'package:nyantv/constants/contants.dart';
import 'package:nyantv/controllers/offline/offline_storage_controller.dart';
import 'package:nyantv/controllers/settings/methods.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:nyantv/models/Media/media.dart' as nyantv;
import 'package:nyantv/models/Offline/Hive/episode.dart';
import 'package:nyantv/models/player/video_player_impl.dart';
import 'package:nyantv/models/player/base_player.dart' as base_player;
import 'package:nyantv/models/player/player_adaptor.dart';
import 'package:nyantv/screens/anime/widgets/episode_watch_screen.dart';
import 'package:nyantv/screens/anime/widgets/video_slider.dart';
import 'package:nyantv/screens/settings/sub_settings/settings_player.dart';
import 'package:nyantv/utils/string_extensions.dart';
import 'package:nyantv/widgets/common/checkmark_tile.dart';
import 'package:nyantv/widgets/common/glow.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_titlebar.dart';
import 'package:nyantv/widgets/helper/platform_builder.dart';
import 'package:nyantv/widgets/helper/tv_wrapper.dart';
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
import 'package:outlined_text/outlined_text.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:nyantv/utils/aniskip.dart' as aniskip;
import 'package:nyantv/utils/introdb.dart' as introdb;
import 'package:nyantv/utils/skip_times.dart';
import 'package:nyantv/utils/tv_scroll_mixin.dart';
import 'package:nyantv/controllers/discord/discord_rpc.dart';
import 'package:nyantv/main.dart';
import 'package:nyantv/controllers/tv/tv_watch_next_service.dart';

class ExoWatchPage extends StatefulWidget {
  final model.Video episodeSrc;
  final Episode currentEpisode;
  final List<Episode> episodeList;
  final nyantv.Media anilistData;
  final List<model.Video> episodeTracks;
  final bool shouldTrack;

  const ExoWatchPage({
    super.key,
    required this.episodeSrc,
    required this.episodeList,
    required this.anilistData,
    required this.currentEpisode,
    this.shouldTrack = true,
    required this.episodeTracks,
  });

  @override
  State<ExoWatchPage> createState() => _ExoWatchPageState();
}

class _ExoActiveSkip {
  final String label;
  final int end;
  final int start;
  _ExoActiveSkip({required this.label, required this.end, required this.start});
}

final Rx<_ExoActiveSkip?> exoActiveSkip = Rx<_ExoActiveSkip?>(null);

class _ExoWatchPageState extends State<ExoWatchPage>
    with TickerProviderStateMixin, TVScrollMixin, WidgetsBindingObserver {
  late Rx<model.Video> episode;
  late Rx<Episode> currentEpisode;
  late RxList<model.Video> episodeTracks;
  late RxList<Episode> episodeList;
  late Rx<nyantv.Media> anilistData;
  RxList<model.Track?> subtitles = <model.Track>[].obs;

  final offlineStorage = Get.find<OfflineStorageController>();
  late ServicesType mediaService;
  late DiscordRPCController discordRPC;

  late BetterPlayerImpl _betterPlayer;
  bool _isPlayerInitialized = false;
  Widget? _cachedVideoWidget;

  final isPlaying = true.obs;
  final currentPosition = const Duration(milliseconds: 0).obs;
  final episodeDuration = const Duration(minutes: 24).obs;
  final formattedTime = "00:00".obs;
  final formattedDuration = "24:00".obs;
  final showControls = true.obs;
  final isBuffering = true.obs;
  final bufferred = const Duration(milliseconds: 0).obs;
  Timer? _bufferingDebounceTimer;
  final isBufferingVisible = false.obs;
  final playbackSpeed = 1.0.obs;
  final isFullscreen = false.obs;
  final selectedSubIndex = (-1).obs;
  final selectedAudioIndex = 0.obs;
  final settings = Get.find<Settings>();
  final RxString resizeMode = "Contain".obs;
  late PlayerSettings playerSettings;
  late FocusNode _keyboardListenerFocusNode;
  final ScrollController _scrollController = ScrollController();
  final skipTimes = Rx<EpisodeSkipTimes?>(null);
  final isOPSkippedOnce = false.obs;
  final isEDSkippedOnce = false.obs;

  late AnimationController _leftAnimationController;
  late AnimationController _rightAnimationController;
  RxInt skipDuration = 10.obs;
  final isLocked = false.obs;
  RxList<String> subtitleText = [''].obs;
  FocusNode? _lastControlsFocusNode;

  final doubleTapLabel = 0.obs;
  Timer? doubleTapTimeout;
  final isLeftSide = false.obs;
  Timer? _hideControlsTimer;
  final pressed2x = false.obs;

  final sourceController = Get.find<SourceController>();
  final isEpisodeDialogOpen = false.obs;
  late bool isLoggedIn;
  final _prevEpFocusNode = FocusNode(debugLabel: 'prev-ep');
  final _playPauseFocusNode = FocusNode(debugLabel: 'play-pause');
  final _nextEpFocusNode = FocusNode(debugLabel: 'next-ep');
  final _skipButtonFocusNode = FocusNode(debugLabel: 'skip-btn');
  final _skipOpEdFocusNode = FocusNode(debugLabel: 'skip-oped');

  bool _menuInteractionPaused = false;

  Timer? _discordUpdateTimer;
  Timer? _periodicDiscordUpdateTimer;
  bool _isUpdatingDiscord = false;
  DateTime? _lastDiscordUpdate;
  final _minUpdateInterval = const Duration(seconds: 2);
  final _periodicUpdateInterval = const Duration(seconds: 20);

  int _focusGeneration = 0;
  DateTime? _controlsClosedAt;
  final _activeSegmentKey = Rx<String?>(null);

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<double>? _rateSub;
  StreamSubscription<List<String>>? _subtitleSub;
  StreamSubscription<bool>? _completedSub;

  bool isSwitchingEpisode = false;
  bool _isSeeking = false;
  bool _isManualSeeking = false;
  Duration _lastPosition = Duration.zero;
  DateTime _lastUIUpdate = DateTime.now();
  final prevRate = 1.0.obs;

  bool get isMobile =>
      !settings.isTV.value && (Platform.isAndroid || Platform.isIOS);

  @override
  ScrollController get scrollController => _scrollController;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      setState(() {});
    }
  }

  String? _computeSegmentKey(int secs) {
    if (skipTimes.value == null) return null;
    final segs = [
      skipTimes.value!.op,
      skipTimes.value!.mixedOp,
      skipTimes.value!.ed,
      skipTimes.value!.mixedEd,
      skipTimes.value!.recap,
    ];
    for (final seg in segs) {
      if (seg != null && secs >= seg.start && secs < seg.end) {
        return '${seg.start}-${seg.end}';
      }
    }
    return null;
  }

  void navigateToNextEpisode() {
    if (playerSettings.autoSkipFiller) {
      final target = _getNextNonFillerEpisode();
      if (target != null) {
        _switchToEpisode(target);
        return;
      }
    }
    if (_hasNextEpisode()) _switchToEpisode(_getNextEpisode()!);
  }

  bool _hasNextEpisode() =>
      currentEpisode.value.number.toInt() <
      episodeList.value.last.number.toInt();

  Episode? _getNextEpisode() {
    final idx = episodeList.value.indexOf(currentEpisode.value);
    return idx < episodeList.value.length - 1
        ? episodeList.value[idx + 1]
        : null;
  }

  Episode? _getNextNonFillerEpisode() {
    final idx = episodeList.value.indexOf(currentEpisode.value);
    int skipped = 0;
    for (int i = idx + 1; i < episodeList.value.length; i++) {
      final ep = episodeList.value[i];
      if (ep.filler != true) {
        if (skipped > 0) {
          snackBar('Skipped $skipped filler episode${skipped > 1 ? 's' : ''}');
        }
        return ep;
      }
      skipped++;
    }
    return _getNextEpisode();
  }

  Future<void> _switchToEpisode(Episode episode) async {
    isSwitchingEpisode = true;
    trackEpisode(
        currentPosition.value, episodeDuration.value, currentEpisode.value);
    currentEpisode.value = episode;
    final resp = await sourceController.activeSource.value!.methods
        .getVideoList(
            d.DEpisode(episodeNumber: episode.number, url: episode.link));
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
    if (settings.isTV.value) {
      try {
        Get.find<TvWatchNextService>()
            .setCurrentMedia(widget.anilistData.id.toString());
      } catch (_) {}
    }
    await _initExoPlayer(false);
    _waitForPlayerReady().then((_) {
      if (mounted) {
        isSwitchingEpisode = false;
        _scheduleDiscordUpdate(isPaused: false);
        if (isPlaying.value) _startPeriodicDiscordUpdates();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    initTVScroll();
    WidgetsBinding.instance.addObserver(this);
    setExcludedScreen(true);
    mediaService = widget.anilistData.serviceType;
    discordRPC = DiscordRPCController.instance;

    if (settings.isTV.value) {
      try {
        Get.find<TvWatchNextService>()
            .setCurrentMedia(widget.anilistData.id.toString());
      } catch (_) {}
    }

    _leftAnimationController = AnimationController(
        duration: const Duration(milliseconds: 1000), vsync: this);
    _rightAnimationController = AnimationController(
        duration: const Duration(milliseconds: 1000), vsync: this);
    skipTimes.value = null;
    _initRxVariables();
    _initHiveVariables();
    _initExoPlayer(true);

    if (widget.currentEpisode.number.toInt() > 1) {
      trackAnilistAndLocal(
          widget.currentEpisode.number.toInt() - 1, widget.currentEpisode);
    }

    _keyboardListenerFocusNode = FocusNode(
      canRequestFocus: !settings.isTV.value,
      skipTraversal: settings.isTV.value,
    );

    ever(showControls, (controlsVisible) {
      if (!settings.isTV.value || !mounted) return;
      final generation = ++_focusGeneration;
      if (controlsVisible) {
        if (_keyboardListenerFocusNode.hasFocus) {
          _keyboardListenerFocusNode.unfocus();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !showControls.value || generation != _focusGeneration)
            return;
          Future.delayed(const Duration(milliseconds: 250), () {
            if (!mounted ||
                !showControls.value ||
                generation != _focusGeneration) return;
            if (exoActiveSkip.value != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted ||
                    !showControls.value ||
                    generation != _focusGeneration) return;
                if (_skipOpEdFocusNode.canRequestFocus) {
                  _skipOpEdFocusNode.requestFocus();
                }
              });
            } else if (_lastControlsFocusNode != null &&
                _lastControlsFocusNode!.canRequestFocus) {
              _lastControlsFocusNode!.requestFocus();
            }
          });
        });
      } else {
        _controlsClosedAt = DateTime.now();
        final currentFocus = FocusScope.of(context).focusedChild;
        if (currentFocus != null &&
            currentFocus != _keyboardListenerFocusNode &&
            currentFocus != _skipOpEdFocusNode) {
          _lastControlsFocusNode = currentFocus;
        }
        _prevEpFocusNode.unfocus();
        _playPauseFocusNode.unfocus();
        _nextEpFocusNode.unfocus();
        _skipButtonFocusNode.unfocus();
        _skipOpEdFocusNode.unfocus();
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted &&
              generation == _focusGeneration &&
              !_keyboardListenerFocusNode.hasFocus) {
            FocusScope.of(context).requestFocus(_keyboardListenerFocusNode);
          }
        });
      }
    });

    ever(isBackButtonPressed, (pressed) {
      if (pressed && mounted) {
        isBackButtonPressed.value = false;

        if (isEpisodeDialogOpen.value) {
          isEpisodeDialogOpen.value = false;
          _menuInteractionPaused = false;
          _startHideControlsTimer();
        } else if (showControls.value) {
          toggleControls(val: false);
        } else if (!isLocked.value) {
          if (widget.shouldTrack) {
            discordRPC.updateMediaPresence(media: anilistData.value);
          }
          Get.back();
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

    ever(exoActiveSkip, (skip) {
      if (!settings.isTV.value || !mounted || !showControls.value) return;
      if (skip == null) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (!mounted || !showControls.value) return;
          _skipButtonFocusNode.requestFocus();
        });
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
  }

  Future<void> _initExoPlayer(bool firstTime) async {
    final savedEpisode = offlineStorage.getWatchedEpisode(
        widget.anilistData.id, currentEpisode.value.number);
    int savedMs = (savedEpisode?.number ?? 0) == currentEpisode.value.number
        ? savedEpisode?.timeStampInMilliseconds ?? 0
        : 0;
    final savedDuration = savedEpisode?.durationInMilliseconds ?? 0;
    final isNearEnd = savedDuration > 0 && (savedMs / savedDuration) >= 0.99;
    final startMs = isNearEnd ? 0 : savedMs;

    if (firstTime) {
      _betterPlayer = BetterPlayerImpl(
        configuration: base_player.PlayerConfiguration(
          playerType: base_player.PlayerType.betterPlayer,
          autoPlay: true,
          useBuffering: true,
          bufferSize: 32 * 1024 * 1024,
        ),
      );
      await _betterPlayer.initialize();
      _attachExoListeners();
    } else {
      currentPosition.value = Duration.zero;
      episodeDuration.value = Duration.zero;
      bufferred.value = Duration.zero;
    }

    await _betterPlayer.open(
      episode.value.url,
      headers: episode.value.headers ??
          {'Referer': sourceController.activeSource.value?.baseUrl ?? ''},
      startPosition: startMs > 0 ? Duration(milliseconds: startMs) : null,
    );

    if (firstTime) {
      _cachedVideoWidget = _betterPlayer.getVideoWidget(
          fit: resizeModes[resizeMode.value] ?? BoxFit.contain);
      if (mounted) setState(() => _isPlayerInitialized = true);
    } else {
      _cachedVideoWidget = _betterPlayer.getVideoWidget(
          fit: resizeModes[resizeMode.value] ?? BoxFit.contain);
      if (mounted) setState(() {});
    }

    await _initSubs();
    await _betterPlayer.setRate(prevRate.value);
    isOPSkippedOnce.value = false;
    isEDSkippedOnce.value = false;
    _fetchSkipTimes();

    if (firstTime) {
      _waitForPlayerReady().then((_) {
        if (mounted) {
          isSwitchingEpisode = false;
          _performDiscordUpdate(isPaused: false);
        }
      });
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted && episodeDuration.value.inMilliseconds == 0) {
          _performDiscordUpdate(isPaused: false);
        }
      });
    }
  }

  void _attachExoListeners() {
    _positionSub = _betterPlayer.positionStream.listen((e) {
      if (_isSeeking) return;
      if (_lastPosition.inSeconds != e.inSeconds) {
        _lastPosition = e;
        currentEpisode.value.timeStampInMilliseconds = e.inMilliseconds;
        final newKey = _computeSegmentKey(e.inSeconds);
        if (newKey != _activeSegmentKey.value) {
          _activeSegmentKey.value = newKey;
        }
        if (e.inSeconds % 30 == 0 &&
            e.inSeconds > 0 &&
            isPlaying.value &&
            !isSwitchingEpisode) {
          trackEpisode(e, episodeDuration.value, currentEpisode.value);
        }
        if (isPlaying.value && skipTimes.value != null && !isSwitchingEpisode) {
          _handleAutoSkip();
        }
      }
      final now = DateTime.now();
      if (mounted && now.difference(_lastUIUpdate).inMilliseconds >= 1000) {
        _lastUIUpdate = now;
        currentPosition.value = e;
        formattedTime.value = formatDuration(e);
      }
      if (e.inSeconds >= episodeDuration.value.inSeconds - 1 &&
          episodeDuration.value.inMinutes >= 1) {
        if (!isSwitchingEpisode) {
          isSwitchingEpisode = true;
          Future.delayed(
              const Duration(milliseconds: 500), navigateToNextEpisode);
        }
      }
      if (skipTimes.value != null && settings.isTV.value) {
        _updateExoActiveSkip(e.inSeconds);
      }
    });

    _durationSub = _betterPlayer.durationStream.listen((e) {
      episodeDuration.value = e;
      currentEpisode.value.durationInMilliseconds = e.inMilliseconds;
      formattedDuration.value = formatDuration(e);
    });

    _playingSub = _betterPlayer.playingStream.listen((e) {
      isPlaying.value = e;
      if (e) {
        _menuInteractionPaused = false;
        _startHideControlsTimer();
        setExcludedScreen(true);
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) isSwitchingEpisode = false;
        });
        _startPeriodicDiscordUpdates();
      } else {
        setExcludedScreen(false);
        _stopPeriodicDiscordUpdates();
      }
      if (!_isManualSeeking) _scheduleDiscordUpdate(isPaused: !e);
    });

    _bufferingSub = _betterPlayer.bufferingStream.listen((e) {
      isBuffering.value = e;
      if (e) {
        _bufferingDebounceTimer?.cancel();
        _bufferingDebounceTimer = Timer(const Duration(milliseconds: 400), () {
          if (isBuffering.value) isBufferingVisible.value = true;
        });
      } else {
        _bufferingDebounceTimer?.cancel();
        isBufferingVisible.value = false;
        if (isPlaying.value && !isSwitchingEpisode && !_isManualSeeking) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !isSwitchingEpisode) {
              _scheduleDiscordUpdate(isPaused: false);
            }
          });
        }
      }
    });

    _bufferSub = _betterPlayer.bufferStream.listen((e) {
      bufferred.value = e;
    });
    _rateSub = _betterPlayer.rateStream.listen((e) {
      playbackSpeed.value = e;
    });
    _subtitleSub = _betterPlayer.subtitleStream.listen((e) {
      subtitleText.value = e;
    });
    _completedSub = _betterPlayer.completedStream.listen((completed) {
      if (completed &&
          !isSwitchingEpisode &&
          episodeDuration.value.inMinutes >= 1) {
        isSwitchingEpisode = true;
        navigateToNextEpisode();
      }
    });
  }

  void _updateExoActiveSkip(int pos) {
    if (skipTimes.value == null) return;
    final isAnimating = _controlsClosedAt != null &&
        DateTime.now().difference(_controlsClosedAt!).inMilliseconds < 250;
    final candidates = <_ExoActiveSkip>[];

    void checkSegment(SkipIntervals? seg, String label, bool autoSkip) {
      if (seg == null || autoSkip) return;
      if (pos >= seg.start && pos < seg.end) {
        final secsIn = pos - seg.start;
        if (secsIn < 15 || showControls.value || isAnimating) {
          candidates.add(
              _ExoActiveSkip(label: label, end: seg.end, start: seg.start));
        }
      }
    }

    checkSegment(
        skipTimes.value!.op, 'Skip Opening', playerSettings.autoSkipOP);
    checkSegment(
        skipTimes.value!.mixedOp, 'Skip Opening', playerSettings.autoSkipOP);
    checkSegment(skipTimes.value!.ed, 'Skip Ending', playerSettings.autoSkipED);
    checkSegment(
        skipTimes.value!.mixedEd, 'Skip Ending', playerSettings.autoSkipED);
    checkSegment(
        skipTimes.value!.recap, 'Skip Recap', playerSettings.autoSkipRecap);

    if (candidates.isEmpty) {
      exoActiveSkip.value = null;
    } else {
      candidates.sort((a, b) => b.start.compareTo(a.start));
      exoActiveSkip.value = candidates.first;
    }
  }

  void _scheduleDiscordUpdate({bool isPaused = false}) {
    _discordUpdateTimer?.cancel();
    if (_isUpdatingDiscord) return;
    if (_lastDiscordUpdate != null) {
      final elapsed = DateTime.now().difference(_lastDiscordUpdate!);
      if (elapsed < _minUpdateInterval) {
        _discordUpdateTimer = Timer(_minUpdateInterval - elapsed,
            () => _performDiscordUpdate(isPaused: isPaused));
        return;
      }
    }
    _discordUpdateTimer = Timer(const Duration(milliseconds: 300),
        () => _performDiscordUpdate(isPaused: isPaused));
  }

  Future<void> _waitForPlayerReady() async {
    int attempts = 0;
    while (attempts < 30) {
      if (episodeDuration.value.inMilliseconds > 0) {
        await Future.delayed(const Duration(milliseconds: 300));
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }
  }

  Future<void> _performDiscordUpdate({bool isPaused = false}) async {
    if (_isUpdatingDiscord || episodeDuration.value.inMilliseconds == 0) return;
    _isUpdatingDiscord = true;
    _lastDiscordUpdate = DateTime.now();
    try {
      final totalEps =
          episodeList.isNotEmpty ? 'Total: ${episodeList.length} Episodes' : '';
      if (isPaused) {
        await discordRPC.updateAnimePresencePaused(
            anime: anilistData.value,
            episode: currentEpisode.value,
            totalEpisodes: totalEps);
      } else {
        await discordRPC.updateAnimePresence(
            anime: anilistData.value,
            episode: currentEpisode.value,
            totalEpisodes: totalEps);
      }
    } catch (e) {
      Logger.i('Discord error: $e');
    } finally {
      _isUpdatingDiscord = false;
    }
  }

  void _startPeriodicDiscordUpdates() {
    _stopPeriodicDiscordUpdates();
    if (!isPlaying.value || isSwitchingEpisode) return;
    _periodicDiscordUpdateTimer =
        Timer.periodic(_periodicUpdateInterval, (timer) {
      if (!mounted || !isPlaying.value || isSwitchingEpisode) {
        _stopPeriodicDiscordUpdates();
        return;
      }
      if (_lastDiscordUpdate == null ||
          DateTime.now().difference(_lastDiscordUpdate!) >=
              _periodicUpdateInterval) {
        if (!_isManualSeeking) _scheduleDiscordUpdate(isPaused: false);
      }
    });
  }

  void _stopPeriodicDiscordUpdates() {
    _periodicDiscordUpdateTimer?.cancel();
    _periodicDiscordUpdateTimer = null;
  }

  Future<void> trackEpisode(
      Duration position, Duration duration, Episode currentEpisode,
      {bool updateAL = true}) async {
    final pct =
        (position.inMilliseconds / episodeDuration.value.inMilliseconds) * 100;
    final crossed = pct >= settings.markAsCompleted;
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

  void _initHiveVariables() {
    playerSettings = settings.playerSettings.value;
    resizeMode.value =
        settings.resizeMode.contains('Cover') ? 'Contain' : settings.resizeMode;
    isLoggedIn = mediaService.onlineService.isLoggedIn.value;
    skipDuration.value = settings.seekDuration;
    prevRate.value = playerSettings.speed;
  }

  Future<void> _initSubs() async {
    subtitles.clear();
    selectedSubIndex.value = 0;
    _betterPlayer.setSubtitleTrack(base_player.SubtitleTrack.no());
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
        await _betterPlayer.setSubtitleTrack(
          base_player.SubtitleTrack(id: i!.file!, url: i.file, title: i.label),
        );
        break;
      }
    }
  }

  void _fetchSkipTimes() {
    skipTimes.value = null;
    isOPSkippedOnce.value = false;
    isEDSkippedOnce.value = false;
    final isSimkl = anilistData.value.serviceType == ServicesType.simkl;
    final isSeries = !anilistData.value.id.contains('*MOVIE');
    if (isSimkl && isSeries) {
      final imdbId = anilistData.value.imdbId;
      if (imdbId == null) return;
      () async {
        try {
          final result =
              await introdb.IntroDbApi().getSkipTimes(introdb.SkipSearchQuery(
            imdbId: imdbId,
            seasonNumber: _extractSeason(currentEpisode.value.number),
            episodeNumber: _extractEpisode(currentEpisode.value.number),
          ));
          if (result == null) return;
          skipTimes.value = EpisodeSkipTimes.fromIntroDb(result);
        } catch (e) {
          debugPrint('IntroDb error: $e');
        }
      }();
    } else {
      () async {
        try {
          final result =
              await aniskip.AniSkipApi().getSkipTimes(aniskip.SkipSearchQuery(
            idMAL: anilistData.value.serviceType == ServicesType.mal
                ? anilistData.value.id
                : anilistData.value.idMal,
            episodeNumber: currentEpisode.value.number,
          ));
          if (result == null) return;
          skipTimes.value = EpisodeSkipTimes.fromAniSkip(result);
        } catch (e) {
          debugPrint('AniSkip error: $e');
        }
      }();
    }
  }

  String _extractSeason(String ep) =>
      RegExp(r'[Ss](\d+)').firstMatch(ep)?.group(1) ?? '1';
  String _extractEpisode(String ep) =>
      RegExp(r'[Ee](\d+)').firstMatch(ep)?.group(1) ?? ep;

  final Map<int, String> _durationCache = {};

  String formatDuration(Duration duration) {
    final key = duration.inSeconds;
    if (_durationCache.containsKey(key)) return _durationCache[key]!;
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final result =
        duration.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
    if (_durationCache.length > 100) _durationCache.clear();
    _durationCache[key] = result;
    return result;
  }

  Episode? navEpisode(bool prev) {
    if (prev) {
      return episodeList.firstWhereOrNull((e) =>
          e.number == (currentEpisode.value.number.toInt() - 1).toString());
    }
    return episodeList.firstWhereOrNull((e) =>
        e.number == (currentEpisode.value.number.toInt() + 1).toString());
  }

  Future<void> fetchEpisode(bool prev) async {
    trackEpisode(
        currentPosition.value, episodeDuration.value, currentEpisode.value);
    isSwitchingEpisode = true;
    final episodeToNav = navEpisode(prev);
    if (episodeToNav == null) {
      snackBar("No Streams Found");
      isSwitchingEpisode = false;
      return;
    }
    currentEpisode.value = episodeToNav;
    if (settings.isTV.value) {
      try {
        Get.find<TvWatchNextService>()
            .setCurrentMedia(widget.anilistData.id.toString());
      } catch (_) {}
    }
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
    await _initExoPlayer(false);
    _waitForPlayerReady().then((_) {
      if (mounted) {
        isSwitchingEpisode = false;
        _scheduleDiscordUpdate(isPaused: false);
        if (isPlaying.value) _startPeriodicDiscordUpdates();
      }
    });
  }

  void _handleDoubleTap(TapDownDetails details) {
    final isLeft =
        details.globalPosition.dx < MediaQuery.of(context).size.width / 2;
    _skipSegments(isLeft);
  }

  void _skipSegments(bool isLeft) {
    _isManualSeeking = true;
    _betterPlayer.pause();
    if (isLeftSide.value != isLeft) {
      doubleTapLabel.value = 0;
      skipDuration.value = 0;
    }
    isLeftSide.value = isLeft;
    doubleTapLabel.value += settings.seekDuration;
    skipDuration.value += settings.seekDuration;
    final currentSeconds = currentPosition.value.inSeconds;
    final maxSeconds = episodeDuration.value.inSeconds;
    final newPos = isLeft
        ? (currentSeconds - skipDuration.value).clamp(0, maxSeconds)
        : (currentSeconds + skipDuration.value).clamp(0, maxSeconds);
    formattedTime.value = formatDuration(Duration(seconds: newPos));
    _betterPlayer.seek(Duration(seconds: newPos));
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
      _betterPlayer.play();
      _waitForBufferingAfterSeek().then((_) {
        _isManualSeeking = false;
        if (mounted && !isSwitchingEpisode) {
          _scheduleDiscordUpdate(isPaused: false);
        }
      });
    });
  }

  void _skipSegmentsTV(bool isLeft, int totalSeconds) {
    if (isLeftSide.value != isLeft) doubleTapLabel.value = 0;
    isLeftSide.value = isLeft;
    doubleTapLabel.value = totalSeconds;
    if (isLeft) {
      _leftAnimationController.forward(from: 0);
    } else {
      _rightAnimationController.forward(from: 0);
    }
    doubleTapTimeout?.cancel();
    doubleTapTimeout = Timer(const Duration(milliseconds: 800), () {
      doubleTapLabel.value = 0;
    });
  }

  Future<void> _waitForBufferingAfterSeek() async {
    if (!isPlaying.value) return;
    int attempts = 0;
    while (isBuffering.value && attempts < 75) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }
    await Future.delayed(const Duration(milliseconds: 200));
  }

  void _megaSkip(bool invert) {
    _isManualSeeking = true;
    if (invert) {
      final dur = Duration(
          seconds: currentPosition.value.inSeconds - settings.skipDuration);
      if (dur.inMilliseconds < 0) {
        currentPosition.value = Duration.zero;
        _betterPlayer.seek(Duration.zero);
      } else {
        currentPosition.value = dur;
        _betterPlayer.seek(dur);
      }
    } else {
      final dur = Duration(
          seconds: currentPosition.value.inSeconds + settings.skipDuration);
      currentPosition.value = dur;
      _betterPlayer.seek(dur);
    }
    _waitForBufferingAfterSeek().then((_) {
      _isManualSeeking = false;
      if (mounted && !isSwitchingEpisode && isPlaying.value) {
        _scheduleDiscordUpdate(isPaused: false);
      }
    });
  }

  void _handleAutoSkip() {
    void trySkip(SkipIntervals? seg, bool enabled, RxBool skippedOnce) {
      if (seg == null || !enabled) return;
      if (playerSettings.autoSkipOnce && skippedOnce.value) return;
      if (currentPosition.value.inSeconds > seg.start &&
          currentPosition.value.inSeconds < seg.end) {
        final dur = Duration(seconds: seg.end);
        currentPosition.value = dur;
        _betterPlayer.seek(dur);
        skippedOnce.value = true;
      }
    }

    trySkip(skipTimes.value?.op, playerSettings.autoSkipOP, isOPSkippedOnce);
    trySkip(
        skipTimes.value?.mixedOp, playerSettings.autoSkipOP, isOPSkippedOnce);
    trySkip(skipTimes.value?.ed, playerSettings.autoSkipED, isEDSkippedOnce);
    trySkip(
        skipTimes.value?.mixedEd, playerSettings.autoSkipED, isEDSkippedOnce);

    if (skipTimes.value?.recap != null && playerSettings.autoSkipRecap) {
      final seg = skipTimes.value!.recap!;
      if (currentPosition.value.inSeconds > seg.start &&
          currentPosition.value.inSeconds < seg.end) {
        final dur = Duration(seconds: seg.end);
        currentPosition.value = dur;
        _betterPlayer.seek(dur);
      }
    }
  }

  void toggleControls({bool? val}) {
    showControls.value = val ?? !showControls.value;
    if (showControls.value && isPlaying.value) _startHideControlsTimer();
  }

  void _startHideControlsTimer() {
    if (!isPlaying.value || _menuInteractionPaused) {
      _hideControlsTimer?.cancel();
      return;
    }
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (isPlaying.value && !_menuInteractionPaused) {
        showControls.value = false;
      }
    });
  }

  void _pauseForMenuInteraction() {
    _hideControlsTimer?.cancel();
    if (isPlaying.value) {
      _menuInteractionPaused = true;
      _betterPlayer.pause();
    }
  }

  void startSeeking() => _isSeeking = true;

  void endSeeking(Duration position) {
    currentPosition.value = position;
    formattedTime.value = formatDuration(position);
    currentEpisode.value.timeStampInMilliseconds = position.inSeconds * 1000;
    _isSeeking = false;
  }

  KeyEventResult handlePlayerKeyEvent(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;

    if (settings.isTV.value) {
      if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
        if (!showControls.value) {
          toggleControls(val: true);
          return KeyEventResult.handled;
        }
        _betterPlayer.playOrPause();
        _startHideControlsTimer();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft && showControls.value) {
        final newPos = Duration(
            seconds: (currentPosition.value.inSeconds - settings.seekDuration)
                .clamp(0, episodeDuration.value.inSeconds));
        _betterPlayer.seek(newPos);
        currentPosition.value = newPos;
        formattedTime.value = formatDuration(newPos);
        _skipSegmentsTV(true, settings.seekDuration);
        _startHideControlsTimer();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight && showControls.value) {
        final newPos = Duration(
            seconds: (currentPosition.value.inSeconds + settings.seekDuration)
                .clamp(0, episodeDuration.value.inSeconds));
        _betterPlayer.seek(newPos);
        currentPosition.value = newPos;
        formattedTime.value = formatDuration(newPos);
        _skipSegmentsTV(false, settings.seekDuration);
        _startHideControlsTimer();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        toggleControls();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.escape) {
        if (isEpisodeDialogOpen.value) {
          isEpisodeDialogOpen.value = false;
          _menuInteractionPaused = false;
          _startHideControlsTimer();
          return KeyEventResult.handled;
        }
        if (showControls.value) {
          toggleControls(val: false);
          return KeyEventResult.handled;
        }
        Get.back();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.space) {
      _betterPlayer.playOrPause();
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
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    doubleTapTimeout?.cancel();
    _discordUpdateTimer?.cancel();
    _periodicDiscordUpdateTimer?.cancel();
    _bufferingDebounceTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _bufferSub?.cancel();
    _rateSub?.cancel();
    _subtitleSub?.cancel();
    _completedSub?.cancel();
    _scrollController.dispose();
    _skipOpEdFocusNode.dispose();
    disposeTVScroll();
    setExcludedScreen(false);
    final savedEpisode = offlineStorage.getWatchedEpisode(
        widget.anilistData.id, currentEpisode.value.number);
    final savedMs = savedEpisode?.timeStampInMilliseconds ?? 0;
    final currentMs = currentPosition.value.inMilliseconds;
    if (currentMs > 5000 && currentMs >= savedMs - 3000) {
      trackEpisode(
          currentPosition.value, episodeDuration.value, currentEpisode.value,
          updateAL: false);
    }
    if (mounted) {
      try {
        discordRPC.updateMediaPresence(media: anilistData.value);
      } catch (e) {}
    }
    _betterPlayer.dispose();
    _leftAnimationController.dispose();
    _rightAnimationController.dispose();
    _prevEpFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _nextEpFocusNode.dispose();
    _skipButtonFocusNode.dispose();
    _keyboardListenerFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final canFocus = settings.isTV.value ? !showControls.value : true;
      return Focus(
        focusNode: _keyboardListenerFocusNode,
        autofocus: !settings.isTV.value,
        canRequestFocus: canFocus,
        skipTraversal: settings.isTV.value && showControls.value,
        onKeyEvent: handlePlayerKeyEvent,
        child: PopScope(
          canPop: false,
          onPopInvoked: (didPop) {
            if (didPop) return;
            if (isEpisodeDialogOpen.value) {
              isEpisodeDialogOpen.value = false;
              _menuInteractionPaused = false;
              _startHideControlsTimer();
              return;
            }
            if (!isLocked.value) {
              if (widget.shouldTrack) {
                discordRPC.updateMediaPresence(media: anilistData.value);
              }
              Get.back();
            }
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
                Obx(() => isBufferingVisible.value && !showControls.value
                    ? _buildBufferingIndicator()
                    : const SizedBox.shrink()),
                Obx(() => AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      bottom: showControls.value ? 95 : 40,
                      right: 20,
                      child: _buildSkipOpEdButton(),
                    )),
              ],
            ),
          ),
        ),
      );
    });
  }

  Obx _build2xThingy() {
    return Obx(() {
      if (!pressed2x.value) return const SizedBox.shrink();
      return Positioned(
        top: 30,
        child: Container(
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NyantvText(
                  text: "${(prevRate.value * 2).toInt()}x",
                  variant: TextVariant.semiBold),
              const SizedBox(width: 5),
              const Icon(Icons.fast_forward),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildVideoView() {
    if (!_isPlayerInitialized || _cachedVideoWidget == null) {
      return const SizedBox.shrink();
    }
    return _cachedVideoWidget!;
  }

  Obx _buildPlayer(BuildContext context) {
    return Obx(() {
      final videoWidget = _buildVideoView();
      if (settings.isTV.value) {
        final view = View.of(context);
        final realWidth = view.physicalSize.width / view.devicePixelRatio;
        final scale = settings.uiScale;
        final effectiveWidth = scale != 1.0 ? realWidth / scale : realWidth;
        return Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isEpisodeDialogOpen.value
                  ? effectiveWidth * 0.7
                  : effectiveWidth,
              child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: videoWidget),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isEpisodeDialogOpen.value ? effectiveWidth * 0.3 : 0,
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
                    _initExoPlayer(false);
                  },
                ),
              ),
            ),
          ],
        );
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
            child: videoWidget,
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
                  _initExoPlayer(false);
                },
              ),
            ),
          ),
        ],
      );
    });
  }

  Obx _buildOverlay(BuildContext context) {
    return Obx(() => AnimatedPositioned(
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
              _betterPlayer.setRate(prevRate.value * 2);
            },
            onLongPressEnd: (e) {
              pressed2x.value = false;
              _betterPlayer.setRate(prevRate.value);
            },
            onTap: () {
              if (settings.isTV.value) {
                if (!_keyboardListenerFocusNode.hasFocus &&
                    !showControls.value) {
                  FocusScope.of(context)
                      .requestFocus(_keyboardListenerFocusNode);
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
            child: AnimatedOpacity(
              curve: Curves.easeInOut,
              duration: const Duration(milliseconds: 300),
              opacity: showControls.value ? 1 : 0,
              child: Container(color: Colors.black.withOpacity(0.5)),
            ),
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
            child: Obx(() {
              final lines = subtitleText
                  .where((l) => l.trim().isNotEmpty)
                  .map((l) => l.trim())
                  .toList();
              if (lines.isEmpty) return const SizedBox.shrink();
              return RepaintBoundary(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colorOptions[settings.subtitleBackgroundColor],
                    borderRadius: BorderRadius.circular(12.multiplyRadius()),
                  ),
                  child: OutlinedText(
                    text: Text(
                      lines.join('\n'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: fontColorOptions[settings.subtitleColor],
                        fontSize: settings.subtitleSize.toDouble(),
                        fontFamily: "Poppins-Bold",
                      ),
                    ),
                    strokes: [
                      OutlinedTextStroke(
                        color: fontColorOptions[settings.subtitleOutlineColor]!,
                        width: settings.subtitleOutlineWidth.toDouble(),
                      )
                    ],
                  ),
                ),
              );
            }),
          ),
        ));
  }

  Widget _buildRippleEffect() {
    return Obx(() {
      if (doubleTapLabel.value == 0) return const SizedBox();
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
            final scale =
                Tween<double>(begin: 1.5, end: 1).animate(CurvedAnimation(
              parent: isLeftSide.value
                  ? _leftAnimationController
                  : _rightAnimationController,
              curve: Curves.easeInOut,
            ));
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
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          "${doubleTapLabel.value}s",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
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
      builder: (context) => Wrap(children: [
        SizedBox(
          height: MediaQuery.of(context).size.height,
          child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: const SettingsPlayer(isModal: true)),
        ),
      ]),
    );
  }

  void showAudioSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => SuperListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          const Center(
              child: NyantvText(
                  text: "Choose Audio", size: 18, variant: TextVariant.bold)),
          const SizedBox(height: 10),
          episode.value.audios == null
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
                        _betterPlayer.setAudioTrack(base_player.AudioTrack(
                            id: e.file!, url: e.file, title: e.label));
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
                                  : Theme.of(context).colorScheme.primary),
                          tileColor: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surfaceContainer,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          trailing: Icon(Iconsax.music,
                              color: isSelected
                                  ? Colors.black
                                  : Theme.of(context).colorScheme.primary),
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  void showTrackSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Center(
                  child: NyantvText(
                      text: "Choose Track",
                      size: 18,
                      variant: TextVariant.bold)),
              const SizedBox(height: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: episodeTracks.map((e) {
                  final isSelected = episode.value.quality == e.quality;
                  return NyantvOnTap(
                    onTap: () {
                      episode.value = e;
                      _betterPlayer.open(
                        e.url,
                        headers: e.headers ??
                            {
                              'Referer':
                                  sourceController.activeSource.value!.baseUrl!
                            },
                        startPosition: currentPosition.value,
                      );
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
                                : Theme.of(context).colorScheme.primary),
                        tileColor: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceContainer,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        trailing: Icon(Iconsax.play5,
                            color: isSelected
                                ? Colors.black
                                : Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showSubtitleSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Center(
                child: NyantvText(
                    text: "Choose Subtitle",
                    size: 18,
                    variant: TextVariant.bold)),
            const SizedBox(height: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NyantvOnTap(
                  onTap: () {
                    selectedSubIndex.value = -1;
                    Get.back();
                    _betterPlayer
                        .setSubtitleTrack(base_player.SubtitleTrack.no());
                  },
                  child: subtitleTile(
                      "None", Iconsax.subtitle5, selectedSubIndex.value == -1),
                ),
                ...subtitles.asMap().entries.map((entry) {
                  final index = entry.key;
                  final e = entry.value;
                  return NyantvOnTap(
                    onTap: () {
                      selectedSubIndex.value = index;
                      Get.back();
                      _betterPlayer.setSubtitleTrack(base_player.SubtitleTrack(
                          id: e!.file!, url: e.file, title: e.label));
                    },
                    child: subtitleTile(e?.label ?? 'None', Iconsax.subtitle5,
                        selectedSubIndex.value == index),
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
                      subtitles
                          .add(model.Track(file: filePath, label: file.name));
                      Get.back();
                      _betterPlayer.setSubtitleTrack(base_player.SubtitleTrack(
                          id: filePath, url: filePath, title: file.name));
                    } else {
                      snackBar('No subtitle file selected.', duration: 2000);
                    }
                  },
                  child: subtitleTile("Add Subtitle", Iconsax.add,
                      selectedSubIndex.value == subtitles.length + 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _executeSkipOpEd(_ExoActiveSkip skip) {
    final dur = Duration(seconds: skip.end);
    _betterPlayer.seek(dur);
    currentPosition.value = dur;
    _scheduleDiscordUpdate(isPaused: false);
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      if (exoActiveSkip.value != null) {
        _skipOpEdFocusNode.requestFocus();
      } else {
        _skipButtonFocusNode.requestFocus();
      }
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
            color: isSelected
                ? Colors.black
                : Theme.of(context).colorScheme.primary),
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
                    Focus(
                      skipTraversal: true,
                      onKeyEvent: (node, event) {
                        if (settings.isTV.value &&
                            event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.arrowDown &&
                            !_playPauseFocusNode.hasFocus) {
                          _playPauseFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: AnimatedContainer(
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
                                    onPressed: () => Get.back(),
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
                                        : Get.width * 0.6),
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
                                      text:
                                          anilistData.value.title.toUpperCase(),
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
                                          if (isEpisodeDialogOpen.value) {
                                            _pauseForMenuInteraction();
                                          } else {
                                            _menuInteractionPaused = false;
                                            _startHideControlsTimer();
                                          }
                                        },
                                        icon: HugeIcons.strokeRoundedFolder03),
                                    _buildIcon(
                                        onTap: () {
                                          _pauseForMenuInteraction();
                                          showPlaybackSpeedDialog(context);
                                        },
                                        icon: HugeIcons.strokeRoundedClock01),
                                  ],
                                  _buildIcon(
                                      onTap: () =>
                                          isLocked.value = !isLocked.value,
                                      icon: isLocked.value
                                          ? Icons.lock
                                          : Icons.lock_open),
                                ],
                              ),
                            ),
                          ],
                        ),
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
                                      text: ' /  ${formattedDuration.value}'),
                                ],
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const SizedBox(width: 8),
                                  if (!isLocked.value &&
                                      exoActiveSkip.value == null)
                                    _buildSkipButton(false),
                                ],
                              ),
                            ],
                          ),
                          IgnorePointer(
                            ignoring: isLocked.value,
                            child: SizedBox(
                              height: 27,
                              child: Stack(
                                children: [
                                  VideoSliderTheme(
                                    color: themeFgColor.value,
                                    inactiveTrackColor:
                                        _getBgColor().withOpacity(0.1),
                                    child: Slider(
                                      focusNode: FocusNode(
                                          canRequestFocus: false,
                                          skipTraversal: true),
                                      min: 0,
                                      value: currentPosition
                                          .value.inMilliseconds
                                          .toDouble(),
                                      max: (currentPosition
                                                      .value.inMilliseconds >
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
                                        if (episodeDuration.value.inMilliseconds
                                                .toDouble() !=
                                            0.0) {
                                          final newPosition = Duration(
                                              milliseconds: val.toInt());
                                          _betterPlayer.seek(newPosition);
                                          endSeeking(newPosition);
                                          await _waitForBufferingAfterSeek();
                                          _isManualSeeking = false;
                                          if (mounted &&
                                              !isSwitchingEpisode &&
                                              isPlaying.value) {
                                            _scheduleDiscordUpdate(
                                                isPaused: false);
                                          }
                                        }
                                      },
                                      onChanged: (val) {
                                        if (episodeDuration.value.inMilliseconds
                                                .toDouble() !=
                                            0.0) {
                                          currentPosition.value = Duration(
                                              milliseconds: val.toInt());
                                          formattedTime.value = formatDuration(
                                              currentPosition.value);
                                        }
                                      },
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Obx(() {
                                        _activeSegmentKey.value;
                                        return _buildSegmentOverlay();
                                      }),
                                    ),
                                  ),
                                ],
                              ),
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
                                            _pauseForMenuInteraction();
                                            playerSettingsSheet(context);
                                          },
                                          icon: HugeIcons
                                              .strokeRoundedSettings01),
                                      _buildIcon(
                                          onTap: () {
                                            _pauseForMenuInteraction();
                                            showTrackSelector();
                                          },
                                          icon: HugeIcons
                                              .strokeRoundedFolderVideo),
                                      _buildIcon(
                                          onTap: () {
                                            _pauseForMenuInteraction();
                                            showSubtitleSelector();
                                          },
                                          icon:
                                              HugeIcons.strokeRoundedSubtitle),
                                      if (episode.value.audios != null &&
                                          episode.value.audios!.isNotEmpty)
                                        _buildIcon(
                                            onTap: () {
                                              _pauseForMenuInteraction();
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
                                      _buildIcon(
                                          onTap: () {
                                            final newIndex =
                                                (resizeModeList.indexOf(
                                                            resizeMode.value) +
                                                        1) %
                                                    resizeModeList.length;
                                            resizeMode.value =
                                                resizeModeList[newIndex];
                                            _cachedVideoWidget =
                                                _betterPlayer.getVideoWidget(
                                                    fit: resizeModes[
                                                            resizeMode.value] ??
                                                        BoxFit.contain);
                                            if (mounted) setState(() {});
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
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!isLocked.value) _buildPlaybackButtons(),
              ],
            ),
          ),
        ),
      );
    });
  }

  void showPlaybackSpeedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: getResponsiveValue(context,
              mobileValue: null, desktopValue: 500.0),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Playback Speed',
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
                      child: ListTileWithCheckMark(
                        active: e == playbackSpeed.value,
                        leading: const Icon(Icons.speed),
                        onTap: () {
                          prevRate.value = e;
                          _betterPlayer.setRate(e);
                          Navigator.of(context).pop();
                        },
                        title: '${e.toStringAsFixed(2)}x',
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
              focusNode: _prevEpFocusNode,
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
                  _betterPlayer.pause();
                  fetchEpisode(true);
                }
              },
            ),
            Obx(
              () => isBuffering.value
                  ? _buildBufferingIndicator()
                  : _buildPlayButton(
                      isPlaying: isPlaying,
                      focusNode: _playPauseFocusNode,
                      color: themeBgColor.value,
                      iconColor: themeFgColor.value,
                    ),
            ),
            _buildPlaybackButton(
              focusNode: _nextEpFocusNode,
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
                  _betterPlayer.pause();
                  fetchEpisode(false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButton({
    required RxBool isPlaying,
    FocusNode? focusNode,
    Color? color,
    Color? iconColor,
  }) {
    final padding = getResponsiveSize(context,
        mobileSize: 10, desktopSize: 20, isStrict: true);
    final radius = getResponsiveSize(context,
        mobileSize: 20.multiplyRadius(),
        desktopSize: 40.multiplyRadius(),
        isStrict: true);
    final borderRadius = BorderRadius.circular(radius);

    return Obx(() {
      final iconWidget = AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        ),
        child: IconButton(
          key: ValueKey(isPlaying.value),
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            padding: EdgeInsets.all(padding),
          ),
          onPressed: () => _betterPlayer.playOrPause(),
          icon: Icon(
            isPlaying.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: iconColor ?? color,
            size: getResponsiveSize(context,
                mobileSize: 40, desktopSize: 80, isStrict: true),
          ),
        ),
      );

      if (settings.isTV.value) {
        return _TVFocusGlass(
          borderRadius: borderRadius,
          focusNode: focusNode,
          child: Container(
            decoration: BoxDecoration(color: color, borderRadius: borderRadius),
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.symmetric(horizontal: 50),
            child: BlurWrapper(
              borderRadius: borderRadius,
              child: Focus(
                focusNode: focusNode,
                canRequestFocus: focusNode != null && showControls.value,
                skipTraversal: !showControls.value,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) {
                    return KeyEventResult.ignored;
                  }
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.enter ||
                      key == LogicalKeyboardKey.select) {
                    _betterPlayer.playOrPause();
                    _startHideControlsTimer();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowDown) {
                    if (exoActiveSkip.value != null) {
                      _skipOpEdFocusNode.requestFocus();
                    } else {
                      _skipButtonFocusNode.requestFocus();
                    }
                    _startHideControlsTimer();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowUp) {
                    FocusScope.of(context)
                        .focusInDirection(TraversalDirection.up);
                    _startHideControlsTimer();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    if (currentEpisode.value.number.toInt() > 1) {
                      _prevEpFocusNode.requestFocus();
                    }
                    _startHideControlsTimer();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowRight) {
                    if (currentEpisode.value.number.toInt() <
                        episodeList.value.last.number.toInt()) {
                      _nextEpFocusNode.requestFocus();
                    }
                    _startHideControlsTimer();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: GestureDetector(
                  onTap: () {
                    _betterPlayer.playOrPause();
                    _startHideControlsTimer();
                  },
                  child: iconWidget,
                ),
              ),
            ),
          ),
        );
      }

      return Container(
        decoration: BoxDecoration(color: color, borderRadius: borderRadius),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 50),
        child: BlurWrapper(
          borderRadius: borderRadius,
          child: NyantvOnTap(
            onTap: () => _betterPlayer.playOrPause(),
            bgColor: Colors.transparent,
            focusedBorderColor: Colors.transparent,
            child: iconWidget,
          ),
        ),
      );
    });
  }

  Widget _buildSkipButtonChild(bool invert) {
    return invert
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fast_rewind_rounded, color: Colors.white),
              const SizedBox(width: 5),
              NyantvText(
                  text: "-${settings.skipDuration}s",
                  variant: TextVariant.semiBold,
                  color: Colors.white),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NyantvText(
                  text: "+${settings.skipDuration}s",
                  variant: TextVariant.semiBold,
                  color: Colors.white),
              const SizedBox(width: 5),
              const Icon(Icons.fast_forward_rounded, color: Colors.white),
            ],
          );
  }

  Widget _buildSkipButton(bool invert) {
    final borderRadius = BorderRadius.circular(20.multiplyRoundness());

    final btn = BlurWrapper(
      borderRadius: borderRadius,
      child: NyanTVButton(
        height: 50,
        width: 120,
        variant: ButtonVariant.simple,
        borderRadius: borderRadius,
        backgroundColor: Colors.transparent,
        onTap: () => _doSkip(invert),
        child: _buildSkipButtonChild(invert),
      ),
    );

    if (settings.isTV.value) {
      return _TVFocusGlass(
        borderRadius: borderRadius,
        focusNode: _skipButtonFocusNode,
        child: Focus(
          focusNode: _skipButtonFocusNode,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.select) {
              _doSkip(invert);
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowUp) {
              _playPauseFocusNode.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: btn,
        ),
      );
    }

    return btn;
  }

  Future<void> _doSkip(bool invert) async {
    _isManualSeeking = true;
    if (invert) {
      final dur = Duration(
          seconds: currentPosition.value.inSeconds - settings.skipDuration);
      if (dur.inMilliseconds < 0) {
        currentPosition.value = Duration.zero;
        _betterPlayer.seek(Duration.zero);
      } else {
        currentPosition.value = dur;
        _betterPlayer.seek(dur);
      }
    } else {
      final dur = Duration(
          seconds: currentPosition.value.inSeconds + settings.skipDuration);
      currentPosition.value = dur;
      _betterPlayer.seek(dur);
    }
    await _waitForBufferingAfterSeek();
    _isManualSeeking = false;
    if (mounted && !isSwitchingEpisode && isPlaying.value) {
      _scheduleDiscordUpdate(isPaused: false);
    }
  }

  Widget _buildPlaybackButton({
    required Function() onTap,
    IconData? icon,
    Color? color,
    Color? iconColor,
    FocusNode? focusNode,
  }) {
    final isPlay =
        icon == Icons.play_arrow_rounded || icon == Icons.pause_rounded;
    final padding = getResponsiveSize(context,
        mobileSize: isPlay ? 10 : 5,
        desktopSize: isPlay ? 20 : 10,
        isStrict: true);
    final radius = getResponsiveSize(context,
        mobileSize: 20.multiplyRadius(),
        desktopSize: 40.multiplyRadius(),
        isStrict: true);
    final borderRadius = BorderRadius.circular(radius);

    final iconWidget = IconButton(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        padding: EdgeInsets.all(padding),
      ),
      onPressed: onTap,
      icon: Icon(icon,
          color: iconColor ?? color,
          size: getResponsiveSize(context,
              mobileSize: 40, desktopSize: 80, isStrict: true)),
    );

    if (settings.isTV.value) {
      final isPrev = icon == Icons.skip_previous_rounded;
      final isNext = icon == Icons.skip_next_rounded;

      return _TVFocusGlass(
        borderRadius: borderRadius,
        focusNode: focusNode,
        child: Container(
          decoration: BoxDecoration(
            color: isPlay ? color : Colors.transparent,
            borderRadius: borderRadius,
            boxShadow: isPlay ? [glowingShadow(context)] : [],
          ),
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.symmetric(horizontal: isPlay ? 50 : 0),
          child: BlurWrapper(
            borderRadius: borderRadius,
            child: Focus(
              focusNode: focusNode,
              canRequestFocus: focusNode != null && showControls.value,
              skipTraversal: !showControls.value,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) {
                  return KeyEventResult.ignored;
                }
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.select) {
                  onTap();
                  _startHideControlsTimer();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowDown) {
                  if (exoActiveSkip.value != null) {
                    _skipOpEdFocusNode.requestFocus();
                  } else {
                    _skipButtonFocusNode.requestFocus();
                  }
                  _startHideControlsTimer();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowUp) {
                  FocusScope.of(context)
                      .focusInDirection(TraversalDirection.up);
                  _startHideControlsTimer();
                  return KeyEventResult.handled;
                }
                if (isPrev && key == LogicalKeyboardKey.arrowRight) {
                  _playPauseFocusNode.requestFocus();
                  _startHideControlsTimer();
                  return KeyEventResult.handled;
                }
                if (isNext && key == LogicalKeyboardKey.arrowLeft) {
                  _playPauseFocusNode.requestFocus();
                  _startHideControlsTimer();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                onTap: () {
                  onTap();
                  _startHideControlsTimer();
                },
                child: iconWidget,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isPlay
            ? color
            : settings.playerStyle == 0
                ? Colors.transparent
                : Colors.black.withOpacity(0.5),
        borderRadius: borderRadius,
        boxShadow: isPlay ? [glowingShadow(context)] : [],
      ),
      clipBehavior: Clip.antiAlias,
      margin:
          EdgeInsets.symmetric(horizontal: isPlay ? (isMobile ? 20 : 50) : 0),
      child: BlurWrapper(
        borderRadius: borderRadius,
        child: NyantvOnTap(
          onTap: onTap,
          bgColor: Colors.transparent,
          focusedBorderColor: Colors.transparent,
          child: iconWidget,
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
        child:
            IconButton(onPressed: onTap, icon: Icon(icon, color: Colors.white)),
      ),
    );
  }

  Color rotateHue(Color base, double degrees) {
    final hsl = HSLColor.fromColor(base);
    return hsl.withHue((hsl.hue + degrees) % 360).toColor();
  }

  Widget _buildSegmentOverlay() {
    if (skipTimes.value == null) return const SizedBox.shrink();
    final totalMs = episodeDuration.value.inMilliseconds.toDouble();
    if (totalMs <= 0) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      const hPad = 10.0;
      final trackWidth = constraints.maxWidth - hPad * 2;
      const markerH = 7.0;
      final markerTop = (constraints.maxHeight - markerH) / 2;

      final cs = Theme.of(context).colorScheme;
      final currentSecs = currentPosition.value.inSeconds;

      final segments = <(SkipIntervals?, Color)>[
        (skipTimes.value?.op, rotateHue(cs.primary, 45)),
        (skipTimes.value?.mixedOp, rotateHue(cs.primary, 45)),
        (skipTimes.value?.ed, cs.secondary),
        (skipTimes.value?.mixedEd, cs.secondary),
        (skipTimes.value?.recap, cs.tertiary),
      ];

      final markers = <Widget>[];
      for (final (seg, color) in segments) {
        if (seg == null) continue;
        if (seg.end <= currentSecs) continue;
        final effectiveStart =
            seg.start < currentSecs ? currentSecs : seg.start;
        final startPx = hPad + (effectiveStart * 1000 / totalMs) * trackWidth;
        final endPx = hPad + (seg.end * 1000 / totalMs) * trackWidth;
        final w = endPx - startPx;
        if (w <= 0) continue;
        markers.add(Positioned(
          left: startPx,
          width: w,
          top: markerTop,
          height: markerH,
          child: Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.95),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ));
      }

      if (markers.isEmpty) return const SizedBox.shrink();
      return Stack(children: markers);
    });
  }

  Widget _buildSkipOpEdButton() {
    return Obx(() {
      final skip = exoActiveSkip.value;
      if (skip == null) return const SizedBox.shrink();

      final borderRadius = BorderRadius.circular(20.multiplyRoundness());

      final btn = BlurWrapper(
        borderRadius: borderRadius,
        child: Focus(
          focusNode: _skipOpEdFocusNode,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.select) {
              _executeSkipOpEd(skip);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: NyanTVButton(
            height: 50,
            width: 160,
            variant: ButtonVariant.simple,
            borderRadius: borderRadius,
            backgroundColor: Colors.transparent,
            onTap: () => _executeSkipOpEd(skip),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.fast_forward_rounded, color: Colors.white),
                const SizedBox(width: 5),
                NyantvText(
                    text: skip.label,
                    variant: TextVariant.semiBold,
                    color: Colors.white),
              ],
            ),
          ),
        ),
      );

      return _TVFocusGlass(
        borderRadius: borderRadius,
        focusNode: _skipOpEdFocusNode,
        child: btn,
      );
    });
  }
}

class _TVFocusGlass extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final FocusNode? focusNode;
  const _TVFocusGlass({
    required this.child,
    required this.borderRadius,
    this.focusNode,
  });
  @override
  State<_TVFocusGlass> createState() => _TVFocusGlassState();
}

class _TVFocusGlassState extends State<_TVFocusGlass> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_TVFocusGlass old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode?.removeListener(_onFocusChange);
      widget.focusNode?.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    final hasFocus = widget.focusNode?.hasFocus ?? false;
    if (_focused != hasFocus) setState(() => _focused = hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        border: Border.all(
          color: _focused ? Colors.white.withOpacity(0.75) : Colors.transparent,
          width: 2,
        ),
        color: _focused ? Colors.white.withOpacity(0.12) : Colors.transparent,
        boxShadow: _focused
            ? [
                BoxShadow(
                    color: Colors.white.withOpacity(0.08),
                    blurRadius: 10,
                    spreadRadius: 1)
              ]
            : null,
      ),
      child: widget.child,
    );
  }
}
