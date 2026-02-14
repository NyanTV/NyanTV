// lib/controllers/tv/tv_watch_next_service.dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nyantv/controllers/offline/offline_storage_controller.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/utils/logger.dart';

class TvWatchNextService extends GetxController {
  static const _channel = MethodChannel('com.nyantv/tv_watch_next');

  final _offlineStorage = Get.find<OfflineStorageController>();
  final _settings = Get.find<Settings>();

  static const _lastMediaIdKey = 'tv_watch_next_last_media_id';
  String? _lastMediaId;

  bool _isUpdating = false;

  @override
  void onInit() {
    super.onInit();
    _restoreLastMediaId();
    Logger.i('TvWatchNextService connected to OfflineStorageController');
  }

  Future<void> setCurrentMedia(String mediaId) async {
    _lastMediaId = mediaId;
    _persistLastMediaId(mediaId);
    await updateWatchNext();
  }

  void _persistLastMediaId(String mediaId) {
    try {
      Hive.box('preferences').put(_lastMediaIdKey, mediaId);
    } catch (e) {
      Logger.e('Failed to persist lastMediaId: $e');
    }
  }

  void _restoreLastMediaId() {
    try {
      _lastMediaId = Hive.box('preferences').get(_lastMediaIdKey) as String?;
    } catch (e) {
      Logger.e('Failed to restore lastMediaId: $e');
    }
  }

  Future<void> updateWatchNext() async {
    if (!Platform.isAndroid || !_settings.isTV.value) return;
    if (_isUpdating) return;
    _isUpdating = true;

    try {
      final media = _getCurrentMedia();
      if (media == null) return;

      final currentEp = media.currentEpisode;
      if (currentEp == null) return;

      final progress = _calculateProgress(
        currentEp.timeStampInMilliseconds ?? 0,
        currentEp.durationInMilliseconds ?? 0,
      );

      if (progress < 5 || progress > 95) return;

      await _channel.invokeMethod('updateWatchNext', {
        'mediaId': media.id,
        'title': media.name ?? media.english,
        'episodeTitle': 'Episode ${currentEp.number}: ${currentEp.title ?? ''}',
        'coverUrl': media.cover ?? media.poster,
        'posterUrl': media.poster,
        'progress': progress,
        'episodeNumber': currentEp.number,
        'currentPosition': currentEp.timeStampInMilliseconds ?? 0,
        'duration': currentEp.durationInMilliseconds ?? 0,
      });

      Logger.i('Watch Next updated for: ${media.name}');
    } catch (e) {
      Logger.e('Failed to update Watch Next: $e');
    } finally {
      _isUpdating = false;
    }
  }

  dynamic _getCurrentMedia() {
    if (_lastMediaId == null) return null;
    return _offlineStorage.animeLibrary.firstWhereOrNull((media) {
      if (media.id != _lastMediaId) return false;
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
      Logger.e('Failed to remove from Watch Next: $e');
    }
  }
}