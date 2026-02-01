import 'package:nyantv/utils/logger.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:nyantv/models/Media/media.dart';
import 'package:nyantv/models/Offline/Hive/chapter.dart';
import 'package:nyantv/models/Offline/Hive/custom_list.dart';
import 'package:nyantv/models/Offline/Hive/episode.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:get/get.dart';
import 'package:nyantv/models/Offline/Hive/offline_media.dart';
import 'package:hive/hive.dart';
import 'package:nyantv/models/Offline/Hive/offline_storage.dart';

class OfflineStorageController extends GetxController {
  var animeLibrary = <OfflineMedia>[].obs;
  Rx<List<CustomList>> animeCustomLists = Rx([]);
  Rx<List<CustomListData>> animeCustomListData = Rx([]);
  late Box<OfflineStorage> _offlineStorageBox;
  late Box storage;

  bool _isUpdating = false;

  @override
  Future<void> onInit() async {
    super.onInit();
    try {
      _offlineStorageBox = await Hive.openBox<OfflineStorage>('offlineStorage');
      storage = await Hive.openBox('storage');
      _loadLibraries();
    } catch (e) {
      Logger.i('Error opening Hive box: $e');
    }
  }

  void _loadLibraries() {
    if (_isUpdating) return;

    final offlineStorage =
        _offlineStorageBox.get('storage') ?? OfflineStorage();

    animeLibrary.assignAll(offlineStorage.animeLibrary ?? []);
    animeCustomLists.value
        .assignAll(offlineStorage.animeCustomList ?? [CustomList()]);

    _refreshListData();
  }

  void _refreshListData() {
    if (_isUpdating) return;

    _removeDuplicateMediaIds();
    _buildCustomListData();
    animeCustomLists.refresh();
  }

  void _removeDuplicateMediaIds() {
    for (var list in animeCustomLists.value) {
      if (list.mediaIds != null) {
        list.mediaIds = list.mediaIds!.toSet().toList();
        list.mediaIds!.removeWhere((id) => id == '0' || id.isEmpty);
      }
    }
  }

  void _buildCustomListData() {
    animeCustomListData.value.clear();

    for (var customList in animeCustomLists.value) {
      final mediaList = <OfflineMedia>[];

      if (customList.mediaIds != null) {
        for (var mediaId in customList.mediaIds!) {
          final media = getAnimeById(mediaId);
          if (media != null) {
            mediaList.add(media);
          }
        }
      }

      animeCustomListData.value.add(CustomListData(
          listData: mediaList,
          listName: customList.listName ?? 'Unnamed List'));
    }
  }

  void addCustomList(String listName, {ItemType mediaType = ItemType.anime}) {
    if (listName.isEmpty) return;

    final targetLists = animeCustomLists;

    if (targetLists.value.any((list) => list.listName == listName)) {
      Logger.i('List with name "$listName" already exists');
      return;
    }

    targetLists.value.add(CustomList(listName: listName, mediaIds: []));
    _refreshListData();
    _saveLibraries();
  }

  void removeCustomList(String listName,
      {ItemType mediaType = ItemType.anime}) {
    if (listName.isEmpty) return;

    final targetLists = animeCustomLists;
    final beforeLength = targetLists.value.length;
    targetLists.value.removeWhere((e) => e.listName == listName);
    final afterLength = targetLists.value.length;

    if (beforeLength != afterLength) {
      _refreshListData();
      _saveLibraries();
    }
  }

  void renameCustomList(String oldName, String newName,
      {ItemType mediaType = ItemType.anime}) {
    if (oldName.isEmpty || newName.isEmpty || oldName == newName) return;

    final targetLists = animeCustomLists;

    if (targetLists.value.any((list) => list.listName == newName)) {
      Logger.i('List with name "$newName" already exists');
      return;
    }

    final listToRename =
        targetLists.value.firstWhereOrNull((list) => list.listName == oldName);
    if (listToRename != null) {
      listToRename.listName = newName;
      _refreshListData();
      _saveLibraries();
    }
  }

