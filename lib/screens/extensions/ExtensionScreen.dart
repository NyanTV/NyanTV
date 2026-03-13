import 'dart:async';

import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:nyantv/screens/extensions/ExtensionList.dart';
import 'package:nyantv/screens/extensions/widgets/repo_sheet.dart';
import 'package:nyantv/utils/language.dart';
import 'package:nyantv/utils/storage_provider.dart';
import 'package:nyantv/widgets/AlertDialogBuilder.dart';
import 'package:nyantv/widgets/common/glow.dart';
import 'package:nyantv/widgets/common/search_bar.dart';
import 'package:nyantv/widgets/helper/platform_builder.dart';
import 'package:nyantv/widgets/helper/tv_wrapper.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart'
    hide Extension, ExtensionList;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:iconsax/iconsax.dart';

class ExtensionScreen extends StatefulWidget {
  final bool disableGlow;
  const ExtensionScreen({super.key, this.disableGlow = false});

  @override
  State<ExtensionScreen> createState() => _ExtensionScreenState();
}

class _ExtensionScreenState extends State<ExtensionScreen>
    with TickerProviderStateMixin {
  late TabController _tabBarController;
  final _textEditingController = TextEditingController();
  final RxString _selectedLanguage = 'all'.obs;
  final RxMap<String, int> _extensionCounts = <String, int>{}.obs;
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _tab0FocusNode = FocusNode();
  final FocusNode _tab1FocusNode = FocusNode();
  late FocusNode _textFieldFocusNode;
  final RxInt _reloadTrigger = 0.obs;
  final RxInt _focusFirstItemTrigger0 = 0.obs;
  final RxInt _focusFirstItemTrigger1 = 0.obs;
  final _currentTabIndex = 0.obs;

  List<Worker>? _workers;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() => setState(() {}));
    _textFieldFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack) {
            _textFieldFocusNode.unfocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final tabIndex = _tabBarController.index;
            tabIndex == 0
                ? _tab0FocusNode.requestFocus()
                : _tab1FocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (_tabBarController.index == 0) {
              _focusFirstItemTrigger0.value++;
            } else {
              _focusFirstItemTrigger1.value++;
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _searchFocusNode.focusInDirection(TraversalDirection.left);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
    _fetchData();
    _checkPermission();
    _tabBarController = TabController(length: 2, vsync: this);
    _tabBarController.animateTo(0);
    _tabBarController.addListener(_onTabChanged);

    _setupReactiveListeners();
  }

  void _setupReactiveListeners() {
    _workers = [
      ever(sourceController.installedExtensions, (_) {
        _updateExtensionCounts();
        _restoreFocusAfterRebuild();
      }),
      ever(_selectedLanguage, (_) => _updateExtensionCounts()),
    ];
    _updateExtensionCounts();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _textFieldFocusNode.dispose();
    _tab0FocusNode.dispose();
    _tab1FocusNode.dispose();
    _tabBarController.removeListener(_onTabChanged);
    _tabBarController.dispose();
    _textEditingController.dispose();

    // Dispose all workers
    if (_workers != null) {
      for (var worker in _workers!) {
        worker.dispose();
      }
    }

    super.dispose();
  }

  void _onTabChanged() {
    if (_tabBarController.indexIsChanging) return;
    if (!mounted) return;

    final newIndex = _tabBarController.index;
    _currentTabIndex.value = newIndex;
    _textEditingController.clear();

    FocusManager.instance.primaryFocus?.unfocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_currentTabIndex.value == 0 ? _tab0FocusNode : _tab1FocusNode)
          .requestFocus();
    });

    setState(() {});
  }

  void _restoreFocusAfterRebuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final activeNode =
          _currentTabIndex.value == 0 ? _tab0FocusNode : _tab1FocusNode;
      if (!activeNode.hasFocus) {
        activeNode.requestFocus();
      }
    });
  }

  void _updateExtensionCounts() {
    final newCounts = <String, int>{};

    for (final itemType in [ItemType.anime]) {
      for (final installed in [true, false]) {
        final key = '${itemType.toString()}_$installed';
        final extensions = installed
            ? sourceController.getInstalledExtensions(itemType)
            : sourceController.getAvailableExtensions(itemType);

        final filteredCount = extensions
            .where((element) => _selectedLanguage.value != 'all'
                ? element.lang!.toLowerCase() ==
                    completeLanguageCode(_selectedLanguage.value)
                : true)
            .length;

        newCounts[key] = filteredCount;
      }
    }

    _extensionCounts.value = newCounts;
  }

  Future<void> _fetchData() async {
    await sourceController.fetchRepos();
    _updateExtensionCounts();
    _reloadTrigger.value++;
    _restoreFocusAfterRebuild();
  }

  Future<void> _checkPermission() async {
    await StorageProvider().requestPermission();
  }

  void repoSheet() {
    RepoBottomSheet.show(
      context,
      onSave: _fetchData,
    );
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context).colorScheme;
    return Glow(
      disabled: widget.disableGlow,
      child: PopScope(
        canPop: !_searchFocusNode.hasFocus && !_textFieldFocusNode.hasFocus,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _textFieldFocusNode.unfocus();
            _searchFocusNode.unfocus();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            leading: getResponsiveValue(context,
                mobileValue: Center(
                  child: NyantvOnTap(
                    onTap: () => Get.back(),
                    child: Container(
                        width: 35,
                        height: 35,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(50),
                            color:
                                Theme.of(context).colorScheme.surfaceContainer),
                        child: const Icon(Icons.arrow_back_ios_new_rounded)),
                  ),
                ),
                desktopValue: const SizedBox.shrink()),
            leadingWidth: getResponsiveValue(context,
                mobileValue: null, desktopValue: 0.0),
            title: Text(
              "Extensions",
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 16.0,
                color: theme.primary,
              ),
            ),
            iconTheme: IconThemeData(color: theme.primary),
            actions: [
              IconButton(
                icon: Icon(HugeIcons.strokeRoundedGithub, color: theme.primary),
                onPressed: repoSheet,
              ),
              IconButton(
                icon: Icon(Iconsax.language_square, color: theme.primary),
                onPressed: () {
                  AlertDialogBuilder(context)
                    ..setTitle(_selectedLanguage.value)
                    ..singleChoiceItems(
                      sortedLanguagesMap.keys.toList(),
                      sortedLanguagesMap.keys
                          .toList()
                          .indexOf(_selectedLanguage.value),
                      (index) {
                        final newLanguage =
                            sortedLanguagesMap.keys.elementAt(index);
                        if (_selectedLanguage.value != newLanguage) {
                          _selectedLanguage.value = newLanguage;
                        }
                      },
                    )
                    ..show();
                },
              ),
              const SizedBox(width: 8.0),
            ],
          ),
          body: Column(
            children: [
              TabBar(
                indicatorSize: TabBarIndicatorSize.label,
                isScrollable: true,
                controller: _tabBarController,
                tabAlignment: TabAlignment.start,
                dragStartBehavior: DragStartBehavior.start,
                tabs: [
                  _buildTab(
                      context, ItemType.anime, "Installed Anime", true, 0),
                  _buildTab(
                      context, ItemType.anime, "Available Anime", false, 1),
                ],
              ),
              const SizedBox(height: 8.0),
              Focus(
                focusNode: _searchFocusNode,
                onFocusChange: (hasFocus) {
                  if (hasFocus && !_textFieldFocusNode.hasFocus) {
                    Future.microtask(() => _textFieldFocusNode.requestFocus());
                  }
                },
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.select ||
                        event.logicalKey == LogicalKeyboardKey.enter) {
                      if (!_textFieldFocusNode.hasFocus) {
                        _textFieldFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                    }
                    if (event.logicalKey == LogicalKeyboardKey.escape ||
                        event.logicalKey == LogicalKeyboardKey.goBack) {
                      _textFieldFocusNode.unfocus();
                      _searchFocusNode.unfocus();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: CustomSearchBar(
                  disableIcons: true,
                  focusNode: _textFieldFocusNode,
                  controller: _textEditingController,
                  onChanged: (v) => setState(() {}),
                  onSubmitted: (v) {
                    _textFieldFocusNode.unfocus();
                  },
                ),
              ),
              const SizedBox(height: 8.0),
              Expanded(
                child: FocusTraversalGroup(
                  child: TabBarView(
                    controller: _tabBarController,
                    children: [
                      ExcludeFocus(
                        excluding: _currentTabIndex.value != 0,
                        child: ExtensionList(
                          key: ValueKey(
                              'anime_installed_${_selectedLanguage.value}_${sourceController.activeAnimeRepo}'),
                          installed: true,
                          query: _textEditingController.text,
                          itemType: ItemType.anime,
                          selectedLanguage: _selectedLanguage.value,
                          showRecommended: false,
                          reloadTrigger: _reloadTrigger,
                          focusFirstItemTrigger: _focusFirstItemTrigger0,
                        ),
                      ),
                      ExcludeFocus(
                        excluding: _currentTabIndex.value != 1,
                        child: ExtensionList(
                          key: ValueKey(
                              'anime_available_${_selectedLanguage.value}_${sourceController.activeAnimeRepo}'),
                          installed: false,
                          query: _textEditingController.text,
                          itemType: ItemType.anime,
                          selectedLanguage: _selectedLanguage.value,
                          reloadTrigger: _reloadTrigger,
                          focusFirstItemTrigger: _focusFirstItemTrigger1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(BuildContext context, ItemType itemType, String label,
      bool installed, int tabIndex) {
    final focusNode = tabIndex == 0 ? _tab0FocusNode : _tab1FocusNode;
    return Focus(
      focusNode: focusNode,
      child: Tab(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 14.0)),
            const SizedBox(width: 8),
            _buildExtensionCount(itemType, installed),
          ],
        ),
      ),
    );
  }

  Widget _buildExtensionCount(ItemType itemType, bool installed) {
    final key = '${itemType.toString()}_$installed';
    final count = _extensionCounts[key] ?? 0;

    return count > 0
        ? Text(
            "($count)",
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
            ),
          )
        : const SizedBox.shrink();
  }
}
