// ignore_for_file: deprecated_member_use

import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nyantv/widgets/custom_widgets/custom_text.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:iconsax/iconsax.dart';

class InlineSearchHistory extends StatefulWidget {
  final RxList<String> searchTerms;
  final FocusNode clearAllFocusNode;
  final Function(String) onTermSelected;
  final Function(List<String>) onHistoryUpdated;
  final VoidCallback onNavigateBack;

  const InlineSearchHistory({
    super.key,
    required this.searchTerms,
    required this.clearAllFocusNode,
    required this.onTermSelected,
    required this.onHistoryUpdated,
    required this.onNavigateBack,
  });

  @override
  State<InlineSearchHistory> createState() => _InlineSearchHistoryState();
}

class _InlineSearchHistoryState extends State<InlineSearchHistory> {
  final List<FocusNode> _termFocusNodes = [];
  final List<FocusNode> _deleteFocusNodes = [];

  @override
  void initState() {
    super.initState();
    _initializeFocusNodes();
    widget.clearAllFocusNode.addListener(() {
      setState(() {});
    });
  }

  void _initializeFocusNodes() {
    // Clear existing focus nodes
    for (var node in _termFocusNodes) {
      node.dispose();
    }
    for (var node in _deleteFocusNodes) {
      node.dispose();
    }
    _termFocusNodes.clear();
    _deleteFocusNodes.clear();

    // Create focus nodes for each term
    final displayedTerms = widget.searchTerms.reversed.toList();
    for (int i = 0; i < displayedTerms.length; i++) {
      final termNode = FocusNode();
      final deleteNode = FocusNode();
      
      termNode.addListener(() {
        setState(() {});
      });
      deleteNode.addListener(() {
        setState(() {});
      });
      
      _termFocusNodes.add(termNode);
      _deleteFocusNodes.add(deleteNode);
    }
  }

  @override
  void didUpdateWidget(InlineSearchHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchTerms.length != widget.searchTerms.length) {
      _initializeFocusNodes();
    }
  }

  @override
  void dispose() {
    for (var node in _termFocusNodes) {
      node.dispose();
    }
    for (var node in _deleteFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _deleteTerm(String term) {
    List<String> updatedTerms = List.from(widget.searchTerms);
    updatedTerms.remove(term);
    _saveToDatabase(updatedTerms);
    widget.onHistoryUpdated(updatedTerms);
  }

  void _clearAllHistory() {
    _saveToDatabase([]);
    widget.onHistoryUpdated([]);
  }

  void _saveToDatabase(List<String> terms) {
    Hive.box('preferences').put(
        'anime_searched_queries_${serviceHandler.serviceType.value.name}',
        terms);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.searchTerms.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final displayedTerms = widget.searchTerms.reversed.toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Iconsax.clock,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    NyantvText(
                      text: 'Recent Searches',
                      variant: TextVariant.semiBold,
                      size: 15,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.9),
                    ),
                  ],
                ),
                Focus(
                  focusNode: widget.clearAllFocusNode,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        _clearAllHistory();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        if (_termFocusNodes.isNotEmpty) {
                          _termFocusNodes.first.requestFocus();
                        }
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        widget.onNavigateBack();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: GestureDetector(
                    onTap: _clearAllHistory,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: widget.clearAllFocusNode.hasFocus
                              ? Theme.of(context).colorScheme.error
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Iconsax.trash,
                            size: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withOpacity(0.8),
                          ),
                          const SizedBox(width: 4),
                          NyantvText(
                            text: "Clear",
                            size: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withOpacity(0.8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search terms
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: displayedTerms.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final term = displayedTerms[index];

                  return _buildSearchTermItem(
                    context,
                    term,
                    index,
                    displayedTerms.length,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTermItem(
    BuildContext context,
    String term,
    int index,
    int totalItems,
  ) {
    return Focus(
      focusNode: _termFocusNodes[index],
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onTermSelected(term);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            if (index > 0) {
              _termFocusNodes[index - 1].requestFocus();
            } else {
              widget.clearAllFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (index < totalItems - 1) {
              _termFocusNodes[index + 1].requestFocus();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _deleteFocusNodes[index].requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onTermSelected(term),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceVariant
                  .withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _termFocusNodes[index].hasFocus
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline.withOpacity(0.05),
                width: _termFocusNodes[index].hasFocus ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Search icon
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Iconsax.search_normal_1,
                    size: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(0.7),
                  ),
                ),

                const SizedBox(width: 12),

                // Search term
                Expanded(
                  child: NyantvText(
                    text: term,
                    size: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.8),
                  ),
                ),

                // Delete button
                Focus(
                  focusNode: _deleteFocusNodes[index],
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        _deleteTerm(term);
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        _termFocusNodes[index].requestFocus();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        if (index > 0) {
                          _deleteFocusNodes[index - 1].requestFocus();
                        } else {
                          widget.clearAllFocusNode.requestFocus();
                        }
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        if (index < totalItems - 1) {
                          _deleteFocusNodes[index + 1].requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: GestureDetector(
                    onTap: () => _deleteTerm(term),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .error
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _deleteFocusNodes[index].hasFocus
                              ? Theme.of(context).colorScheme.error
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Iconsax.close_circle,
                        size: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .error
                            .withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}