// lib/screens/anime/watch/watch_view.dart
import 'package:nyantv/models/Media/media.dart' as nyantv;
import 'package:nyantv/models/Offline/Hive/episode.dart';
import 'package:nyantv/models/Offline/Hive/video.dart' as model;
import 'package:nyantv/screens/anime/watch/controller/player_controller.dart';
import 'package:nyantv/screens/anime/watch/controls/bottom_controls.dart';
import 'package:nyantv/screens/anime/watch/controls/center_controls.dart';
import 'package:nyantv/screens/anime/watch/controls/widgets/double_tap_seek.dart';
import 'package:nyantv/screens/anime/watch/controls/widgets/overlay.dart';
import 'package:nyantv/screens/anime/watch/controls/top_controls.dart';
import 'package:nyantv/screens/anime/watch/controls/widgets/episodes_pane.dart';
import 'package:nyantv/screens/anime/watch/controls/widgets/subtitle_text.dart';
import 'package:nyantv/screens/anime/watch/subtitles/subtitle_view.dart';
import 'package:nyantv/screens/anime/widgets/media_indicator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

class WatchScreen extends StatefulWidget {
  final model.Video episodeSrc;
  final Episode currentEpisode;
  final List<Episode> episodeList;
  final nyantv.Media anilistData;
  final List<model.Video> episodeTracks;
  final bool shouldTrack;

  const WatchScreen({
    super.key,
    required this.episodeSrc,
    required this.currentEpisode,
    required this.episodeList,
    required this.anilistData,
    required this.episodeTracks,
    this.shouldTrack = true,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  late PlayerController controller;
  late FocusNode _keyboardFocusNode;

  @override
  initState() {
    super.initState();
    controller = Get.put(PlayerController(
        widget.episodeSrc,
        widget.currentEpisode,
        widget.episodeList,
        widget.anilistData,
        widget.episodeTracks));
    _keyboardFocusNode = FocusNode();
  }

  @override
  void dispose() {
    controller.delete();
    Get.delete<PlayerController>(force: true);
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_keyboardFocusNode.hasFocus) {
        _keyboardFocusNode.requestFocus();
      }
    });
    return Scaffold(
      body: FocusScope(
        autofocus: true,
        child: KeyboardListener(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: (event) {
            // Handle TV remote input
            if (controller.settings.isTV.value) {
              controller.tvRemoteHandler.handleKeyEvent(_keyboardFocusNode, event);
              return;
            }

            if (event is KeyDownEvent) {
            _handleAdditionalKeys(event);
            }
          },
            child: Stack(
            children: [
              Obx(() {
                return Video(
                  key: const ValueKey('android_tv_video_player'),
                  filterQuality: FilterQuality.medium,
                  controls: null,
                  controller: controller.playerController,
                  fit: controller.videoFit.value,
                  resumeUponEnteringForegroundMode: true,
                  wakelock: true,
                  subtitleViewConfiguration:
                      const SubtitleViewConfiguration(visible: false),
                );
              }),
              PlayerOverlay(controller: controller),
              SubtitleText(controller: controller),
              DoubleTapSeekWidget(
                controller: controller,
              ),
              const Align(
                alignment: Alignment.center,
                child: CenterControls(),
              ),
              const Align(
                alignment: Alignment.topCenter,
                child: TopControls(),
              ),
              const Align(
                alignment: Alignment.bottomCenter,
                child: BottomControls(),
              ),
              MediaIndicatorBuilder(
                isVolumeIndicator: false,
                controller: controller,
              ),
              MediaIndicatorBuilder(
                isVolumeIndicator: true,
                controller: controller,
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                left: 0,
                child: SubtitleSearchBottomSheet(controller: controller),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                left: 0,
                child: EpisodesPane(controller: controller),
              ),
              // TV Seek Indicator - nur auf Android TV anzeigen
            ],
          ),
        ),
      ),
    );
  }

  void _handleAdditionalKeys(KeyDownEvent event) {
    final key = event.logicalKey;
    
    // Space bar for play/pause
    if (key == LogicalKeyboardKey.space) {
      controller.togglePlayPause();
    }
    
    // F for fullscreen
    if (key == LogicalKeyboardKey.keyF) {
      controller.toggleFullScreen();
    }
    
    // M for mute
    if (key == LogicalKeyboardKey.keyM) {
      controller.toggleMute();
    }
  }

}
