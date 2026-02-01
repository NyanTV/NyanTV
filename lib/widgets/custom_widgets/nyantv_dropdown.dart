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
  
  int _focusedIndex = 0;
  final List<FocusNode> _itemFocusNodes = [];
  final FocusNode _dropdownButtonFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
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

    _rotateAnimation = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    _initializeFocusNodes();
    
    if (widget.selectedItem != null) {
      final index = widget.items.indexWhere((item) => item.value == widget.selectedItem!.value);
      if (index != -1) {
        _focusedIndex = index;
      }
    }
  }
  
  void _initializeFocusNodes() {
    for (int i = 0; i < widget.items.length; i++) {
      _itemFocusNodes.add(FocusNode());
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _fadeController.dispose();
    _overlayEntry?.remove();
    _dropdownButtonFocusNode.dispose();
    for (var node in _itemFocusNodes) {
      node.dispose();
    }
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
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;
    final double screenHeight = MediaQuery.of(context).size.height;

    const double dropdownMaxHeight = 320;
    const double spacing = 8;

    final double spaceBelow = screenHeight - (offset.dy + size.height);
    final double spaceAbove = offset.dy;

    if (spaceBelow >= dropdownMaxHeight + spacing) {
      return false;
    }

    if (spaceAbove > spaceBelow) {
      return true;
    }

    return false;
  }

  void _openDropdown() {
    setState(() {
      _isOpen = true;
      _openUpwards = _shouldOpenUpwards();
    });

    _animationController.forward();
    _fadeController.forward();

    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemFocusNodes.isNotEmpty && _focusedIndex < _itemFocusNodes.length) {
        _itemFocusNodes[_focusedIndex].requestFocus();
      }
    });
  }

  void _closeDropdown() {
    setState(() {
      _isOpen = false;
    });

    _animationController.reverse();
    _fadeController.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      _dropdownButtonFocusNode.requestFocus();
    });
  }
  
  KeyEventResult _handleDropdownNavigation(FocusNode node, RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _focusedIndex = (_focusedIndex + 1) % widget.items.length;
          _itemFocusNodes[_focusedIndex].requestFocus();
        });
        return KeyEventResult.handled;
      }
      else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _focusedIndex = (_focusedIndex - 1 + widget.items.length) % widget.items.length;
          _itemFocusNodes[_focusedIndex].requestFocus();
        });
        return KeyEventResult.handled;
      }
      else if (event.logicalKey == LogicalKeyboardKey.select || 
               event.logicalKey == LogicalKeyboardKey.enter) {
        widget.onChanged(widget.items[_focusedIndex]);
        _closeDropdown();
        return KeyEventResult.handled;
      }
      else if (event.logicalKey == LogicalKeyboardKey.escape ||
               event.logicalKey == LogicalKeyboardKey.goBack) {
        _closeDropdown();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    Size size = renderBox.size;
    Offset offset = renderBox.localToGlobal(Offset.zero);
    
    final bool isTV = Get.find<Settings>().isTV.value;

    return OverlayEntry(
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _closeDropdown,
        child: Stack(
          children: [
            Positioned(
              left: offset.dx,
              top: _openUpwards ? null : offset.dy + size.height + 8,
              bottom: _openUpwards
                  ? MediaQuery.of(context).size.height - offset.dy + 8
                  : null,
              width: size.width,
              child: GestureDetector(
                onTap: () {},
                child: CompositedTransformFollower(
                  link: _layerLink,
                  showWhenUnlinked: false,
                  offset: Offset(0.0,
                      (_openUpwards ? -(320 + 8) : size.height + 8).toDouble()),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _expandAnimation,
                      alignment: _openUpwards
                          ? Alignment.bottomCenter
                          : Alignment.topCenter,
                      child: Material(
                        elevation: 12,
                        borderRadius: BorderRadius.circular(20),
                        color: Theme.of(context).colorScheme.surface,
                        shadowColor:
                            Theme.of(context).shadowColor.withOpacity(0.15),
                        child: Container(
                          constraints: const BoxConstraints(
                            maxHeight: 320,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outline
                                  .withOpacity(0.15),
                              width: 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: widget.items.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                thickness: 0.5,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withOpacity(0.1),
                                indent: 16,
                                endIndent: 16,
                              ),
                              itemBuilder: (context, index) {
                                final item = widget.items[index];
                                final isSelected =
                                    widget.selectedItem?.value == item.value;
                                final isFocused = _focusedIndex == index;

                                return Focus(
                                  focusNode: _itemFocusNodes[index],
                                  onKey: _handleDropdownNavigation,
                                  child: Builder(
                                    builder: (context) {
                                      final hasFocus = Focus.of(context).hasFocus;
                                      
                                      return Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            widget.onChanged(item);
                                            _closeDropdown();
                                          },
                                          splashColor: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.1),
                                          highlightColor: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.05),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 150),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 16,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withOpacity(0.08)
                                                  : null,
                                              border: isTV && hasFocus
                                                  ? Border.all(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      width: 2,
                                                    )
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
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primaryContainer
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
                                                          fontWeight: isSelected || hasFocus
                                                              ? FontWeight.w600
                                                              : FontWeight.w500,
                                                          color: isSelected || hasFocus
                                                              ? Theme.of(context)
                                                                  .colorScheme
                                                                  .primary
                                                              : Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurface,
                                                        ),
                                                      ),
                                                      if (item.subtitle != null) ...[
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          item.subtitle!,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w400,
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

                                                // Extra widget (if any)
                                                if (item.extra != null) ...[
                                                  const SizedBox(width: 8),
                                                  item.extra!,
                                                ],

                                                // Trailing icon or check
                                                if (item.trailingIcon != null) ...[
                                                  const SizedBox(width: 8),
                                                  item.trailingIcon!,
                                                ] else if (isSelected) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.all(4),
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      borderRadius:
                                                          BorderRadius.circular(10),
                                                    ),
                                                    child: Icon(
                                                      Icons.check,
                                                      size: 14,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onPrimary,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Focus(
        focusNode: _dropdownButtonFocusNode,
        onKey: (node, event) {
          if (event is RawKeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter) {
              if (widget.items.isNotEmpty) {
                _toggleDropdown();
                return KeyEventResult.handled;
              }
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
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      widget.icon,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
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
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (widget.selectedItem?.leadingIcon != null) ...[
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                              ),
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
                                  widget.selectedItem?.text ?? "No item selected",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: widget.selectedItem != null
                                        ? Theme.of(context).colorScheme.onSurface
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.6),
                                  ),
                                ),
                                if (widget.selectedItem?.subtitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.selectedItem!.subtitle!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
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
                        ],
                      ),
                    ),
                    if (widget.actionIcon != null &&
                        widget.onActionPressed != null &&
                        widget.selectedItem != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: widget.onActionPressed,
                            child: Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: Icon(
                                widget.actionIcon,
                                size: 20,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.8),
                              ),
                            ),
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