  void addMediaToList(String listName, String mediaId,
      {ItemType mediaType = ItemType.anime}) {
    if (listName.isEmpty || mediaId.isEmpty) return;

    final targetLists = animeCustomLists;
    final targetList =
        targetLists.value.firstWhereOrNull((list) => list.listName == listName);

    if (targetList != null) {
      Logger.i('Adding Media to List => $listName  $mediaId');
      targetList.mediaIds ??= [];
      targetList.mediaIds!.add(mediaId);
      _refreshListData();
      _saveLibraries();
    }
  }

  void removeMediaFromList(String listName, String mediaId,
      {ItemType mediaType = ItemType.anime}) {
    if (listName.isEmpty || mediaId.isEmpty) return;

    final targetLists = animeCustomLists;
    final targetList =
        targetLists.value.firstWhereOrNull((list) => list.listName == listName);

    if (targetList != null && targetList.mediaIds != null) {
      final beforeLength = targetList.mediaIds!.length;
      targetList.mediaIds!.removeWhere((id) => id == mediaId);
      final afterLength = targetList.mediaIds!.length;

      animeLibrary.removeWhere((media) => media.id == mediaId);


      if (beforeLength != afterLength) {
        _refreshListData();
        _saveLibraries();
      }
    }
  }

  void batchUpdateCustomList(
      {required String listName,
      String? newListName,
      List<String>? mediaIds,
      ItemType mediaType = ItemType.anime}) {
    if (listName.isEmpty) return;

    _isUpdating = true;

    try {
      final targetLists = animeCustomLists;
      final targetList = targetLists.value
          .firstWhereOrNull((list) => list.listName == listName);

      if (targetList != null) {
        if (newListName != null &&
            newListName.isNotEmpty &&
            newListName != listName) {
          if (!targetLists.value.any((list) => list.listName == newListName)) {
            targetList.listName = newListName;
          }
        }

        if (mediaIds != null) {
          targetList.mediaIds = mediaIds
              .where((id) => id.isNotEmpty && id != '0')
              .toSet()
              .toList();
        }

        _refreshListData();
        _saveLibraries();
      }
    } finally {
      _isUpdating = false;
    }
  }

  List<CustomListData> getEditableCustomListData(
      {ItemType mediaType = ItemType.anime}) {
    final sourceData = animeCustomListData.value;

    return sourceData
        .map((listData) => CustomListData(
            listName: listData.listName,
            listData: List<OfflineMedia>.from(listData.listData)))
        .toList();
  }

