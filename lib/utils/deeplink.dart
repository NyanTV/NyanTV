// lib/utils/deeplink.dart
import 'dart:io';
import 'package:nyantv/utils/extensions.dart';
import 'package:nyantv/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/ExtensionManager.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:nyantv/controllers/offline/offline_storage_controller.dart';
import 'package:nyantv/screens/anime/watch_page.dart';
import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:get/get.dart';
import 'package:nyantv/utils/logger.dart';
import 'package:nyantv/models/Media/media.dart' as nyantv;
import 'package:nyantv/models/Offline/Hive/video.dart' as model;
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart' as d;

class Deeplink {
  static void handleDeepLink(Uri uri) async {
    Logger.i("Deep Link received: $uri");
    
    try {
      // Watch Next Deep Link Handler
      if (uri.scheme == 'nyantv' && uri.host == 'watch') {
        await _handleWatchNextDeepLink(uri);
        return;
      }
      
      // Repo Add Deep Link Handler
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
        repoUrl = (uri.queryParameters["url"] ?? uri.queryParameters['anime_url'])
                  ?.trim();
      }
      
      if (repoUrl != null) {
        Extensions().addRepo(ItemType.anime, repoUrl, extType);
        snackBar("Added Repo Link Successfully!");
      } else {
        snackBar("Missing required parameters in the link.");
      }
    } catch (e, stackTrace) {
      Logger.e("Deep Link error: $e");
      Logger.e("Stack: $stackTrace");
      snackBar("Failed to handle deep link");
    }
  }
  
  static Future<void> _handleWatchNextDeepLink(Uri uri) async {
    try {
      final segments = uri.pathSegments;
      if (segments.length < 2) {
        Logger.i('Invalid Watch Next link format');
        snackBar('Invalid link format');
        return;
      }
      
      final mediaId = segments[0];
      final episodeNumber = segments[1];
      
      Logger.i('Watch Next: mediaId=$mediaId, episode=$episodeNumber');
      
      final offlineStorage = Get.find<OfflineStorageController>();
      final media = offlineStorage.getAnimeById(mediaId);
      
      if (media == null) {
        Logger.i('Media not found for Watch Next: $mediaId');
        snackBar('Anime not found in library');
        return;
      }
      
      final episode = media.episodes?.firstWhereOrNull(
        (e) => e.number == episodeNumber
      );
      
      if (episode == null) {
        Logger.i('Episode not found: $episodeNumber');
        snackBar('Episode not available');
        return;
      }
      
      final sourceController = Get.find<SourceController>();
      
      if (sourceController.activeSource.value == null) {
        Logger.i('No active source available');
        snackBar('No source configured');
        return;
      }
      
      // Show loading indicator
      snackBar('Loading episode...');
      
      // Fetch video streams
      final resp = await sourceController.activeSource.value!.methods
          .getVideoList(d.DEpisode(
            episodeNumber: episode.number, 
            url: episode.link
          ));
      
      final videos = resp.map((e) => model.Video.fromVideo(e)).toList();
      
      if (videos.isEmpty) {
        Logger.i('No video streams found');
        snackBar('No streams available');
        return;
      }
      
      // Convert OfflineMedia to Media
      final mediaObj = nyantv.Media.fromOfflineMedia(media, ItemType.anime);
      
      // Navigate to player
      Get.to(() => WatchPage(
        episodeSrc: videos.first,
        episodeList: media.episodes ?? [],
        anilistData: mediaObj,
        currentEpisode: episode,
        episodeTracks: videos,
      ));
      
      Logger.i('Successfully launched Watch Next episode');
      
    } catch (e, stackTrace) {
      Logger.e('Watch Next deep link error: $e');
      Logger.e('Stack: $stackTrace');
      snackBar('Failed to start playback');
    }
  }
}