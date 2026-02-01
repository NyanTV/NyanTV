import 'package:nyantv/controllers/offline/offline_storage_controller.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:nyantv/models/Media/media.dart';
import 'package:nyantv/models/Offline/Hive/offline_media.dart';
import 'package:nyantv/screens/anime/details_page.dart';
import 'package:nyantv/screens/library/editor/list_editor.dart';
import 'package:nyantv/screens/library/widgets/history_model.dart';
import 'package:nyantv/screens/library/widgets/library_deps.dart';
import 'package:nyantv/screens/settings/widgets/history_card_gate.dart';
import 'package:nyantv/screens/settings/widgets/history_card_selector.dart';
import 'package:nyantv/utils/extension_utils.dart';
import 'package:nyantv/utils/function.dart';
import 'package:nyantv/widgets/common/cards/base_card.dart';
import 'package:nyantv/widgets/common/cards/card_gate.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_bottomsheet.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_chip.dart';
import 'package:nyantv/widgets/custom_widgets/custom_expansion_tile.dart';
import 'package:nyantv/widgets/exceptions/empty_library.dart';
import 'package:nyantv/widgets/helper/platform_builder.dart';
import 'package:nyantv/widgets/custom_widgets/custom_text.dart';
import 'package:nyantv/widgets/helper/tv_wrapper.dart';
import 'package:nyantv/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconly/iconly.dart';
import 'package:iconsax/iconsax.dart';

enum SortType {
  title,
  lastAdded,
  lastWatched,
  rating,
}

String _getTypeLabel(ItemType itemType) {
  return 'Anime';
}

IconData _getTypeIcon(ItemType itemType) {
  return Icons.movie_filter_rounded;
}

class MyLibrary extends StatefulWidget {
  const MyLibrary({super.key});

  @override
  State<MyLibrary> createState() => _MyLibraryState();
}

class _MyLibraryState extends State<MyLibrary> {
  final TextEditingController controller = TextEditingController();
  final offlineStorage = Get.find<OfflineStorageController>();
  final gridCount = 0.obs;

  RxList<CustomListData> customListData = <CustomListData>[].obs;
  RxList<CustomListData> initialCustomListData = <CustomListData>[].obs;
  RxList<OfflineMedia> filteredData = <OfflineMedia>[].obs;
  RxList<OfflineMedia> historyData = <OfflineMedia>[].obs;

  RxString searchQuery = ''.obs;
  RxInt selectedListIndex = 0.obs;
  Rx<ItemType> type = ItemType.anime.obs;

  @override
  void initState() {
    super.initState();
    _initLibraryData();
    _getPreferences();
    ever(offlineStorage.animeCustomLists, (_) => _initLibraryData());
  }

  void _initLibraryData() {
    customListData.value = offlineStorage.animeCustomListData.value
        .map((e) => CustomListData(
              listName: e.listName,
              listData: e.listData.toList(),
            ))
        .toList();

    historyData.value = offlineStorage.animeLibrary
        .where((e) => e.currentEpisode?.currentTrack != null)
        .toList();

    initialCustomListData.value = customListData;
  }

  void _getPreferences() {
    currentSort = SortType.values[settingsController.preferences.get(
        'anime_sort_type',
        defaultValue: SortType.lastWatched.index)];
    isAscending = settingsController.preferences
        .get('anime_sort_order', defaultValue: true);
    gridCount.value = settingsController.preferences
        .get('anime_grid_size', defaultValue: 0);
  }

  void _savePreferences() {
    settingsController.preferences
        .put('anime_sort_type', currentSort.index);
    settingsController.preferences
        .put('anime_sort_order', isAscending);
    settingsController.preferences
        .put('anime_grid_size', gridCount.value);
  }

  void _search(String val) {
    searchQuery.value = val;
    final currentIndex = selectedListIndex.value;

    final initialData = customListData[currentIndex].listData;
    filteredData.value = initialData
        .where(
            (e) => e.name?.toLowerCase().contains(val.toLowerCase()) ?? false)
        .toList();
  }

