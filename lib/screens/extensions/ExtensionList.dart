import 'dart:async';
import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:nyantv/utils/language.dart';
import 'package:nyantv/widgets/custom_widgets/custom_button.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/material.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:grouped_list/sliver_grouped_list.dart';
import 'package:get/get.dart';
import 'ExtensionItem.dart';

class ExtensionList extends StatefulWidget {
  final bool installed;
  final ItemType itemType;
  final String query;
  final String selectedLanguage;
  final bool showRecommended;
  final RxInt? reloadTrigger;
  final RxInt? focusFirstItemTrigger;

  const ExtensionList({
    required this.installed,
    required this.query,
    required this.itemType,
    required this.selectedLanguage,
    this.showRecommended = true,
    this.reloadTrigger,
    this.focusFirstItemTrigger,
    super.key,
  });

  @override
  State<ExtensionList> createState() => _ExtensionListState();
}

class _ExtensionListState extends State<ExtensionList>
    with AutomaticKeepAliveClientMixin {
  final controller = ScrollController();

  final RxList<Source> _installedEntries = <Source>[].obs;
  final RxList<Source> _updateEntries = <Source>[].obs;
  final RxList<Source> _notInstalledEntries = <Source>[].obs;
  final RxList<Source> _recommendedEntries = <Source>[].obs;
  final FocusNode _firstItemFocusNode = FocusNode();
  Source? _firstVisibleItem;

  List<Worker> _workers = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _computeAllData();
    _setupReactiveListeners();
  }

  void _setupReactiveListeners() {
    _workers = [
      ever(sourceController.installedExtensions, (_) => _computeAllData()),
      ever(sourceController.availableExtensions, (_) => _computeAllData()),
      if (widget.reloadTrigger != null)
        ever(widget.reloadTrigger!, (_) => _computeAllData()),
      if (widget.focusFirstItemTrigger != null)
        ever(widget.focusFirstItemTrigger!, (_) {
          controller.jumpTo(0);
          _firstItemFocusNode.requestFocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (!_firstItemFocusNode.hasFocus) {
              Future.microtask(() {
                if (!mounted) return;
                _firstItemFocusNode.requestFocus();
              });
            }
          });
        }),
    ];
  }

  Source? _getFirstOfNotInstalled(List<Source> list) {
    if (list.isEmpty) return null;
    final grouped = <String, List<Source>>{};
    for (final s in list) {
      final lang = completeLanguageName(s.lang!.toLowerCase());
      grouped.putIfAbsent(lang, () => []).add(s);
    }
    final sortedGroups = grouped.keys.toList()..sort();
    final firstGroup = grouped[sortedGroups.first]!;
    firstGroup.sort((a, b) => a.name!.compareTo(b.name!));
    return firstGroup.first;
  }

