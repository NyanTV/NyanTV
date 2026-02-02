// ignore_for_file: unnecessary_null_comparison, invalid_use_of_protected_member

import 'package:nyantv/screens/search/source_search_page.dart';
import 'package:nyantv/utils/extension_utils.dart';
import 'package:nyantv/utils/logger.dart';
import 'dart:async';
import 'dart:io';
import 'package:nyantv/controllers/cacher/cache_controller.dart';
import 'package:nyantv/controllers/service_handler/params.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/controllers/offline/offline_storage_controller.dart';
import 'package:nyantv/controllers/services/widgets/widgets_builders.dart';
import 'package:nyantv/models/Media/media.dart';
import 'package:nyantv/models/Service/base_service.dart';
import 'package:nyantv/utils/function.dart';
import 'package:nyantv/utils/storage_provider.dart';
import 'package:nyantv/widgets/common/search_bar.dart';
import 'package:nyantv/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/Aniyomi/AniyomiExtensions.dart';
import 'package:flutter/material.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_progress.dart';
import 'package:get/get.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:hive/hive.dart';

final sourceController = Get.put(SourceController());

class SourceController extends GetxController implements BaseService {
  var availableExtensions = <Source>[].obs;
  var installedExtensions = <Source>[].obs;
  var activeSource = Rxn<Source>();
  var installedDownloaderExtensions = <Source>[].obs;

  var lastUpdatedSource = "".obs;

  final _animeSections = <Widget>[].obs;
  final _homeSections = <Widget>[].obs;

  final isExtensionsServiceAllowed = false.obs;
  final RxString _activeAnimeRepo = ''.obs;
  final RxString _activeAniyomiAnimeRepo = ''.obs;

  final RxBool shouldShowExtensions = false.obs;

  String get activeAnimeRepo => _activeAnimeRepo.value;
  set activeAnimeRepo(String value) {
    _activeAnimeRepo.value = value;
    saveRepoSettings();
  }

  String get activeAniyomiAnimeRepo => _activeAniyomiAnimeRepo.value;
  set activeAniyomiAnimeRepo(String value) {
    _activeAniyomiAnimeRepo.value = value;
    saveRepoSettings();
  }

  void setAnimeRepo(String val, ExtensionType type) {
    if (type == ExtensionType.aniyomi) {
      Logger.i('Settings Aniyomi repo: $val');
      activeAniyomiAnimeRepo = val;
    } else {
      Logger.i('Settings Anime repo: $val');
      activeAnimeRepo = val;
    }
  }

  String getAnimeRepo(ExtensionType type) {
    if (type == ExtensionType.aniyomi) {
      Logger.i('Getting Aniyomi repo');
      return activeAniyomiAnimeRepo;
    } else {
      Logger.i('Getting Anime repo');
      return activeAnimeRepo;
    }
  }

  void saveRepoSettings() {
    final box = Hive.box('themeData');
    box.put("activeAnimeRepo", _activeAnimeRepo.value);
    box.put("activeAniyomiAnimeRepo", _activeAniyomiAnimeRepo.value);
    shouldShowExtensions.value = [
      _activeAnimeRepo.value,
      _activeAniyomiAnimeRepo.value,
      installedExtensions,
    ].any((e) => (e as dynamic).isNotEmpty);
  }

  @override
  void onInit() {
    super.onInit();

    _initialize();
  }

  void _initialize() async {
    isar = await StorageProvider().initDB(null);
    await DartotsuExtensionBridge().init(isar, 'NyanTV');

    await initExtensions();

    if (Get.find<ServiceHandler>().serviceType.value ==
        ServicesType.extensions) {
      fetchHomePage();
    }
  }

  Future<List<Source>> _getInstalledExtensions(
      Future<List<Source>> Function() fetchFn) async {
    return await fetchFn();
  }

  List<Source> _getAvailableExtensions(List<Source> Function() fetchFn) {
    return fetchFn();
  }

  Future<void> sortAnimeExtensions() async {
    final types = ExtensionType.values.where((e) {
      if (!Platform.isAndroid && e == ExtensionType.aniyomi) return false;
      return true;
    });

    final installed = <Source>[];
    final available = <Source>[];

    for (final type in types) {
      final manager = type.getManager();
      installed.addAll(await _getInstalledExtensions(
          () => manager.getInstalledAnimeExtensions()));
      available.addAll(_getAvailableExtensions(
          () => manager.availableAnimeExtensions.value));
    }

    installedExtensions.value = installed;
    availableExtensions.value = available;

    installedDownloaderExtensions.value = installed
        .where((e) => e.name?.contains('Downloader') ?? false)
        .toList();
  }

  Future<void> sortAllExtensions() async {
    await Future.wait([
      sortAnimeExtensions(),
    ]);
  }