  void _switchCategory(ItemType typ) {
    type.value = typ;
    selectedListIndex.value = 0;
    if (searchQuery.isNotEmpty) {
      controller.clear();
      searchQuery.value = '';
    }
    _getPreferences();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 28.0),
              child: _buildHeader(),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildChipTabs(),
          ),
          _buildSliverTabsBody(),
        ],
      ),
    );
  }

  double getCardHeight(CardStyle style) {
    final isDesktop = getPlatform(context);
    switch (style) {
      case CardStyle.modern:
        return isDesktop ? 220 : 170;
      case CardStyle.exotic:
        return isDesktop ? 270 : 210;
      case CardStyle.saikou:
        return isDesktop ? 270 : 230;
      case CardStyle.minimalExotic:
        return isDesktop ? 250 : 280;
      default:
        return isDesktop ? 230 : 170;
    }
  }

  SliverGridDelegateWithFixedCrossAxisCount getSliverDel() {
    if (gridCount.value == 0) {
      if (getPlatform(context)) {
        return SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: getResponsiveCrossAxisVal(
                MediaQuery.of(context).size.width - 120,
                itemWidth: 170),
            crossAxisSpacing: 10,
            mainAxisSpacing: 20,
            mainAxisExtent:
                getCardHeight(CardStyle.values[settingsController.cardStyle]));
      } else {
        return const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 20,
            childAspectRatio: 2 / 3);
      }
    }

    if (gridCount.value == 2) {
      return SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridCount.value,
        crossAxisSpacing: 10,
        mainAxisSpacing: 20,
        childAspectRatio: 2 / 3,
      );
    }
    if (getPlatform(context)) {
      return SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridCount.value,
          crossAxisSpacing: 10,
          mainAxisSpacing: 20,
          mainAxisExtent:
              getCardHeight(CardStyle.values[settingsController.cardStyle]));
    } else {
      return SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridCount.value,
          crossAxisSpacing: 10,
          mainAxisSpacing: 20,
          mainAxisExtent:
              (MediaQuery.of(context).size.width / gridCount.value) * (3 / 2) +
                  10);
    }
  }

  Widget _buildSliverTabsBody() {
    return Obx(() {
      if (selectedListIndex.value != -1) {
        final currentIndex = selectedListIndex.value;
        final lists = customListData;
        final isEmpty = lists.isEmpty || lists[currentIndex].listData.isEmpty;
        final items = searchQuery.isNotEmpty
            ? filteredData
            : (lists.isEmpty ? [] : lists[currentIndex].listData);

        return isEmpty
            ? const SliverToBoxAdapter(child: EmptyLibrary())
            : SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
                sliver: SliverGrid(
                  gridDelegate: getSliverDel(),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final tag = getRandomTag(addition: i.toString());
                      OfflineMedia item = items[i];
                      return NyantvOnTap(
                        margin: 0,
                        scale: 1,
                        onTap: () {
                          navigate(() => AnimeDetailsPage(
                              media: Media.fromOfflineMedia(
                                  item, ItemType.anime),
                              tag: tag));
                        },
                        child: MediaCardGate(
                            itemData: items[i],
                            tag: '${getRandomTag()}-$i',
                            variant: DataVariant.library,
                            type: ItemType.anime,
                            cardStyle:
                                CardStyle.values[settingsController.cardStyle]),
                      );
                    },
                    childCount: items.length,
                  ),
                ),
              );
      } else {
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: getResponsiveCrossAxisVal(
                    MediaQuery.of(context).size.width - 120,
                    itemWidth: 400),
                crossAxisSpacing: 10,
                mainAxisSpacing: 0,
                mainAxisExtent: getHistoryCardHeight(
                    HistoryCardStyle
                        .values[settingsController.historyCardStyle],
                    context)),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final historyModel =
                    HistoryModel.fromOfflineMedia(historyData[i], ItemType.anime);
                return HistoryCardGate(
                  data: historyModel,
                  cardStyle: HistoryCardStyle
                      .values[settingsController.historyCardStyle],
                );
              },
              childCount: historyData.length,
            ),
          ),
        );
      }
    });
  }

  Padding _buildChipTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Obx(() {
          final historyCount = historyData.length;

          return Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: NyantvIconChip(
                icon: Row(
                  children: [
                    Icon(
                        selectedListIndex.value == -1
                            ? Iconsax.clock5
                            : Iconsax.clock,
                        color: selectedListIndex.value == -1
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurfaceVariant),
                    5.width(),
                    NyantvText(text: '($historyCount)')
                  ],
                ),
                isSelected: selectedListIndex.value == -1,
                onSelected: (selected) {
                  if (selected) {
                    selectedListIndex.value = -1;
                    if (searchQuery.isNotEmpty) {
                      controller.clear();
                      searchQuery.value = '';
                    }
                  }
                },
              ),
            ),
            ...List.generate(
              customListData.length,
              (index) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: NyantvChip(
                  label:
                      '${customListData[index].listName} (${customListData[index].listData.length})',
                  isSelected: selectedListIndex.value == index,
                  onSelected: (selected) {
                    if (selected) {
                      selectedListIndex.value = index;
                      if (searchQuery.isNotEmpty) {
                        controller.clear();
                        searchQuery.value = '';
                      }
                    }
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: NyantvIconChip(
                icon: Row(
                  children: [
                    Icon(Iconsax.edit,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    5.width(),
                    const NyantvText(text: 'Edit')
                  ],
                ),
                isSelected: false,
                onSelected: (selected) {
                  navigate(() => CustomListsEditor(type: ItemType.anime));
                },
              ),
            ),
          ]);
        }),
      ),
    );
  }

  final RxBool isSearchActive = false.obs;

  Widget _buildSegmentedControl() {
    final availableTypes = [ItemType.anime];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: availableTypes.map((itemType) {
          final isSelected = type.value == itemType;
          return Expanded(
            child: GestureDetector(
              onTap: () => _switchCategory(itemType),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        _getTypeIcon(itemType),
                        key: ValueKey('${itemType.name}_icon'),
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontFamily: "Poppins-Bold",
                          fontSize: 14,
                          color: isSelected
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        child: Text(
                          _getTypeLabel(itemType),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeader() {
    return Obx(() => Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      AnimatedSlide(
                        offset: isSearchActive.value
                            ? const Offset(-1.0, 0)
                            : Offset.zero,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOutCubic,
                        child: AnimatedOpacity(
                          opacity: isSearchActive.value ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Library',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: "Poppins-Bold",
                                ),
                              ),
                              Text(
                                'Discover your favorite anime',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        width: isSearchActive.value
                            ? MediaQuery.of(context).size.width * 0.7
                            : 0,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        child: AnimatedOpacity(
                          opacity: isSearchActive.value ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          child: Row(
                            children: [
                              TweenAnimationBuilder<double>(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.elasticOut,
                                tween: Tween<double>(
                                  begin: 0.0,
                                  end: isSearchActive.value ? 1.0 : 0.0,
                                ),
                                builder: (context, value, child) {
                                  return Transform.scale(
                                    scale: value,
                                    child: child,
                                  );
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    onPressed: () {
                                      isSearchActive.value = false;
                                    },
                                    icon: Icon(Icons.arrow_back_ios_new,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary),
                                    constraints: const BoxConstraints(
                                      minHeight: 40,
                                      minWidth: 40,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  child: CustomSearchBar(
                                    controller: controller,
                                    onChanged: _search,
                                    hintText: 'Search Anime...',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                          return ScaleTransition(
                            scale: animation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: !isSearchActive.value
                            ? Container(
                                key: const ValueKey('searchButton'),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: IconButton(
                                  onPressed: () {
                                    isSearchActive.value = true;
                                  },
                                  icon: Icon(IconlyLight.search,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary),
                                ),
                              )
                            : const SizedBox(
                                key: ValueKey('emptySearch'), width: 0),
                      ),
                      TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        tween: Tween<double>(
                          begin: 0.9,
                          end: 1.0,
                        ),
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value,
                            child: child,
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: () {
                              showSortingSettings();
                            },
                            icon: Icon(Icons.sort,
                                color: Theme.of(context).colorScheme.onPrimary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSegmentedControl(),
            ],
          ),
        ));
  }

  void showSortingSettings() => NyantvSheet(
        title: 'Settings',
        contentWidget: StatefulBuilder(
          builder: (context, setState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NyantvExpansionTile(
                        title: 'Sort By',
                        initialExpanded: true,
                        content: Column(children: [
                          Row(
                            children: [
                              _buildSortBox(
                                title: 'Title',
                                currentSort: currentSort,
                                sortType: SortType.title,
                                isAscending: isAscending,
                                onTap: () =>
                                    _handleSortChange(SortType.title, setState),
                                icon: Icons.sort_by_alpha,
                              ),
                              _buildSortBox(
                                title: 'Last Added',
                                currentSort: currentSort,
                                sortType: SortType.lastAdded,
                                isAscending: isAscending,
                                onTap: () => _handleSortChange(
                                    SortType.lastAdded, setState),
                                icon: Icons.add_circle_outline,
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              _buildSortBox(
                                title: 'Last Watched',
                                currentSort: currentSort,
                                sortType: SortType.lastWatched,
                                isAscending: isAscending,
                                onTap: () => _handleSortChange(
                                    SortType.lastWatched, setState),
                                icon: Icons.visibility,
                              ),
                              _buildSortBox(
                                title: 'Rating',
                                currentSort: currentSort,
                                sortType: SortType.rating,
                                isAscending: isAscending,
                                onTap: () => _handleSortChange(
                                    SortType.rating, setState),
                                icon: Icons.star_border,
                              ),
                            ],
                          ),
                        ])),
                    NyantvExpansionTile(
                        title: 'Grid',
                        content: Column(
                          children: [
                            Obx(() {
                              return CustomSliderTile(
                                  icon: Icons.grid_view_rounded,
                                  title: 'Grid Size',
                                  description: 'Adjust Items per row',
                                  sliderValue: gridCount.value.toDouble(),
                                  onChanged: (e) {
                                    gridCount.value = e.toInt();
                                    _savePreferences();
                                  },
                                  max: getResponsiveSize(context,
                                      mobileSize: 4, desktopSize: 10));
                            })
                          ],
                        ))
                  ],
                ),
              ),
            );
          },
        ),
      ).show(context);

  SortType currentSort = SortType.lastAdded;
  bool isAscending = false;

  Widget _buildSortBox({
    required String title,
    required SortType currentSort,
    required SortType sortType,
    required bool isAscending,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    final isSelected = currentSort == sortType;
    final theme = Theme.of(context);

    return Expanded(
      child: SizedBox(
        height: 90,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Material(
            clipBehavior: Clip.antiAlias,
            elevation: isSelected ? 3 : 0,
            shadowColor: isSelected
                ? theme.colorScheme.primary.withOpacity(0.4)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onTap,
              splashColor: theme.colorScheme.primary.withOpacity(0.15),
              highlightColor: theme.colorScheme.primary.withOpacity(0.05),
              child: Container(
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            theme.colorScheme.primary.withOpacity(0.15),
                            theme.colorScheme.primaryContainer,
                          ],
                        )
                      : null,
                  color: isSelected
                      ? null
                      : theme.colorScheme.surfaceVariant.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withOpacity(0.2),
                    width: isSelected ? 1.5 : 0.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        if (isSelected)
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  theme.colorScheme.primary.withOpacity(0.12),
                            ),
                          ),
                        Icon(
                          icon,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 24,
                        ),
                        if (isSelected)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isAscending
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                color: theme.colorScheme.onPrimary,
                                size: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      child: NyantvText(
                        text: title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleSortChange(SortType sortType, StateSetter setState) {
    if (currentSort == sortType) {
      setState(() {
        isAscending = !isAscending;
      });
    } else {
      setState(() {
        currentSort = sortType;
        isAscending = false;
      });
    }

    _savePreferences();
    _applySorting();
  }

  void _applySorting() {
    if (customListData.isEmpty || selectedListIndex.value >= customListData.length) return;

    final currentList = customListData[selectedListIndex.value];
    final initialList = initialCustomListData[selectedListIndex.value];

    currentList.listData.sort((a, b) {
      int comparison = 0;

      switch (currentSort) {
        case SortType.title:
          // Handle potential null names
          final aName = a.name ?? '';
          final bName = b.name ?? '';
          comparison = aName.compareTo(bName);
          break;
        case SortType.lastWatched:
          final aTime = a.currentEpisode?.lastWatchedTime ?? 0;
          final bTime = b.currentEpisode?.lastWatchedTime ?? 0;
          comparison = aTime.compareTo(bTime);
          break;
        case SortType.rating:
          final aRating = double.tryParse(a.rating ?? '0.0') ?? 0.0;
          final bRating = double.tryParse(b.rating ?? '0.0') ?? 0.0;
          comparison = aRating.compareTo(bRating);
          break;
        case SortType.lastAdded:
          break;
      }

      return isAscending ? comparison : -comparison;
    });

    if (currentSort == SortType.lastAdded) {
      if (isAscending) {
        currentList.listData = initialList.listData.reversed.toList();
      } else {
        currentList.listData = initialList.listData;
      }
    }

    customListData.refresh();
  }
}