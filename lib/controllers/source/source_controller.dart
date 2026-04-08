// ignore_for_file: unnecessary_null_comparison, invalid_use_of_protected_member

import 'package:nyantv/screens/search/source_search_page.dart';
import 'package:nyantv/utils/extension_utils.dart';
import 'package:nyantv/utils/logger.dart';
import 'dart:async';
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:dartotsu_extension_bridge/Services/Aniyomi/AniyomiExtensions.dart';
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
  final _widgetCache = <int, Widget>{};

  final isExtensionsServiceAllowed = false.obs;
  final RxString _activeAnimeRepo = ''.obs;
  final RxString _activeAniyomiAnimeRepo = ''.obs;
  final shouldShowExtensions = false.obs;

  Future<void>? _repoRefreshTask;
  Timer? _rebuildTimer;
  bool _homeReady = false;

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

  void setAnimeRepo(String val, String managerId) {
    if (managerId == 'aniyomi') {
      activeAniyomiAnimeRepo = val;
    } else {
      activeAnimeRepo = val;
    }
  }

  String getAnimeRepo(String managerId) {
    if (managerId == 'aniyomi') {
      return activeAniyomiAnimeRepo;
    } else {
      return activeAnimeRepo;
    }
  }

  void saveRepoSettings() {
    final box = Hive.box('themeData');
    box.put("activeAnimeRepo", _activeAnimeRepo.value);
    box.put("activeAniyomiAnimeRepo", _activeAniyomiAnimeRepo.value);
    _refreshVisibility();
  }

  void _refreshVisibility() {
    shouldShowExtensions.value = _activeAnimeRepo.value.isNotEmpty ||
        _activeAniyomiAnimeRepo.value.isNotEmpty ||
        installedExtensions.isNotEmpty;
  }

  @override
  void onInit() {
    super.onInit();
    _initialize();
  }

  @override
  void onClose() {
    _rebuildTimer?.cancel();
    super.onClose();
  }

  void _initialize() async {
    isar = await StorageProvider().initDB(null);
    await DartotsuExtensionBridge().init(isar, 'NyanTV');

    final em = Get.find<ExtensionManager>();

    void registerAniyomiHandler() {
      final aniyomi = em.findById('aniyomi');
      if (aniyomi is AniyomiExtensions &&
          aniyomi.onUninstallRequested == null) {
        aniyomi.onUninstallRequested = (packageName) async {
          const channel = MethodChannel('app.nyantv/uninstall');
          await channel
              .invokeMethod('uninstallPackage', {'package': packageName});
        };
        Logger.i('Aniyomi uninstall handler registered');
      }
    }

    registerAniyomiHandler();
    ever(em.managers, (_) => registerAniyomiHandler());

    ever(em.installedAnimeExtensions, (list) {
      installedExtensions.value = list;
      installedDownloaderExtensions.value =
          list.where((e) => e.name?.contains('Downloader') ?? false).toList();
      _refreshVisibility();
      if (_homeReady) _syncSections();
    });

    ever(em.availableAnimeExtensions, (list) {
      availableExtensions.value = list;
    });

    await initExtensions();
    if (Get.find<ServiceHandler>().serviceType.value ==
        ServicesType.extensions) {
      fetchHomePage();
    }
    if (Get.context != null) {
      checkForUpdates(Get.context!);
    }
  }

  Future<void> checkForUpdates(BuildContext context) async {
    try {
      await fetchRepos();
      final updates = <Source>[];
      for (final source in installedExtensions) {
        final available =
            availableExtensions.firstWhereOrNull((s) => s.id == source.id);
        if (available != null &&
            (available.version ?? '') != (source.version ?? '')) {
          updates.add(available);
        }
      }
      if (updates.isNotEmpty) {
        snackString("Updates available for ${updates.length} extensions");
      }
    } catch (e) {
      Logger.e('Error checking for updates: $e');
    }
  }

  Future<void> sortAnimeExtensions() async {
    final em = Get.find<ExtensionManager>();
    installedExtensions.value = em.installedAnimeExtensions.value;
    availableExtensions.value = em.availableAnimeExtensions.value;
    installedDownloaderExtensions.value = installedExtensions
        .where((e) => e.name?.contains('Downloader') ?? false)
        .toList();
  }

  Future<void> initExtensions({bool refresh = true}) async {
    try {
      await sortAnimeExtensions();
      final box = Hive.box('themeData');
      final savedId = box.get('activeSourceId', defaultValue: '') as String?;
      isExtensionsServiceAllowed.value =
          box.get('extensionsServiceAllowed', defaultValue: false);

      if (installedExtensions.isEmpty &&
          savedId != null &&
          savedId.isNotEmpty) {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (
            installedExtensions.isEmpty && DateTime.now().isBefore(deadline)) {
          await Future.delayed(const Duration(milliseconds: 200));
          await sortAnimeExtensions();
        }
      }

      activeSource.value = installedExtensions
              .firstWhereOrNull((s) => s.id.toString() == savedId) ??
          installedExtensions.firstOrNull;

      _activeAnimeRepo.value = box.get("activeAnimeRepo", defaultValue: '');
      _activeAniyomiAnimeRepo.value =
          box.get("activeAniyomiAnimeRepo", defaultValue: '');

      _refreshVisibility();
      Logger.i('Extensions initialized.');
    } catch (e) {
      Logger.i('Error initializing extensions: $e');
    }
  }

  void setActiveSource(Source source) {
    activeSource.value = source;
    Hive.box('themeData').put('activeSourceId', source.id.toString());
    lastUpdatedSource.value = 'ANIME';
  }

  List<Source> getInstalledExtensions(ItemType type) => installedExtensions;
  List<Source> getAvailableExtensions(ItemType type) => availableExtensions;

  Future<void> fetchRepos() async {
    final active = _repoRefreshTask;
    if (active != null) {
      await active;
      return;
    }

    final task = _doFetchRepos();
    _repoRefreshTask = task;
    try {
      await task;
    } finally {
      if (identical(_repoRefreshTask, task)) _repoRefreshTask = null;
    }
  }

  Future<void> _doFetchRepos() async {
    final em = Get.find<ExtensionManager>();
    await em.refreshExtensions(refreshAvailableSource: true);
    await initExtensions();
  }

  Source? getExtensionByValue(String value) {
    final match = installedExtensions.firstWhereOrNull(
      (s) => '${s.name} (${s.lang?.toUpperCase()})' == value || s.name == value,
    );
    if (match != null) {
      activeSource.value = match;
      Hive.box('themeData').put('activeSourceId', match.id);
      return match;
    }
    lastUpdatedSource.value = 'ANIME';
    return null;
  }

  void _buildOfflineSections() {
    final offlineStorage = Get.find<OfflineStorageController>();
    _homeSections.value = [
      Obx(() => buildSection(
            "Continue Watching",
            offlineStorage.animeLibrary
                .where((e) => e.serviceIndex == ServicesType.extensions.index)
                .toList(),
            variant: DataVariant.offline,
          )),
    ];
  }

  void _syncSections() {
    final liveIds = {for (final s in installedExtensions) s.id};
    final cachedIds = _widgetCache.keys.toSet();

    final added = liveIds.difference(cachedIds);
    final removed = cachedIds.difference(liveIds);

    if (added.isEmpty && removed.isEmpty) return;

    for (final id in removed) {
      _widgetCache.remove(id);
    }

    for (final src in installedExtensions.where((s) => added.contains(s.id))) {
      _widgetCache[int.tryParse(src.id?.toString() ?? '') ?? src.id.hashCode] =
          buildFutureSection(
        src.name ?? '??',
        src.methods.getPopular(1).then((r) => r.list),
        type: ItemType.anime,
        variant: DataVariant.extension,
        source: src,
      );
    }

    _animeSections.value = [
      if (_widgetCache.isNotEmpty)
        CustomSearchBar(
          disableIcons: true,
          onSubmitted: (v) =>
              SourceSearchPage(initialTerm: v, type: ItemType.anime).go(),
        ),
      ..._widgetCache.values,
    ];
  }

  @override
  RxList<Widget> animeWidgets(BuildContext context) =>
      [Obx(() => Column(children: _animeSections.value))].obs;

  @override
  RxList<Widget> homeWidgets(BuildContext context) =>
      [Obx(() => Column(children: _homeSections.value))].obs;

  @override
  Future<void> fetchHomePage() async {
    try {
      _buildOfflineSections();
      _homeReady = true;
      _syncSections();
    } catch (error) {
      Logger.i('Error in fetchHomePage: $error');
      errorSnackBar('Failed to fetch data from sources.');
    }
  }

  @override
  Future<Media> fetchDetails(FetchDetailsParams params) async {
    final data =
        await activeSource.value!.methods.getDetail(DMedia.withUrl(params.id));
    if (serviceHandler.serviceType.value != ServicesType.extensions) {
      cacheController.addCache(data.toJson());
    }
    return Media.froDMedia(data, ItemType.anime);
  }

  @override
  Future<List<Media>> search(SearchParams params) async {
    final data =
        (await activeSource.value!.methods.search(params.query, 1, [])).list;
    return data.map((e) => Media.froDMedia(e, ItemType.anime)).toList();
  }
}
