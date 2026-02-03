import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:nyantv/models/Offline/Hive/offline_media.dart';
import 'package:nyantv/screens/anime/watch/watch_view.dart';
import 'package:nyantv/screens/anime/watch_page.dart';
import 'package:nyantv/utils/extension_utils.dart';
import 'package:nyantv/utils/function.dart';
import 'package:nyantv/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HistoryModel {
  OfflineMedia? media;
  String? title;
  String cover;
  String poster;
  String? sourceName;
  String? formattedEpisodeTitle;
  num? progress;
  num? totalProgress;
  String? progressTitle;
  double? calculatedProgress;
  VoidCallback? onTap;
  String? progressText;
  String? date;

  HistoryModel(
      {this.media,
      this.title,
      required this.cover,
      required this.poster,
      this.formattedEpisodeTitle,
      this.sourceName,
      this.progress,
      this.totalProgress,
      this.progressTitle,
      this.calculatedProgress,
      this.onTap,
      this.progressText,
      this.date});

  factory HistoryModel.fromOfflineMedia(OfflineMedia media, ItemType type) {
    final onTap = () {
      if (media.currentEpisode == null ||
          media.currentEpisode?.currentTrack == null ||
          media.episodes == null ||
          media.currentEpisode?.videoTracks == null) {
        snackBar(
          "Error: Missing required media. It seems you closed the app directly after watching the episode!",
          duration: 2000,
          maxLines: 3,
        );
      } else {
        if (media.currentEpisode?.source == null) {
          snackBar("Can't Play since user closed the app abruptly");
        }
        final source = Get.find<SourceController>()
            .getExtensionByName(media.currentEpisode!.source!);
        if (source == null) {
          snackBar(
              "Install ${media.currentEpisode?.source} First, Then Click");
        } else {
          navigate(() => settingsController.preferences
                  .get('useOldPlayer', defaultValue: false)
              ? WatchPage(
                  episodeSrc: media.currentEpisode!.currentTrack!,
                  episodeList: media.episodes!,
                  anilistData: convertOfflineToMedia(media),
                  currentEpisode: media.currentEpisode!,
                  episodeTracks: media.currentEpisode!.videoTracks!,
                )
              : WatchScreen(
                  episodeSrc: media.currentEpisode!.currentTrack!,
                  episodeList: media.episodes!,
                  anilistData: convertOfflineToMedia(media),
                  currentEpisode: media.currentEpisode!,
                  episodeTracks: media.currentEpisode!.videoTracks!,
                ));
        }
      }
    };

    return HistoryModel(
        media: media,
        title: media.name,
        cover: media.currentEpisode?.thumbnail ?? media.cover ?? media.poster!,
        poster: media.poster!,
        formattedEpisodeTitle: 'Episode ${media.currentEpisode?.number ?? '??'}',
        sourceName: media.currentEpisode?.source,
        progress: media.currentEpisode?.timeStampInMilliseconds,
        totalProgress: media.currentEpisode?.durationInMilliseconds,
        progressTitle: media.currentEpisode?.title,
        calculatedProgress: calculateProgress(
            media.currentEpisode?.timeStampInMilliseconds,
            media.currentEpisode?.durationInMilliseconds,
          ),
        onTap: onTap,
        date: formattedDate(media.currentEpisode?.lastWatchedTime ?? 0),
        progressText: formatProgressText(media));
  }
  
  @override
  String toString() {
    return '''
HistoryModel(
  title: $title,
  cover: $cover,
  poster: $poster,
  sourceName: $sourceName,
  formattedEpisodeTitle: $formattedEpisodeTitle,
  progress: $progress,
  totalProgress: $totalProgress,
  progressTitle: $progressTitle,
  calculatedProgress: $calculatedProgress,
  progressText: $progressText,
  date: $date
)
  ''';
  }
}

double calculateProgress(int? min, int? max) {
  if (min == null || max == null) {
    return 0.0;
  }

  return (min / max).clamp(0.0, 1.0);
}

String formattedDate(int milliseconds) {
  return formatTimeAgo(milliseconds);
}

String formatProgressText(OfflineMedia data) {
  if (data.currentEpisode?.durationInMilliseconds == null ||
      data.currentEpisode?.timeStampInMilliseconds == null) {
    return '--:--';
  }

  final duration = data.currentEpisode!.durationInMilliseconds ?? 0;
  final timestamp = data.currentEpisode!.timeStampInMilliseconds ?? 0;
  final timeLeft = Duration(milliseconds: duration - timestamp);

  String twoDigits(int n) => n.toString().padLeft(2, '0');

  final minutes = twoDigits(timeLeft.inMinutes.remainder(60));
  final seconds = twoDigits(timeLeft.inSeconds.remainder(60));
  final hours = (timeLeft.inHours);

  if (hours > 0) return '${twoDigits(hours)}:$minutes:$seconds left';

  return '$minutes:$seconds left';
}