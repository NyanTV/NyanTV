// ignore_for_file: deprecated_member_use

import 'package:nyantv/utils/logger.dart';

import 'package:nyantv/controllers/service_handler/params.dart';
import 'package:nyantv/screens/search/widgets/inline_search_history.dart';
import 'package:nyantv/screens/search/widgets/search_widgets.dart';
import 'package:nyantv/screens/settings/misc/sauce_finder_view.dart';
import 'package:nyantv/utils/function.dart';
import 'package:nyantv/widgets/helper/platform_builder.dart';
import 'package:nyantv/widgets/media_items/media_item.dart';
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive/hive.dart';
import 'package:iconsax/iconsax.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/models/Media/media.dart';
import 'package:nyantv/screens/anime/details_page.dart';
import 'package:nyantv/widgets/common/glow.dart';

enum ViewMode { grid, list }

enum SearchState { initial, loading, success, error, empty }

class SearchPage extends StatefulWidget {
  final String searchTerm;
  final dynamic source;
  final Map<String, dynamic>? initialFilters;

  const SearchPage({
    super.key,
    required this.searchTerm,
    this.source,
    this.initialFilters,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ServiceHandler _serviceHandler = Get.find<ServiceHandler>();
  final RxList<String> _searchedTerms = <String>[].obs;

  List<Media>? _searchResults;
  ViewMode _currentViewMode = ViewMode.grid;
  SearchState _searchState = SearchState.initial;
  String? _errorMessage;
  Map<String, dynamic> _activeFilters = {};
  RxBool isAdult = false.obs;

  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _backButtonFocusNode = FocusNode();
  final FocusNode _adultToggleFocusNode = FocusNode();
  final FocusNode _filterButtonFocusNode = FocusNode();
  final FocusNode _imageButtonFocusNode = FocusNode();
  final FocusNode _clearIconFocusNode = FocusNode();
  final FocusNode _searchBarFilterIconFocusNode = FocusNode();
  final FocusNode _gridModeFocusNode = FocusNode();
  final FocusNode _listModeFocusNode = FocusNode();
  final FocusNode _clearAllHistoryFocusNode = FocusNode();
  
  final List<FocusNode> _resultFocusNodes = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeData();
  }

  void _initializeAnimations() {
    _searchFocusNode.addListener(() => setState(() {}));
    _adultToggleFocusNode.addListener(() => setState(() {}));
    _filterButtonFocusNode.addListener(() => setState(() {}));
    _imageButtonFocusNode.addListener(() => setState(() {}));
    _clearIconFocusNode.addListener(() => setState(() {}));
    _searchBarFilterIconFocusNode.addListener(() => setState(() {}));
    _gridModeFocusNode.addListener(() => setState(() {}));
    _listModeFocusNode.addListener(() => setState(() {}));
    _clearAllHistoryFocusNode.addListener(() => setState(() {}));
  }

  void _initializeData() {
    _searchController.text = widget.searchTerm;
    _searchedTerms.value = Hive.box('preferences').get(
        'anime_searched_queries_${serviceHandler.serviceType.value.name}',
        defaultValue: [].cast<String>());

    if (widget.initialFilters != null) {
      _activeFilters = Map<String, dynamic>.from(widget.initialFilters!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch(filters: _activeFilters);
      });
    } else if (widget.searchTerm.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch();
      });
    }
  }

  void _initializeResultFocusNodes() {
    for (var node in _resultFocusNodes) {
      node.dispose();
    }
    _resultFocusNodes.clear();

    if (_searchResults != null) {
      for (int i = 0; i < _searchResults!.length; i++) {
        final node = FocusNode();
        node.addListener(() {
          if (node.hasFocus) {
            setState(() {});
            _scrollToIndex(i);
          }
        });
        _resultFocusNodes.add(node);
      }
    }
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    
    final itemHeight = _currentViewMode == ViewMode.list ? 132.0 : 252.0;
    final crossAxisCount = _getCrossAxisCount();
    final row = index ~/ crossAxisCount;
    final position = row * itemHeight;
    
    _scrollController.animateTo(
      position.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  int _getCrossAxisCount() {
    if (_currentViewMode == ViewMode.list) return 1;
    return getResponsiveValue(context,
        mobileValue: 3,
        desktopValue: getResponsiveCrossAxisVal(
            MediaQuery.of(context).size.width,
            itemWidth: 108));
  }

  void _saveHistory() {
    Hive.box('preferences').put(
      'anime_searched_queries_${serviceHandler.serviceType.value.name}',
      _searchedTerms.toList(),
    );
  }

  Future<void> _performSearch({
    String? query,
    Map<String, dynamic>? filters,
  }) async {
    final searchQuery = query ?? _searchController.text.trim();

    if (searchQuery.isEmpty && (filters == null || filters.isEmpty)) {
      setState(() {
        _searchState = SearchState.initial;
        _searchResults = null;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _searchState = SearchState.loading;
      _errorMessage = null;
    });

    try {
      if (filters != null) {
        _activeFilters = Map<String, dynamic>.from(filters);
      }

      final results = (await _serviceHandler.search(SearchParams(
            query: searchQuery,
            filters: _activeFilters.isNotEmpty ? _activeFilters : null,
            args: isAdult.value,
          ))) ??
          [];

      if (searchQuery.isNotEmpty && !_searchedTerms.contains(searchQuery)) {
        _searchedTerms.add(searchQuery);
        _saveHistory();
      }

      setState(() {
        _searchResults = results;
        _searchState =
            results.isEmpty ? SearchState.empty : SearchState.success;
      });
      
      _initializeResultFocusNodes();
    } catch (e) {
      setState(() {
        _searchState = SearchState.error;
        _errorMessage = _getErrorMessage(e);
      });
      Logger.i('Search failed: $e');
    }
  }

  String _getErrorMessage(dynamic error) {
    if (error.toString().contains('network') ||
        error.toString().contains('connection')) {
      return 'Network error. Please check your connection.';
    } else if (error.toString().contains('timeout')) {
      return 'Search timed out. Please try again.';
    } else if (error.toString().contains('404')) {
      return 'Service not available. Please try later.';
    } else {
      return 'Something went wrong. Please try again.';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _adultToggleFocusNode.dispose();
    _filterButtonFocusNode.dispose();
    _imageButtonFocusNode.dispose();
    _clearIconFocusNode.dispose();
    _searchBarFilterIconFocusNode.dispose();
    _gridModeFocusNode.dispose();
    _listModeFocusNode.dispose();
    _clearAllHistoryFocusNode.dispose();
    _scrollController.dispose();
    for (var node in _resultFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _buildModernSearchBar() {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent && _searchFocusNode.hasFocus) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            // Check if history is visible
            if (_searchState == SearchState.initial && _searchedTerms.isNotEmpty) {
              _clearAllHistoryFocusNode.requestFocus();
            } else if (serviceHandler.serviceType.value == ServicesType.anilist) {
              _adultToggleFocusNode.requestFocus();
            }
            return;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (_searchController.text.isNotEmpty) {
              _clearIconFocusNode.requestFocus();
            } else if (serviceHandler.serviceType.value == ServicesType.anilist) {
              _searchBarFilterIconFocusNode.requestFocus();
            }
            return;
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: _searchFocusNode.hasFocus
              ? [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
          decoration: InputDecoration(
            filled: true,
            fillColor:
                Theme.of(context).colorScheme.surfaceContainer.withOpacity(.5),
            hintText: 'Search anime...',
            hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
            prefixIcon: Icon(
              Iconsax.search_normal,
              color: _searchFocusNode.hasFocus
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? _buildClearIcon()
                : serviceHandler.serviceType.value != ServicesType.anilist
                    ? null
                    : _buildSearchBarFilterIcon(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
          onSubmitted: (query) => _performSearch(query: query),
          onChanged: (value) => setState(() {}),
        ),
      ),
    );
  }

  Widget _buildClearIcon() {
    return Focus(
      focusNode: _clearIconFocusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            _searchController.clear();
            setState(() {
              _searchState = SearchState.initial;
              _searchResults = null;
            });
            _searchFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _searchFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (serviceHandler.serviceType.value == ServicesType.anilist) {
              _adultToggleFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: _clearIconFocusNode.hasFocus
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              )
            : null,
        child: IconButton(
          onPressed: () {
            _searchController.clear();
            setState(() {
              _searchState = SearchState.initial;
              _searchResults = null;
            });
            _searchFocusNode.requestFocus();
          },
          icon: Icon(
            Iconsax.close_circle,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBarFilterIcon() {
    return Focus(
      focusNode: _searchBarFilterIconFocusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            _showFilterBottomSheet();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _searchFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _adultToggleFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: _searchBarFilterIconFocusNode.hasFocus
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              )
            : null,
        child: IconButton(
          onPressed: _showFilterBottomSheet,
          icon: Icon(
            Iconsax.setting_4,
            color: _activeFilters.isNotEmpty
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildControlsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          if (serviceHandler.serviceType.value == ServicesType.anilist) ...[
            _buildToggleButtonObx(),
            const SizedBox(width: 12),
            _buildActionButton(
              icon: Iconsax.setting_4,
              label: 'Filters',
              isActive: _activeFilters.isNotEmpty,
              onTap: _showFilterBottomSheet,
              focusNode: _filterButtonFocusNode,
            ),
            const SizedBox(width: 12),
            _buildActionButton(
              icon: Iconsax.eye,
              label: 'Image',
              isActive: false,
              onTap: () => navigate(() => const SauceFinderView()),
              focusNode: _imageButtonFocusNode,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleButtonObx() {
    return Obx(() {
      return _buildToggleButton(
        label: 'Adult',
        isActive: isAdult.value,
        onTap: () => isAdult.value = !isAdult.value,
        focusNode: _adultToggleFocusNode,
      );
    });
  }

  Widget _buildToggleButton({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required FocusNode focusNode,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            onTap();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _searchFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _filterButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            // Navigate to history if visible, otherwise to view mode toggle or results
            if (_searchState == SearchState.initial && _searchedTerms.isNotEmpty) {
              _clearAllHistoryFocusNode.requestFocus();
            } else if (_searchState == SearchState.success) {
              _gridModeFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                : Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focusNode.hasFocus
                  ? Theme.of(context).colorScheme.primary
                  : isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline.withOpacity(0.3),
              width: focusNode.hasFocus ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 12,
                decoration: BoxDecoration(
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment:
                      isActive ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required FocusNode focusNode,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            onTap();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _searchFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (focusNode == _filterButtonFocusNode) {
              _adultToggleFocusNode.requestFocus();
            } else if (focusNode == _imageButtonFocusNode) {
              _filterButtonFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (focusNode == _filterButtonFocusNode) {
              _imageButtonFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            // Navigate to history if visible, otherwise to view mode toggle or results
            if (_searchState == SearchState.initial && _searchedTerms.isNotEmpty) {
              _clearAllHistoryFocusNode.requestFocus();
            } else if (_searchState == SearchState.success) {
              _gridModeFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                : Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focusNode.hasFocus
                  ? Theme.of(context).colorScheme.primary
                  : isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline.withOpacity(0.3),
              width: focusNode.hasFocus ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildViewModeButton(ViewMode.grid, Iconsax.grid_1, _gridModeFocusNode),
          _buildViewModeButton(ViewMode.list, Iconsax.menu_1, _listModeFocusNode),
        ],
      ),
    );
  }

  Widget _buildViewModeButton(ViewMode mode, IconData icon, FocusNode focusNode) {
    final isActive = _currentViewMode == mode;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            setState(() => _currentViewMode = mode);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (mode == ViewMode.list) {
              _gridModeFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (mode == ViewMode.grid) {
              _listModeFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _adultToggleFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (_resultFocusNodes.isNotEmpty) {
              _resultFocusNodes.first.requestFocus();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => setState(() => _currentViewMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: focusNode.hasFocus
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : null,
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveFilters() {
    if (_activeFilters.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _buildFilterChips(),
        ),
      ),
    );
  }

  List<Widget> _buildFilterChips() {
    List<Widget> chips = [];

    _activeFilters.forEach((key, value) {
      if (key == 'genres' && value is List && value.isNotEmpty) {
        for (var genre in value) {
          chips.add(_buildFilterChip(genre, () => _removeFilter(key, genre)));
        }
      } else if (value != null && value.toString().isNotEmpty) {
        String displayText = _formatFilterValue(key, value);
        chips.add(
            _buildFilterChip(displayText, () => _removeFilter(key, value)));
      }
    });

    return chips;
  }

  Widget _buildFilterChip(String text, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 16,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_searchState) {
      case SearchState.initial:
        return _buildInitialState();
      case SearchState.loading:
        return _buildLoadingState();
      case SearchState.success:
        return _buildSuccessState();
      case SearchState.error:
        return _buildErrorState();
      case SearchState.empty:
        return _buildEmptyState();
    }
  }

  Widget _buildInitialState() {
    return Expanded(
      child: InlineSearchHistory(
        searchTerms: _searchedTerms,
        clearAllFocusNode: _clearAllHistoryFocusNode,
        onTermSelected: (term) {
          _searchController.text = term;
          _performSearch(query: term);
        },
        onHistoryUpdated: (updatedTerms) {
          setState(() {
            _searchedTerms.value = updatedTerms;
          });
          _saveHistory();
        },
        onNavigateBack: () {
          // Navigate back to Adult toggle if available, otherwise to search bar
          if (serviceHandler.serviceType.value == ServicesType.anilist) {
            _adultToggleFocusNode.requestFocus();
          } else {
            _searchFocusNode.requestFocus();
          }
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const ExpressiveLoadingIndicator(),
            ),
            const SizedBox(height: 24),
            Text(
              'Searching...',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Iconsax.warning_2,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Oops! Something went wrong',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Please try again later',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.7),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _performSearch(),
              icon: Icon(Iconsax.refresh,
                  color: Theme.of(context).colorScheme.onPrimary),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Iconsax.search_normal,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No results found',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search terms or filters',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.7),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessState() {
    return Expanded(
      child: _buildSearchResults(),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults == null || _searchResults!.isEmpty) {
      return const SizedBox.shrink();
    }

    final crossAxisCount = _getCrossAxisCount();

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      gridDelegate: _currentViewMode == ViewMode.list
          ? const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1,
              mainAxisExtent: 120,
            )
          : SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12.0,
              mainAxisSpacing: 12.0,
              mainAxisExtent: 240,
            ),
      itemCount: _searchResults!.length,
      itemBuilder: (context, index) {
        final media = _searchResults![index];
        return _buildResultItem(media, index, crossAxisCount);
      },
    );
  }

  Widget _buildResultItem(Media media, int index, int crossAxisCount) {
    final focusNode = _resultFocusNodes[index];
    
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          _navigateToDetails(media);
          return KeyEventResult.handled;
        }
        
        // Calculate navigation targets
        final currentRow = index ~/ crossAxisCount;
        final currentCol = index % crossAxisCount;
        
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (currentRow > 0) {
            final targetIndex = index - crossAxisCount;
            _resultFocusNodes[targetIndex].requestFocus();
          } else {
            _gridModeFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          final targetIndex = index + crossAxisCount;
          if (targetIndex < _resultFocusNodes.length) {
            _resultFocusNodes[targetIndex].requestFocus();
          }
          return KeyEventResult.handled;
        }
        
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (currentCol > 0) {
            _resultFocusNodes[index - 1].requestFocus();
          }
          return KeyEventResult.handled;
        }
        
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (currentCol < crossAxisCount - 1 && index + 1 < _resultFocusNodes.length) {
            _resultFocusNodes[index + 1].requestFocus();
          }
          return KeyEventResult.handled;
        }
        
        return KeyEventResult.ignored;
      },
      child: AnimationConfiguration.staggeredGrid(
        position: index,
        columnCount: crossAxisCount,
        child: ScaleAnimation(
          duration: const Duration(milliseconds: 100),
          child: InkWell(
            onTap: () => _navigateToDetails(media),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: focusNode.hasFocus
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      )
                    : null,
              ),
              child: _currentViewMode == ViewMode.list
                  ? _buildListItem(media)
                  : GridAnimeCard(data: media, variant: CardVariant.search),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListItem(Media media) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(0.3),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Hero(
              tag: media.title,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  width: 60,
                  height: 88,
                  imageUrl: media.poster,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    child: Icon(
                      Iconsax.image,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    child: Icon(
                      Iconsax.warning_2,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    media.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (media.rating != "??") ...[
                    const SizedBox(height: 8),
                    _buildRatingChip(media.rating),
                  ],
                ],
              ),
            ),
            Icon(
              Iconsax.arrow_right_3,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingChip(String rating) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Iconsax.star5,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            rating,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  void _showFilterBottomSheet() {
    showFilterBottomSheet(context, (filters) {
      _performSearch(filters: filters);
    }, currentFilters: _activeFilters);
  }

  void _removeFilter(String key, dynamic value) {
    if (_activeFilters.containsKey(key)) {
      setState(() {
        if (key == 'genres' && _activeFilters[key] is List) {
          List<String> genres = List<String>.from(_activeFilters[key]);
          genres.remove(value);
          if (genres.isEmpty) {
            _activeFilters.remove(key);
          } else {
            _activeFilters[key] = genres;
          }
        } else {
          _activeFilters.remove(key);
        }
      });
      _performSearch(filters: _activeFilters);
    }
  }

  String _formatFilterValue(String key, dynamic value) {
    switch (key) {
      case 'sort':
        return "Sort: ${_formatSortBy(value.toString())}";
      case 'season':
        return "Season: ${value.toString().toLowerCase().capitalize}";
      case 'status':
        return value.toString() != 'All'
            ? "Status: ${_formatStatus(value.toString())}"
            : "";
      case 'format':
        return "Format: $value";
      default:
        return "$key: $value";
    }
  }

  String _formatSortBy(String sortBy) {
    switch (sortBy) {
      case 'SCORE_DESC':
        return 'Score ↓';
      case 'SCORE':
        return 'Score ↑';
      case 'POPULARITY_DESC':
        return 'Popularity ↓';
      case 'POPULARITY':
        return 'Popularity ↑';
      case 'TRENDING_DESC':
        return 'Trending ↓';
      case 'TRENDING':
        return 'Trending ↑';
      case 'START_DATE_DESC':
        return 'Newest';
      case 'START_DATE':
        return 'Oldest';
      case 'TITLE_ROMAJI':
        return 'Title A-Z';
      case 'TITLE_ROMAJI_DESC':
        return 'Title Z-A';
      default:
        return sortBy;
    }
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'FINISHED':
        return 'Finished';
      case 'NOT_YET_RELEASED':
        return 'Not Released';
      case 'RELEASING':
        return 'Airing';
      case 'CANCELLED':
        return 'Cancelled';
      case 'HIATUS':
        return 'On Hiatus';
      default:
        return status;
    }
  }

  void _navigateToDetails(Media media) {
    navigate(() => AnimeDetailsPage(
          media: media,
          tag: media.title,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Glow(
      child: SafeArea(
        child: Scaffold(
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Row(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withOpacity(0.3),
                        ),
                      ),
                      child: IconButton(
                        focusNode: _backButtonFocusNode,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Iconsax.arrow_left_2,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Expanded(child: _buildModernSearchBar()),
                  ],
                ),
              ),
              _buildControlsSection(),
              const SizedBox(height: 16),
              _buildActiveFilters(),
              if (_searchState == SearchState.success &&
                  _searchResults!.isNotEmpty) ...[
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        'Search Results',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_searchResults!.length}',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      const Spacer(),
                      _buildViewModeToggle(),
                    ],
                  ),
                ),
              ],
              _buildMainContent(),
            ],
          ),
        ),
      ),
    );
  }
}