  void applyCustomListChanges(List<CustomListData> editedData,
      {ItemType mediaType = ItemType.anime}) {
    if (editedData.isEmpty) return;

    _isUpdating = true;

    try {
      final targetList = animeCustomLists;
      final targetData = animeCustomListData;

      final newLists = <CustomList>[];

      for (var listData in editedData) {
        final mediaIds = listData.listData
            .map((media) => media.id ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
        newLists
            .add(CustomList(listName: listData.listName, mediaIds: mediaIds));
      }

      targetList.value = newLists;
      targetData.value = editedData;

      targetList.refresh();
      targetData.refresh();
      _saveLibraries();
    } finally {
      _isUpdating = false;
    }
  }

  List<OfflineMedia> getLibraryFromType(ItemType mediaType) {
    return (animeLibrary);
  }

  List<CustomList> getListFromType(ItemType mediaType) {
    return (animeCustomLists).value;
  }

  void addMedia(String listName, Media original, ItemType type) {
    final library = getLibraryFromType(type);

    if (library.firstWhereOrNull((e) => e.id == original.id) == null) {
      final episode = Episode(number: '1');
      library.insert(
          0, _createOfflineMedia(original, null, null, null, episode));
    }

    addMediaToList(listName, original.id, mediaType: type);
  }

  void removeMedia(String listName, String id, ItemType type) {
    removeMediaFromList(listName, id, mediaType: type);
  }

  void addOrUpdateAnime(
      Media original, List<Episode>? episodes, Episode? currentEpisode) {
    OfflineMedia? existingAnime = getAnimeById(original.id);

    if (existingAnime != null) {
      existingAnime.episodes = episodes;
      currentEpisode?.source = sourceController.activeSource.value?.name;
      existingAnime.currentEpisode = currentEpisode;

      Logger.i('Updated anime: ${existingAnime.name}');
      animeLibrary.remove(existingAnime);
      animeLibrary.insert(0, existingAnime);
    } else {
      animeLibrary.insert(0,
          _createOfflineMedia(original, null, episodes, null, currentEpisode));
      Logger.i('Added new anime: ${original.title}');
    }

    _saveLibraries();

    if (!_isUpdating) {
      _refreshListData();
    }
  }

  void addOrUpdateWatchedEpisode(String animeId, Episode episode) {
    OfflineMedia? existingAnime = getAnimeById(animeId);
    if (existingAnime != null) {
      existingAnime.watchedEpisodes ??= [];
      int index = existingAnime.watchedEpisodes!
          .indexWhere((e) => e.number == episode.number);
      episode.source = sourceController.activeSource.value?.name;

      if (index != -1) {
        episode.lastWatchedTime = DateTime.now().millisecondsSinceEpoch;
        existingAnime.watchedEpisodes![index] = episode;
        Logger.i(
            'Overwritten episode: ${episode.number} for anime ID: $animeId');
      } else {
        episode.lastWatchedTime = DateTime.now().millisecondsSinceEpoch;
        existingAnime.watchedEpisodes!.add(episode);
        Logger.i('Added new episode: ${episode.title} for anime ID: $animeId');
      }
    } else {
      Logger.i(
          'Anime with ID: $animeId not found. Unable to add/update episode.');
    }
    _saveLibraries();
  }

  OfflineMedia _createOfflineMedia(
      Media original,
      List<Chapter>? chapters,
      List<Episode>? episodes,
      Chapter? currentChapter,
      Episode? currentEpisode) {
    final handler = Get.find<ServiceHandler>();
    return OfflineMedia(
        id: original.id,
        jname: original.romajiTitle,
        name: original.title,
        english: original.title,
        japanese: original.romajiTitle,
        description: original.description,
        poster: original.poster,
        cover: original.cover,
        totalEpisodes: original.totalEpisodes,
        type: original.type,
        season: original.season,
        premiered: original.premiered,
        duration: original.duration,
        status: original.status,
        rating: original.rating,
        popularity: original.popularity,
        format: original.format,
        aired: original.aired,
        genres: original.genres,
        studios: original.studios,
        episodes: episodes,
        currentEpisode: currentEpisode,
        watchedEpisodes: episodes ?? [],
        serviceIndex: handler.serviceType.value.index);
  }

  void _saveLibraries() {
    if (_isUpdating) return;

    final updatedStorage = OfflineStorage(
        animeLibrary: animeLibrary.toList(),
        animeCustomList: animeCustomLists.value);

    try {
      _offlineStorageBox.put('storage', updatedStorage);
      Logger.i("Anime Successfully Saved!");
    } catch (e) {
      Logger.i('Error saving libraries: $e');
    }
  }

  OfflineMedia? getAnimeById(String id) {
    return animeLibrary.firstWhereOrNull((anime) => anime.id == id);
  }


  Episode? getWatchedEpisode(String anilistId, String episodeOrChapterNumber) {
    OfflineMedia? anime = getAnimeById(anilistId);
    if (anime != null) {
      Episode? episode = anime.watchedEpisodes
          ?.firstWhereOrNull((e) => e.number == episodeOrChapterNumber);
      if (episode != null) {
        Logger.i("Found Episode! Episode Number is ${episode.number}");
        Logger.i(episode.timeStampInMilliseconds.toString());
        return episode;
      } else {
        Logger.i(
            'No watched episode with number $episodeOrChapterNumber found for anime with ID: $anilistId');
        return null;
      }
    }
    return null;
  }





  void clearCache() {
    _offlineStorageBox.clear();
    animeLibrary.clear();
    animeCustomLists.value.clear();
    animeCustomListData.value.clear();
  }
}

class CustomListData {
  String listName;
  List<OfflineMedia> listData;

  CustomListData({required this.listData, required this.listName});
}
