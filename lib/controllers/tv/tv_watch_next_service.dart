// lib/controllers/tv/tv_watch_next_service.dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:nyantv/controllers/offline/offline_storage_controller.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/utils/logger.dart';

class TvWatchNextService extends GetxController {
  static const _channel = MethodChannel('com.nyantv/tv_watch_next');
  
  final _offlineStorage = Get.find<OfflineStorageController>();
  final _settings = Get.find<Settings>();
  
  @override
  void onInit() {
    super.onInit();
    if (Platform.isAndroid && _settings.isTV.value) {
      ever(_offlineStorage.animeLibrary, (_) => updateWatchNext());
    }
  }
  
  Future<void> updateWatchNext() async {
    if (!Platform.isAndroid || !_settings.isTV.value) return;
    
    final recentMedia = _getRecentWatchedMedia();
    if (recentMedia == null) return;
    
    final currentEp = recentMedia.currentEpisode;
    if (currentEp == null) return;
    
    final progress = _calculateProgress(
      currentEp.timeStampInMilliseconds ?? 0,
      currentEp.durationInMilliseconds ?? 0,
    );
    
    if (progress < 5 || progress > 95) return;
    
    try {
      await _channel.invokeMethod('updateWatchNext', {
        'mediaId': recentMedia.id,
        'title': recentMedia.name ?? recentMedia.english,
        'episodeTitle': 'Episode ${currentEp.number}: ${currentEp.title ?? ''}',
        'coverUrl': recentMedia.cover ?? recentMedia.poster,
        'posterUrl': recentMedia.poster,
        'progress': progress,
        'episodeNumber': currentEp.number,
        'currentPosition': currentEp.timeStampInMilliseconds ?? 0,
        'duration': currentEp.durationInMilliseconds ?? 0,
      });
      Logger.i('Watch Next updated for: ${recentMedia.name}');
    } catch (e) {
      Logger.i('Failed to update Watch Next: $e');
    }
  }
  
  dynamic _getRecentWatchedMedia() {
    final library = _offlineStorage.animeLibrary;
    if (library.isEmpty) return null;
    
    return library.firstWhereOrNull((media) {
      final ep = media.currentEpisode;
      return ep != null && 
             ep.timeStampInMilliseconds != null &&
             ep.durationInMilliseconds != null &&
             ep.timeStampInMilliseconds! > 0;
    });
  }
  
  int _calculateProgress(int current, int total) {
    if (total == 0) return 0;
    return ((current / total) * 100).round();
  }
  
  Future<void> removeFromWatchNext(String mediaId) async {
    if (!Platform.isAndroid || !_settings.isTV.value) return;
    
    try {
      await _channel.invokeMethod('removeFromWatchNext', {'mediaId': mediaId});
    } catch (e) {
      Logger.i('Failed to remove from Watch Next: $e');
    }
  }
}