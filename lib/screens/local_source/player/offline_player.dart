// lib/screens/local_source/player/offline_player.dart
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/models/Media/media.dart';
import 'package:nyantv/models/Offline/Hive/episode.dart';
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
import 'package:media_kit_video/media_kit_video.dart';

class LocalEpisode {
  final String folderName;
  final String name;
  final String path;

  LocalEpisode({
    required this.folderName,
    required this.name,
    required this.path,
  });
}

class OfflineWatchPage extends StatefulWidget {
  final LocalEpisode episode;
  final List<LocalEpisode> episodeList;

  const OfflineWatchPage({
    super.key,
    required this.episode,
    required this.episodeList,
  });

  @override
  State<OfflineWatchPage> createState() => _OfflineWatchPageState();
}

class _OfflineWatchPageState extends State<OfflineWatchPage> {
  late PlayerController controller;
  late FocusNode _keyboardFocusNode;

  @override
  initState() {
    super.initState();
    controller = Get.put(PlayerController.offline(
      folderName: widget.episode.folderName,
      itemName: widget.episode.name,
      videoPath: widget.episode.path,
      episode: Episode(number: 'Offline'),
      episodeList: [],
      anilistData: Media(serviceType: ServicesType.anilist),
    ));
    
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
    // Request focus nach dem ersten Frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_keyboardFocusNode.hasFocus) {
        _keyboardFocusNode.requestFocus();
      }
    });
    
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        // Handle TV remote input
        if (controller.settings.isTV.value) {
          return controller.tvRemoteHandler.handleKeyEvent(node, event);
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: Stack(
          children: [
            Obx(() {
              return Video(
                controller: controller.playerController,
                fit: controller.videoFit.value,
                resumeUponEnteringForegroundMode: true,
                subtitleViewConfiguration:
                    const SubtitleViewConfiguration(visible: false),
                controls: (state) => const SizedBox.shrink(),
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
          ],
        ),
      ),
    );
  }
}