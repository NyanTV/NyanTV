import 'dart:io';
import 'package:nyantv/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/ExtensionManager.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:nyantv/controllers/offline/offline_storage_controller.dart';
import 'package:nyantv/screens/anime/watch_page.dart';
import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:get/get.dart';
import 'extensions.dart';
import 'package:nyantv/utils/logger.dart';
import 'package:nyantv/models/Media/media.dart' as nyantv;
import 'package:nyantv/models/Offline/Hive/video.dart' as model;
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart' as d;
import 'package:nyantv/screens/anime/details_page.dart';
import 'package:nyantv/main.dart';

class Deeplink {
  static void handleDeepLink(Uri uri) async {
    Logger.i("Deep Link received: $uri");
    try {
      if (uri.scheme == 'nyantv' && uri.host == 'watch') {
        await _handleWatchNextDeepLink(uri);
        return;
      }
      if (uri.host != 'add-repo') return;

      ExtensionType extType;
      String? repoUrl;

      if (Platform.isAndroid) {
        switch (uri.scheme.toLowerCase()) {
          case 'aniyomi':
            extType = ExtensionType.aniyomi;
            repoUrl = uri.queryParameters["url"]?.trim();
            break;
          case 'tachiyomi':
            extType = ExtensionType.aniyomi;
            repoUrl = uri.queryParameters["url"]?.trim();
            break;
          default:
            extType = ExtensionType.mangayomi;
            repoUrl = (uri.queryParameters["url"])?.trim();
        }
      } else {
        extType = ExtensionType.mangayomi;
        repoUrl = (uri.queryParameters["url"] ?? uri.queryParameters['anime_url'])?.trim();
      }

      if (repoUrl != null) {
        Extensions().addRepo(ItemType.anime, repoUrl, extType);
        snackBar("Added Repo Link Successfully!");
      } else {
        snackBar("Missing required parameters in the link.");
      }
    } catch (e, stackTrace) {
      Logger.e("Deep Link error: $e\n$stackTrace");
      snackBar("Failed to handle deep link");
    }
  }

  static Future<void> _handleWatchNextDeepLink(Uri uri) async {
    try {
      final segments = uri.pathSegments;
      if (segments.length < 2) {
        snackBar('Invalid link format');
        return;
      }

      final mediaId = segments[0];
      final episodeNumber = segments[1];
      Logger.i('Watch Next: mediaId=$mediaId, episode=$episodeNumber');

      dynamic media;
      OfflineStorageController? offlineStorage;
      final libraryDeadline = DateTime.now().add(const Duration(seconds: 15));

      while (DateTime.now().isBefore(libraryDeadline)) {
        try {
          offlineStorage ??= Get.find<OfflineStorageController>();
          media = offlineStorage.getAnimeById(mediaId);
          if (media != null) break;
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (media == null) {
        Logger.e('Watch Next: media $mediaId not found after 15s');
        snackBar('Anime not found in library');
        return;
      }

      // firstWhereOrNull funktioniert nicht auf dynamic-typed Listen —
      // daher manuell iterieren.
      dynamic episode;
      final episodes = media.episodes;
      if (episodes != null) {
        for (final e in episodes) {
          if (e.number == episodeNumber) {
            episode = e;
            break;
          }
        }
      }

      if (episode == null) {
        Logger.e('Watch Next: episode $episodeNumber not found');
        snackBar('Episode not available');
        return;
      }

      SourceController? sourceController;
      final sourceDeadline = DateTime.now().add(const Duration(seconds: 10));

      while (DateTime.now().isBefore(sourceDeadline)) {
        try {
          sourceController ??= Get.find<SourceController>();
          if (sourceController.activeSource.value != null) break;
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (sourceController == null || sourceController.activeSource.value == null) {
        Logger.e('Watch Next: no active source after 10s');
        snackBar('No source configured');
        return;
      }

      snackBar('Loading episode...');

      final resp = await sourceController.activeSource.value!.methods
          .getVideoList(d.DEpisode(
        episodeNumber: episode.number,
        url: episode.link,
      ));

      final videos = resp.map((e) => model.Video.fromVideo(e)).toList();

      if (videos.isEmpty) {
        Logger.e('Watch Next: no video streams returned');
        snackBar('No streams available');
        return;
      }

      final mediaObj = nyantv.Media.fromOfflineMedia(media, ItemType.anime);

      Get.offAll(
        () => FilterScreen(),
        transition: Transition.noTransition,
        duration: Duration.zero,
      );

      await Future.delayed(const Duration(milliseconds: 80));

      Get.to(
        () => AnimeDetailsPage(media: mediaObj, tag: mediaId),
        transition: Transition.noTransition,
        duration: Duration.zero,
      );

      await Future.delayed(const Duration(milliseconds: 80));

      Get.to(
        () => WatchPage(
          episodeSrc: videos.first,
          episodeList: episodes is List ? List.from(episodes) : [],
          anilistData: mediaObj,
          currentEpisode: episode,
          episodeTracks: videos,
        ),
      );

      Logger.i('Watch Next: episode launched successfully');
    } catch (e, stackTrace) {
      Logger.e('Watch Next deep link error: $e\n$stackTrace');
      snackBar('Failed to start playback');
    }
  }
}