  Future<void> initExtensions({bool refresh = true}) async {
    try {
      await sortAllExtensions();
      final box = Hive.box('themeData');
      final savedActiveSourceId =
          box.get('activeSourceId', defaultValue: '') as String?;
      isExtensionsServiceAllowed.value =
          box.get('extensionsServiceAllowed', defaultValue: false);

      activeSource.value = installedExtensions.firstWhereOrNull(
          (source) => source.id.toString() == savedActiveSourceId);

      activeSource.value ??= installedExtensions.firstOrNull;

      _activeAnimeRepo.value = box.get("activeAnimeRepo", defaultValue: '');
      _activeAniyomiAnimeRepo.value =
          box.get("activeAniyomiAnimeRepo", defaultValue: '');

      shouldShowExtensions.value = [
        _activeAnimeRepo.value,
        _activeAniyomiAnimeRepo.value,
        installedExtensions,
      ].any((e) => (e as dynamic).isNotEmpty);

      Logger.i('Extensions initialized.');
    } catch (e) {
      Logger.i('Error initializing extensions: $e');
    }
  }

  bool isEmpty(dynamic val) => val.isEmpty;

  void setActiveSource(Source source) {
    activeSource.value = source;
    Hive.box('themeData').put('activeSourceId', source.id);
    lastUpdatedSource.value = 'ANIME';
  }

  List<Source> getInstalledExtensions(ItemType type) {
    return installedExtensions;
  }

  List<Source> getAvailableExtensions(ItemType type) {
    return availableExtensions;
  }

  Future<void> fetchRepos() async {
    final extenionTypes = ExtensionType.values.where((e) {
      if (!Platform.isAndroid) {
        if (e == ExtensionType.aniyomi) {
          return false;
        }
      }
      return true;
    }).toList();
    Logger.i(extenionTypes.length.toString());
    if (Platform.isAndroid) {
      Get.put(AniyomiExtensions(), tag: 'AniyomiExtensions');
    }
    for (var type in extenionTypes) {
      await type
          .getManager()
          .fetchAvailableAnimeExtensions([getAnimeRepo(type)]);
    }
    await initExtensions();
  }

  Source? getExtensionByName(String name) {
    final selectedSource = installedExtensions.firstWhereOrNull((source) =>
        '${source.name} (${source.lang?.toUpperCase()})' == name ||
        source.name == name);

    if (selectedSource != null) {
      activeSource.value = selectedSource;
      Hive.box('themeData').put('activeSourceId', selectedSource.id);
      return activeSource.value;
    }
    lastUpdatedSource.value = 'ANIME';
    return null;
  }

  void _initializeEmptySections() {
    final offlineStorage = Get.find<OfflineStorageController>();
    _animeSections.value = [const Center(child: NyantvProgressIndicator())];
    _homeSections.value = [
      Obx(
        () => buildSection(
            "Continue Watching",
            offlineStorage.animeLibrary
                .where((e) => e.serviceIndex == ServicesType.extensions.index)
                .toList(),
            variant: DataVariant.offline),
      ),
    ];
  }

  @override
  RxList<Widget> animeWidgets(BuildContext context) => [
        Obx(() {
          return Column(
            children: _animeSections.value,
          );
        })
      ].obs;

  @override
  RxList<Widget> homeWidgets(BuildContext context) => [
        Obx(() {
          return Column(
            children: _homeSections.value,
          );
        })
      ].obs;

  @override
  Future<void> fetchHomePage() async {
    try {
      _initializeEmptySections();

      for (final source in installedExtensions) {
        _fetchSourceData(source,
            targetSections: _animeSections, type: ItemType.anime);
      }

      Logger.i('Fetched home page data.');
    } catch (error) {
      Logger.i('Error in fetchHomePage: $error');
      errorSnackBar('Failed to fetch data from sources.');
    }
  }

  Future<void> _fetchSourceData(
    Source source, {
    required RxList<Widget> targetSections,
    required ItemType type,
  }) async {
    try {
      final future = source.methods.getPopular(1).then((result) => result.list);

      final newSection = buildFutureSection(
        source.name ?? '??',
        future,
        type: type,
        variant: DataVariant.extension,
        source: source,
      );

      if (targetSections.first is Center) {
        targetSections.value = [];
        targetSections.add(CustomSearchBar(
          disableIcons: true,
          onSubmitted: (v) {
            SourceSearchPage(initialTerm: v, type: type).go();
          },
        ));
      }
      targetSections.add(newSection);

      Logger.i('Data fetched and updated for ${source.name}');
    } catch (e) {
      Logger.i('Error fetching data from ${source.name}: $e');
    }
  }

  @override
  Future<Media> fetchDetails(FetchDetailsParams params) async {
    final id = params.id;
    final data = await activeSource.value!.methods.getDetail(DMedia.withUrl(id));

    if (serviceHandler.serviceType.value != ServicesType.extensions) {
      cacheController.addCache(data.toJson());
    }
    return Media.froDMedia(data, ItemType.anime);
  }

  @override
  Future<List<Media>> search(SearchParams params) async {
    final source = activeSource.value;
    final data = (await source!.methods.search(params.query, 1, [])).list;
    return data.map((e) => Media.froDMedia(e, ItemType.anime)).toList();
  }
}