//  RxList<Source> _getRelevantExtensionList() {
//    return sourceController.installedExtensions;
//  }

  @override
  void dispose() {
    controller.dispose();
    _firstItemFocusNode.dispose();
    for (final w in _workers) {
      w.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(ExtensionList oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.query != widget.query ||
        oldWidget.selectedLanguage != widget.selectedLanguage ||
        oldWidget.itemType != widget.itemType ||
        oldWidget.installed != widget.installed) {
      _computeAllData();
    }
  }

  void _computeAllData() {
    if (!mounted) return;

    _installedEntries.value = _computeInstalledEntries();
    _updateEntries.value = _computeUpdateEntries();
    _notInstalledEntries.value = _computeNotInstalledEntries();

    if (widget.showRecommended) {
      _recommendedEntries.value = _computeRecommendedEntries();
    } else {
      _recommendedEntries.clear();
    }
    if (widget.showRecommended && _recommendedEntries.isNotEmpty) {
      _firstVisibleItem = _getFirstSorted(_recommendedEntries);
    } else if (widget.installed && _updateEntries.isNotEmpty) {
      _firstVisibleItem = _getFirstSorted(_updateEntries);
    } else if (widget.installed && _installedEntries.isNotEmpty) {
      _firstVisibleItem = _getFirstSorted(_installedEntries);
    } else if (_notInstalledEntries.isNotEmpty) {
      _firstVisibleItem = _getFirstOfNotInstalled(_notInstalledEntries);
    } else {
      _firstVisibleItem = null;
    }
  }

  Future<void> _refreshData() async {
    await sourceController.fetchRepos();
    if (!mounted) return;
    _computeAllData();
  }

  List<Source> get _allAvailableExtensions {
    return sourceController.getAvailableExtensions(widget.itemType);
  }

  List<Source> get _installedExtensions {
    return sourceController.getInstalledExtensions(widget.itemType);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Obx(() {
          final installedEntries = _installedEntries.value;
          final updateEntries = _updateEntries.value;
          final notInstalledEntries = _notInstalledEntries.value;
          final recommendedEntries = _recommendedEntries.value;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: CustomScrollView(
              controller: controller,
              physics: const ClampingScrollPhysics(),
              slivers: [
                if (widget.showRecommended && recommendedEntries.isNotEmpty)
                  _buildRecommendedList(recommendedEntries),
                if (widget.installed && updateEntries.isNotEmpty)
                  _buildUpdatePendingList(updateEntries),
                if (widget.installed && installedEntries.isNotEmpty)
                  _buildInstalledList(installedEntries),
                if (!widget.installed && notInstalledEntries.isNotEmpty)
                  _buildNotInstalledList(notInstalledEntries),
                if (_isEmpty(installedEntries, updateEntries,
                    notInstalledEntries, recommendedEntries))
                  const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text(
                          'No extensions found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  bool _isEmpty(List<Source> installed, List<Source> updates,
      List<Source> notInstalled, List<Source> recommended) {
    if (widget.installed) {
      return installed.isEmpty && updates.isEmpty;
    } else {
      return notInstalled.isEmpty &&
          (!widget.showRecommended || recommended.isEmpty);
    }
  }

  List<Source> _filterData(List<Source> data) {
    if (data.isEmpty) return data;

    return data.where((element) {
      if (widget.selectedLanguage != 'all') {
        final elementLang = element.lang?.toLowerCase() ?? '';
        final targetLang = completeLanguageCode(widget.selectedLanguage);
        if (elementLang != targetLang) return false;
      }

      if (widget.query.isNotEmpty) {
        final elementName = element.name?.toLowerCase() ?? '';
        final query = widget.query.toLowerCase();
        if (!elementName.contains(query)) return false;
      }

      return true;
    }).toList();
  }

  List<Source> _computeNotInstalledEntries() {
    final availableExtensions = _allAvailableExtensions;
    final installedExtensions = _installedExtensions;

    if (availableExtensions.isEmpty) return [];

    final installedSet =
        installedExtensions.map((e) => '${e.name}_${e.lang}').toSet();

    final notInstalled = availableExtensions.where((available) {
      final key = '${available.name}_${available.lang}';
      return !installedSet.contains(key);
    }).toList();

    return _filterData(notInstalled);
  }

  List<Source> _computeInstalledEntries() {
    final installedExtensions = _installedExtensions;
    final withoutPendingUpdates =
        installedExtensions.where((e) => e.hasUpdate != true).toList();
    return _filterData(withoutPendingUpdates);
  }

  List<Source> _computeUpdateEntries() {
    final installedExtensions = _installedExtensions;
    final availableExtensions = _allAvailableExtensions;
    if (installedExtensions.isEmpty) return [];

    final updateAvailable = installedExtensions.where((installed) {
      if (installed.hasUpdate == true) return true;

      final available = availableExtensions.firstWhereOrNull(
        (a) => a.name == installed.name && a.lang == installed.lang,
      );
      if (available == null) return false;

      return _isNewerVersion(available.version, installed.version);
    }).toList();

    return _filterData(updateAvailable);
  }

  bool _isNewerVersion(String? available, String? installed) {
    if (available == null || installed == null) return false;
    try {
      final aParts = available
          .replaceAll(RegExp(r'[^0-9.]'), '')
          .split('.')
          .map(int.parse)
          .toList();
      final iParts = installed
          .replaceAll(RegExp(r'[^0-9.]'), '')
          .split('.')
          .map(int.parse)
          .toList();
      for (int i = 0; i < aParts.length && i < iParts.length; i++) {
        if (aParts[i] > iParts[i]) return true;
        if (aParts[i] < iParts[i]) return false;
      }
      return aParts.length > iParts.length;
    } catch (_) {
      return false;
    }
  }

  List<Source> _computeRecommendedEntries() {
    const extens = ['nyantv'];
    const preferredLangs = {'en', 'all', 'multi'};

    final availableExtensions = _allAvailableExtensions;

    if (availableExtensions.isEmpty) return [];

    final recommended = availableExtensions.where((element) {
      final name = element.name?.toLowerCase() ?? '';
      final lang = element.lang?.toLowerCase() ?? '';

      final matchesExtension = extens.any((ext) => name.contains(ext));
      final matchesLanguage = preferredLangs.contains(lang);

      return matchesExtension && matchesLanguage;
    }).toList();

    return _filterData(recommended);
  }

  Widget _buildUpdatePendingList(List<Source> updateEntries) {
    return SliverGroupedListView<Source, String>(
      elements: updateEntries,
      groupBy: (element) => "",
      groupSeparatorBuilder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Update Pending',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            NyanTVButton(
              variant: ButtonVariant.outline,
              onTap: () => _updateAllExtensions(updateEntries),
              child: const Text(
                'Update All',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      itemBuilder: (context, Source element) {
        final isFirst = _firstVisibleItem != null &&
            element.name == _firstVisibleItem!.name &&
            element.lang == _firstVisibleItem!.lang;

        return ExtensionListTileWidget(
          key: ValueKey('update_${element.id ?? element.name}_${element.lang}'),
          source: element,
          mediaType: widget.itemType,
          onUpdate: _refreshData,
          primaryFocusNode: isFirst ? _firstItemFocusNode : null,
        );
      },
      groupComparator: (group1, group2) => group1.compareTo(group2),
      itemComparator: (item1, item2) => item1.name!.compareTo(item2.name!),
      order: GroupedListOrder.ASC,
    );
  }

  Future<void> _updateAllExtensions(List<Source> updateEntries) async {
    if (updateEntries.isEmpty) return;
    try {
      await Future.wait(updateEntries.map((source) => source.update()));
      _computeAllData();
    } catch (e) {
      debugPrint('Error updating extensions: $e');
    }
  }

  Source? _getFirstSorted(List<Source> list) {
    if (list.isEmpty) return null;
    final sorted = [...list]..sort((a, b) => a.name!.compareTo(b.name!));
    return sorted.first;
  }

  Widget _buildInstalledList(List<Source> installedEntries) {
    return SliverGroupedListView<Source, String>(
      elements: installedEntries,
      groupBy: (element) => "",
      groupSeparatorBuilder: (_) => const SizedBox(height: 8),
      itemBuilder: (context, Source element) {
        final isFirst = _firstVisibleItem != null &&
            element.name == _firstVisibleItem!.name &&
            element.lang == _firstVisibleItem!.lang;

        return ExtensionListTileWidget(
          key: ValueKey(
              'installed_${element.id ?? element.name}_${element.lang}'),
          source: element,
          mediaType: widget.itemType,
          onUpdate: _refreshData,
          primaryFocusNode: isFirst ? _firstItemFocusNode : null,
        );
      },
      groupComparator: (group1, group2) => group1.compareTo(group2),
      itemComparator: (item1, item2) => item1.name!.compareTo(item2.name!),
      order: GroupedListOrder.ASC,
    );
  }

  Widget _buildRecommendedList(List<Source> recommendedEntries) {
    return SliverGroupedListView<Source, String>(
      elements: recommendedEntries,
      groupBy: (element) => "",
      groupSeparatorBuilder: (_) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(
              'Recommended',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
      itemBuilder: (context, Source element) {
        final isFirst = _firstVisibleItem != null &&
            element.name == _firstVisibleItem!.name &&
            element.lang == _firstVisibleItem!.lang;

        return ExtensionListTileWidget(
          key: ValueKey(
              'recommended_${element.id ?? element.name}_${element.lang}'),
          source: element,
          mediaType: widget.itemType,
          onUpdate: _refreshData,
          primaryFocusNode: isFirst ? _firstItemFocusNode : null,
        );
      },
      groupComparator: (group1, group2) => group1.compareTo(group2),
      itemComparator: (item1, item2) => item1.name!.compareTo(item2.name!),
      order: GroupedListOrder.ASC,
    );
  }

  Widget _buildNotInstalledList(List<Source> notInstalledEntries) {
    return SliverGroupedListView<Source, String>(
      elements: notInstalledEntries,
      groupBy: (element) => completeLanguageName(element.lang!.toLowerCase()),
      groupSeparatorBuilder: (String groupByValue) => Padding(
        padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
        child: Row(
          children: [
            Text(
              groupByValue,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
      itemBuilder: (context, Source element) {
        final isFirst = _firstVisibleItem != null &&
            element.name == _firstVisibleItem!.name &&
            element.lang == _firstVisibleItem!.lang;

        return ExtensionListTileWidget(
          key: ValueKey(
              'not_installed_${element.id ?? element.name}_${element.lang}'),
          source: element,
          mediaType: widget.itemType,
          onUpdate: _refreshData,
          primaryFocusNode: isFirst ? _firstItemFocusNode : null,
        );
      },
      groupComparator: (group1, group2) => group1.compareTo(group2),
      itemComparator: (item1, item2) => item1.name!.compareTo(item2.name!),
      order: GroupedListOrder.ASC,
    );
  }
}
