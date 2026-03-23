import 'package:nyantv/controllers/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class NyantvDropdown extends StatefulWidget {
  final List<DropdownItem> items;
  final DropdownItem? selectedItem;
  final Function(DropdownItem) onChanged;
  final String label;
  final IconData icon;
  final IconData? actionIcon;
  final VoidCallback? onActionPressed;

  const NyantvDropdown({
    super.key,
    required this.items,
    this.selectedItem,
    required this.onChanged,
    required this.label,
    required this.icon,
    this.actionIcon,
    this.onActionPressed,
  });

  @override
  State<NyantvDropdown> createState() => _NyantvDropdownState();
}

class _NyantvDropdownState extends State<NyantvDropdown>
    with TickerProviderStateMixin {
  bool _isOpen = false;
  bool _openUpwards = false;

  late AnimationController _animationController;
  late AnimationController _fadeController;
  late Animation<double> _expandAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _rotateAnimation;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  final FocusNode _dropdownButtonFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 180),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _rotateAnimation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _fadeController.dispose();
    _overlayEntry?.remove();
    _dropdownButtonFocusNode.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  bool _shouldOpenUpwards() {
    try {
      final RenderBox? rb = context.findRenderObject() as RenderBox?;
      if (rb == null || !rb.hasSize) return false;
      final offset = rb.localToGlobal(Offset.zero);
      final screenHeight = MediaQuery.of(context).size.height;
      const maxH = 320.0;
      const spacing = 8.0;
      final spaceBelow = screenHeight - (offset.dy + rb.size.height);
      final spaceAbove = offset.dy;
      if (spaceBelow >= maxH + spacing) return false;
      return spaceAbove > spaceBelow;
    } catch (_) {
      return false;
    }
  }

  void _openDropdown() {
    if (!mounted || _overlayEntry != null || _isClosing) return;
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null || !rb.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openDropdown());
      return;
    }

    setState(() {
      _isOpen = true;
      _openUpwards = _shouldOpenUpwards();
    });

    _animationController.forward();
    _fadeController.forward();

    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  bool _isClosing = false;

  void _closeDropdown() {
    if (!_isOpen) return;
    setState(() {
      _isOpen = false;
      _isClosing = true;
    });
    _animationController.reverse();
    _fadeController.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _dropdownButtonFocusNode.requestFocus();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) setState(() => _isClosing = false);
          });
        }
      });
    });
  }

  OverlayEntry _createOverlayEntry() {
    final RenderBox rb = context.findRenderObject() as RenderBox;
    final size = rb.size;
    final offset = rb.localToGlobal(Offset.zero);
    final bool isTV = Get.find<Settings>().isTV.value;
    final bool openUpwards = _openUpwards;
    final screenHeight = MediaQuery.of(context).size.height;

    return OverlayEntry(
      builder: (ctx) => _DropdownOverlay(
        offset: offset,
        size: size,
        screenHeight: screenHeight,
        openUpwards: openUpwards,
        layerLink: _layerLink,
        fadeAnimation: _fadeAnimation,
        expandAnimation: _expandAnimation,
        isTV: isTV,
        items: widget.items,
        selectedItem: widget.selectedItem,
        onSelect: (item) {
          widget.onChanged(item);
          _closeDropdown();
        },
        onDismiss: _closeDropdown,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Focus(
        focusNode: _dropdownButtonFocusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter) {
              if (widget.items.isNotEmpty &&
                  !_isClosing &&
                  _overlayEntry == null) {
                _toggleDropdown();
              }
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.items.isNotEmpty ? _toggleDropdown : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isOpen
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                width: _isOpen ? 2 : 1,
              ),
              boxShadow: _isOpen
                  ? [
                      BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(widget.icon,
                        size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    RotationTransition(
                      turns: _rotateAnimation,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (widget.selectedItem?.leadingIcon != null) ...[
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: widget.selectedItem!.leadingIcon!,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.selectedItem?.text ?? 'No item selected',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: widget.selectedItem != null
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.5),
                            ),
                          ),
                          if (widget.selectedItem?.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.selectedItem!.subtitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.selectedItem?.extra != null) ...[
                      const SizedBox(width: 8),
                      widget.selectedItem!.extra!,
                    ],
                    if (widget.actionIcon != null &&
                        widget.onActionPressed != null &&
                        widget.selectedItem != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: widget.onActionPressed,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(widget.actionIcon,
                                size: 20,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.8)),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownOverlay extends StatefulWidget {
  final Offset offset;
  final Size size;
  final double screenHeight;
  final bool openUpwards;
  final LayerLink layerLink;
  final Animation<double> fadeAnimation;
  final Animation<double> expandAnimation;
  final bool isTV;
  final List<DropdownItem> items;
  final DropdownItem? selectedItem;
  final void Function(DropdownItem) onSelect;
  final VoidCallback onDismiss;

  const _DropdownOverlay({
    required this.offset,
    required this.size,
    required this.screenHeight,
    required this.openUpwards,
    required this.layerLink,
    required this.fadeAnimation,
    required this.expandAnimation,
    required this.isTV,
    required this.items,
    required this.selectedItem,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  State<_DropdownOverlay> createState() => _DropdownOverlayState();
}

class _DropdownOverlayState extends State<_DropdownOverlay> {
  late int _focusedIndex;
  final FocusNode _scopeFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _focusedIndex = widget.selectedItem == null
        ? 0
        : widget.items
            .indexWhere((i) => i.value == widget.selectedItem!.value)
            .clamp(0, widget.items.length - 1);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scopeFocus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_focusedIndex > 0 && _scrollController.hasClients) {
          _scrollController.jumpTo(
            (_focusedIndex * 64.0)
                .clamp(0, _scrollController.position.maxScrollExtent),
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _scopeFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) {
    const itemH = 64.0;
    final target = index * itemH;
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      target.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKey(FocusNode node, RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < widget.items.length - 1) {
        setState(() => _focusedIndex++);
        _scrollToIndex(_focusedIndex);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > 0) {
        setState(() => _focusedIndex--);
        _scrollToIndex(_focusedIndex);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      widget.onSelect(widget.items[_focusedIndex]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: widget.offset.dx,
          top: widget.openUpwards
              ? null
              : widget.offset.dy + widget.size.height + 8,
          bottom: widget.openUpwards
              ? widget.screenHeight - widget.offset.dy + 8
              : null,
          width: widget.size.width,
          child: GestureDetector(
            onTap: () {},
            child: CompositedTransformFollower(
              link: widget.layerLink,
              showWhenUnlinked: false,
              offset: Offset(
                0,
                (widget.openUpwards ? -(320 + 8) : widget.size.height + 8)
                    .toDouble(),
              ),
              child: FadeTransition(
                opacity: widget.fadeAnimation,
                child: ScaleTransition(
                  scale: widget.expandAnimation,
                  alignment: widget.openUpwards
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
                  child: Focus(
                    focusNode: _scopeFocus,
                    onKey: _onKey,
                    child: Material(
                      elevation: 12,
                      borderRadius: BorderRadius.circular(20),
                      color: theme.surface,
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 320),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: theme.outline.withOpacity(0.15)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: ListView.separated(
                            controller: _scrollController,
                            shrinkWrap: true,
                            itemCount: widget.items.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              thickness: 0.5,
                              color: theme.outline.withOpacity(0.1),
                              indent: 16,
                              endIndent: 16,
                            ),
                            itemBuilder: (context, index) {
                              final item = widget.items[index];
                              final isSelected =
                                  widget.selectedItem?.value == item.value;
                              final isFocused = _focusedIndex == index;

                              return GestureDetector(
                                onTap: () => widget.onSelect(item),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 16),
                                  decoration: BoxDecoration(
                                    color: isFocused
                                        ? theme.primary.withOpacity(0.08)
                                        : isSelected
                                            ? theme.primary.withOpacity(0.05)
                                            : Colors.transparent,
                                    border: widget.isTV && isFocused
                                        ? Border.all(
                                            color: theme.primary, width: 2)
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      if (item.leadingIcon != null) ...[
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            color: theme.primaryContainer
                                                .withOpacity(0.3),
                                          ),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: item.leadingIcon!,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                      ],
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.text,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight:
                                                    isFocused || isSelected
                                                        ? FontWeight.w600
                                                        : FontWeight.w500,
                                                color: isFocused || isSelected
                                                    ? theme.primary
                                                    : theme.onSurface,
                                              ),
                                            ),
                                            if (item.subtitle != null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                item.subtitle!,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: theme.onSurface
                                                      .withOpacity(0.6),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (item.extra != null) ...[
                                        const SizedBox(width: 8),
                                        item.extra!,
                                      ],
                                      if (item.trailingIcon != null) ...[
                                        const SizedBox(width: 8),
                                        item.trailingIcon!,
                                      ] else if (isSelected) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: theme.primary,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Icon(Icons.check,
                                              size: 14, color: theme.onPrimary),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
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

class DropdownItem {
  final String value;
  final String text;
  final String? subtitle;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final Widget? extra;

  const DropdownItem({
    required this.value,
    required this.text,
    this.subtitle,
    this.leadingIcon,
    this.trailingIcon,
    this.extra,
  });
}
