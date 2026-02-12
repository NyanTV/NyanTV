import 'package:nyantv/models/Media/media.dart';
import 'package:nyantv/widgets/common/slider_semantics.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_button.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter/gestures.dart';

class ListEditorModal extends StatefulWidget {
  final RxString animeStatus;
  final RxDouble animeScore;
  final RxInt animeProgress;
  final Rx<dynamic> currentAnime;
  final Media media;
  final Function(String, double, String, int) onUpdate;
  final Function(String) onDelete;

  const ListEditorModal({
    super.key,
    required this.animeStatus,
    required this.animeScore,
    required this.animeProgress,
    required this.currentAnime,
    required this.media,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<ListEditorModal> createState() => _ListEditorModalState();
}

class _ListEditorModalState extends State<ListEditorModal> {
  late TextEditingController _progressController;
  late FocusNode _progressFocusNode;
  final FocusNode _closeButtonFocusNode = FocusNode();
  final FocusNode _statusDropdownFocusNode = FocusNode();
  final FocusNode _decrementButtonFocusNode = FocusNode();
  final FocusNode _incrementButtonFocusNode = FocusNode();
  final FocusNode _sliderFocusNode = FocusNode();
  final FocusNode _deleteButtonFocusNode = FocusNode();
  final FocusNode _saveButtonFocusNode = FocusNode();
  final GlobalKey _dropdownKey = GlobalKey();

  late String _localStatus;
  late double _localScore;
  late int _localProgress;

  @override
  void initState() {
    super.initState();

    _localStatus =
        widget.animeStatus.value.isEmpty ? "CURRENT" : widget.animeStatus.value;
    _localScore = widget.animeScore.value;
    _localProgress = widget.animeProgress.value;

    _progressController = TextEditingController(
      text: _localProgress.toString(),
    );
    
    _progressFocusNode = FocusNode();
    
    _closeButtonFocusNode.addListener(() => setState(() {}));
    _statusDropdownFocusNode.addListener(() => setState(() {}));
    _decrementButtonFocusNode.addListener(() => setState(() {}));
    _progressFocusNode.addListener(() => setState(() {}));
    _incrementButtonFocusNode.addListener(() => setState(() {}));
    _sliderFocusNode.addListener(() => setState(() {}));
    _deleteButtonFocusNode.addListener(() => setState(() {}));
    _saveButtonFocusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _progressController.dispose();
    _progressFocusNode.dispose();
    _closeButtonFocusNode.dispose();
    _statusDropdownFocusNode.dispose();
    _decrementButtonFocusNode.dispose();
    _incrementButtonFocusNode.dispose();
    _sliderFocusNode.dispose();
    _deleteButtonFocusNode.dispose();
    _saveButtonFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24.0,
          right: 24.0,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
          top: 24.0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 32),
            _buildStatusSection(context),
            const SizedBox(height: 24),
            _buildProgressSection(context),
            const SizedBox(height: 24),
            _buildScoreSection(context),
            const SizedBox(height: 32),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit Anime',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Update your progress and rating',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        Focus(
          focusNode: _closeButtonFocusNode,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter) {
                Get.back();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _statusDropdownFocusNode.requestFocus();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surfaceContainerHighest,
              border: _closeButtonFocusNode.hasFocus
                  ? Border.all(
                      color: colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            padding: const EdgeInsets.all(8),
            child: IconButton(
                color: colorScheme.onSurface,
                onPressed: () => Get.back(),
                icon: const Icon(Icons.close_rounded)),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final GlobalKey<State<StatefulWidget>> dropdownKey = GlobalKey();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Status',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Focus(
          focusNode: _statusDropdownFocusNode,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter) {
                final context = _dropdownKey.currentContext;
                if (context != null) {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final Offset position = box.localToGlobal(box.size.center(Offset.zero));
                  
                  final PointerDownEvent down = PointerDownEvent(position: position);
                  final PointerUpEvent up = PointerUpEvent(position: position);
                  
                  GestureBinding.instance.handlePointerEvent(down);
                  Future.delayed(const Duration(milliseconds: 50), () {
                    GestureBinding.instance.handlePointerEvent(up);
                  });
                }
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _closeButtonFocusNode.requestFocus();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _decrementButtonFocusNode.requestFocus();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _statusDropdownFocusNode.hasFocus
                    ? colorScheme.primary
                    : colorScheme.outline.withOpacity(0.5),
                width: _statusDropdownFocusNode.hasFocus ? 2 : 1,
              ),
            ),
            child: NyantvDropdown(
              key: _dropdownKey,
              label: 'Status',
              icon: Icons.info_rounded,
              onChanged: (e) {
                setState(() {
                  _localStatus = e.value;
                });
              },
              selectedItem: DropdownItem(
                value: _localStatus,
                text: _getStatusDisplayText(_localStatus),
              ),
              items: [
                ('PLANNING', 'Planning', Icons.schedule_rounded),
                ('CURRENT', 'Watching', Icons.play_circle_rounded),
                ('COMPLETED', 'Completed', Icons.check_circle_rounded),
                ('REPEATING', 'Repeating', Icons.repeat_rounded),
                ('PAUSED', 'Paused', Icons.pause_circle_rounded),
                ('DROPPED', 'Dropped', Icons.cancel_rounded),
              ].map((item) {
                return DropdownItem(value: item.$1, text: item.$2);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
  String _getStatusDisplayText(String status) {
    switch (status) {
      case 'PLANNING':
        return 'Planning';
      case 'CURRENT':
        return 'Watching';
      case 'COMPLETED':
        return 'Completed';
      case 'REPEATING':
        return 'Repeating';
      case 'PAUSED':
        return 'Paused';
      case 'DROPPED':
        return 'Dropped';
      default:
        return status;
    }
  }

  Widget _buildProgressSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    bool isUnknownTotal() {
      final String? total = widget.media.totalEpisodes;
      return total == '?' || total == '??' || total == null || total.isEmpty;
    }

    int? getMaxTotal() {
      if (isUnknownTotal()) return null;
      final String total = widget.media.totalEpisodes;
      return int.tryParse(total);
    }

    final int? maxTotal = getMaxTotal();
    final bool hasKnownLimit = maxTotal != null;

    String getDisplayTotal() {
      return widget.media.totalEpisodes;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Progress',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.5),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDecrementButton(context),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: Focus(
                        focusNode: _progressFocusNode,
                        canRequestFocus: false,
                        skipTraversal: true,
                        child: TextFormField(
                          controller: _progressController,
                          enabled: false,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          style: Theme.of(context).textTheme.bodyLarge,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            prefixIcon: Icon(
                              Icons.play_circle_rounded,
                              color: colorScheme.primary,
                            ),
                            filled: true,
                            fillColor: colorScheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.outline.withOpacity(0.5),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.outline.withOpacity(0.5),
                              ),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.outline.withOpacity(0.5),
                              ),
                            ),
                            labelText: 'Episodes Watched',
                            labelStyle: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildIncrementButton(context, hasKnownLimit, maxTotal),
                ],
              ),
              const SizedBox(height: 16),
              _buildProgressIndicator(
                  context, hasKnownLimit, maxTotal, getDisplayTotal()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDecrementButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool canDecrement = _localProgress > 0;

    return Focus(
      focusNode: _decrementButtonFocusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            if (canDecrement) {
              setState(() {
                _localProgress--;
                _progressController.text = _localProgress.toString();
              });
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _statusDropdownFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _sliderFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _incrementButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: canDecrement
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: canDecrement
              ? () {
                  setState(() {
                    _localProgress--;
                    _progressController.text = _localProgress.toString();
                  });
                }
              : null,
          child: Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: _decrementButtonFocusNode.hasFocus
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.primary,
                      width: 2,
                    ),
                  )
                : null,
            child: Icon(
              Icons.remove_rounded,
              color: canDecrement
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.onSurfaceVariant.withOpacity(0.5),
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIncrementButton(BuildContext context, bool hasKnownLimit, int? maxTotal) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool canIncrement =
        !hasKnownLimit || (hasKnownLimit && _localProgress < maxTotal!);

    return Focus(
      focusNode: _incrementButtonFocusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            if (canIncrement) {
              setState(() {
                _localProgress++;
                _progressController.text = _localProgress.toString();
              });
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _statusDropdownFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _sliderFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _decrementButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: canIncrement
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: canIncrement
              ? () {
                  setState(() {
                    _localProgress++;
                    _progressController.text = _localProgress.toString();
                  });
                }
              : null,
          child: Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: _incrementButtonFocusNode.hasFocus
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.onPrimary,
                      width: 2,
                    ),
                  )
                : null,
            child: Icon(
              Icons.add_rounded,
              color: canIncrement
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant.withOpacity(0.5),
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(BuildContext context, bool hasKnownLimit,
      int? maxTotal, String displayTotal) {
    final colorScheme = Theme.of(context).colorScheme;
    final double progressPercentage =
        hasKnownLimit ? (_localProgress / maxTotal!).clamp(0.0, 1.0) : 0.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$_localProgress / $displayTotal',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            if (hasKnownLimit)
              Text(
                '${(progressPercentage * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
          ],
        ),
        if (hasKnownLimit) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressPercentage,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              minHeight: 6,
            ),
          ),
        ],
        if (!hasKnownLimit)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Total episodes unknown',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildScoreSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Rating',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            border: Border.all(
              color: _sliderFocusNode.hasFocus
                  ? colorScheme.primary
                  : colorScheme.outline.withOpacity(0.5),
              width: _sliderFocusNode.hasFocus ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Score',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_localScore.toStringAsFixed(1)}/10',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Focus(
                focusNode: _sliderFocusNode,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _decrementButtonFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _deleteButtonFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      setState(() {
                        _localScore = (_localScore - 0.1).clamp(0.0, 10.0);
                      });
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      setState(() {
                        _localScore = (_localScore + 0.1).clamp(0.0, 10.0);
                      });
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: CustomSlider(
                  value: _localScore,
                  min: 0.0,
                  max: 10.0,
                  divisions: 100,
                  label: _localScore.toStringAsFixed(1),
                  activeColor: colorScheme.primary,
                  inactiveColor: colorScheme.surfaceContainerHighest,
                  onChanged: (double newValue) {
                    setState(() {
                      _localScore = newValue;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 56,
            child: Focus(
              focusNode: _deleteButtonFocusNode,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter) {
                    Navigator.pop(context);
                    widget.onDelete(widget.media.id);
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _sliderFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    _saveButtonFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                decoration: _deleteButtonFocusNode.hasFocus
                    ? BoxDecoration(
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(100),
                          right: Radius.circular(10),
                        ),
                        border: Border.all(
                          color: colorScheme.onTertiary,
                          width: 2,
                        ),
                      )
                    : null,
                child: NyantvButton(
                  onTap: () {
                    Navigator.pop(context);
                    widget.onDelete(widget.media.id);
                  },
                  color: colorScheme.tertiary,
                  border: BorderSide.none,
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(100), right: Radius.circular(10)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_rounded,
                        color: colorScheme.onTertiary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Delete',
                        style: TextStyle(
                          color: colorScheme.onTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: SizedBox(
            height: 56,
            child: Focus(
              focusNode: _saveButtonFocusNode,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter) {
                    Get.back();
                    widget.onUpdate(
                      widget.media.id,
                      _localScore,
                      _localStatus,
                      _localProgress,
                    );
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _sliderFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    _deleteButtonFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                decoration: _saveButtonFocusNode.hasFocus
                    ? BoxDecoration(
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(100),
                          left: Radius.circular(10),
                        ),
                        border: Border.all(
                          color: colorScheme.onPrimary,
                          width: 2,
                        ),
                      )
                    : null,
                child: NyantvButton(
                  borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(100), left: Radius.circular(10)),
                  onTap: () {
                    Get.back();
                    widget.onUpdate(
                      widget.media.id,
                      _localScore,
                      _localStatus,
                      _localProgress,
                    );
                  },
                  color: colorScheme.primary,
                  border: BorderSide.none,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.save_rounded,
                        color: colorScheme.onPrimary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Save Changes',
                        style: TextStyle(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}