import 'package:nyantv/controllers/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class NyantvOnTap extends StatelessWidget {
  final VoidCallback? onTap;
  final GestureTapUpCallback? onTapUp;
  final GestureTapDownCallback? onTapDown;
  final GestureTapCancelCallback? onTapCancel;
  final Widget child;
  final double scale;
  final Duration animationDuration;
  final Color? focusedBorderColor;
  final bool? inkWell;
  final Color? bgColor;
  final double borderWidth;
  final double? margin;

  const NyantvOnTap({
    super.key,
    this.onTap,
    required this.child,
    this.scale = 1.0,
    this.animationDuration = const Duration(milliseconds: 200),
    this.focusedBorderColor,
    this.borderWidth = 2.0,
    this.margin,
    this.bgColor,
    this.inkWell,
    this.onTapUp,
    this.onTapDown,
    this.onTapCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isTV = Get.find<Settings>().isTV.value;
    if (isTV) {
      return FocusableActionDetector(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (ActivateIntent intent) => onTap?.call(),
          ),
        },
        child: Builder(
          builder: (BuildContext context) {
            final bool isFocused = Focus.of(context).hasFocus;
            return GestureDetector(
              onTap: onTap,
              onTapUp: onTapUp,
              onTapDown: onTapDown,
              onTapCancel: onTapCancel,
              child: AnimatedContainer(
                duration: animationDuration,
                transform: Matrix4.identity()..scale(isFocused ? scale : 1.0),
                padding: EdgeInsets.symmetric(
                    vertical: isFocused ? (margin ?? 5) : 0),
                margin: EdgeInsets.only(left: isFocused ? (margin ?? 5) : 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isFocused
                      ? (bgColor ??
                          Theme.of(context).colorScheme.secondaryContainer)
                      : Colors.transparent,
                  border: Border.all(
                    color: isFocused
                        ? (focusedBorderColor ??
                            Theme.of(context).colorScheme.primary)
                        : Colors.transparent,
                    width: borderWidth,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
                ),
                child: child,
              ),
            );
          },
        ),
      );
    } else {
      if (inkWell ?? false) {
        return InkWell(
          onTap: onTap,
          child: child,
        );
      } else {
        return GestureDetector(
          onTap: onTap,
          child: child,
        );
      }
    }
  }
}

class NyantvOnTapAdv extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final double scale;
  final Duration animationDuration;
  final Color? focusedBorderColor;
  final double borderWidth;
  final double? margin;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;
  final FocusNode? focusNode;
  final Function(bool)? onFocusChange;

  const NyantvOnTapAdv({
    super.key,
    this.onTap,
    required this.child,
    this.scale = 1.0,
    this.animationDuration = const Duration(milliseconds: 200),
    this.focusedBorderColor,
    this.borderWidth = 2.0,
    this.margin,
    this.onKeyEvent,
    this.focusNode,
    this.onFocusChange,
  });

  @override
  State<NyantvOnTapAdv> createState() => _NyantvOnTapAdvState();
}

class _NyantvOnTapAdvState extends State<NyantvOnTapAdv> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && mounted) {
      // Auto-scroll when focused
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
      widget.onFocusChange?.call(true);
    } else {
      widget.onFocusChange?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          if (widget.onTap != null) {
            widget.onTap!.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }
        return widget.onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
      },
      child: Builder(
        builder: (BuildContext context) {
          final bool isFocused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: widget.animationDuration,
              transform: Matrix4.identity()..scale(isFocused ? widget.scale : 1.0),
              padding: EdgeInsets.symmetric(vertical: isFocused ? (widget.margin ?? 5) : 0),
              margin: EdgeInsets.only(left: isFocused ? (widget.margin ?? 5) : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isFocused
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Colors.transparent,
                border: Border.all(
                  color: isFocused
                      ? (widget.focusedBorderColor ??
                          Theme.of(context).colorScheme.primary)
                      : Colors.transparent,
                  width: widget.borderWidth,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}

/// Wrapper for Scrollable Content with D-Pad Support
class TVScrollableWrapper extends StatefulWidget {
  final Widget child;
  final ScrollController? scrollController;
  final EdgeInsets? padding;
  final double scrollStep;

  const TVScrollableWrapper({
    super.key,
    required this.child,
    this.scrollController,
    this.padding,
    this.scrollStep = 100.0,
  });

  @override
  State<TVScrollableWrapper> createState() => _TVScrollableWrapperState();
}

class _TVScrollableWrapperState extends State<TVScrollableWrapper> {
  late ScrollController _scrollController;
  FocusNode? _lastFocusedNode;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
  }

  @override
  void dispose() {
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  bool _canScrollInDirection(LogicalKeyboardKey key) {
    if (!_scrollController.hasClients) return false;

    final currentPosition = _scrollController.position.pixels;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final minScroll = _scrollController.position.minScrollExtent;

    if (key == LogicalKeyboardKey.arrowDown) {
      return currentPosition < maxScroll;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      return currentPosition > minScroll;
    }
    return false;
  }

  void _handleManualScroll(LogicalKeyboardKey key) {
    if (!_scrollController.hasClients) return;

    final currentPosition = _scrollController.position.pixels;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final minScroll = _scrollController.position.minScrollExtent;

    if (key == LogicalKeyboardKey.arrowDown) {
      if (currentPosition < maxScroll) {
        final newPosition = (currentPosition + widget.scrollStep).clamp(minScroll, maxScroll);
        _scrollController.animateTo(
          newPosition,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (currentPosition > minScroll) {
        final newPosition = (currentPosition - widget.scrollStep).clamp(minScroll, maxScroll);
        _scrollController.animateTo(
          newPosition,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTV = Get.find<Settings>().isTV.value;

    if (!isTV) {
      return SingleChildScrollView(
        controller: _scrollController,
        padding: widget.padding,
        child: widget.child,
      );
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          
          if (key != LogicalKeyboardKey.arrowDown && key != LogicalKeyboardKey.arrowUp) {
            return KeyEventResult.ignored;
          }

          final currentFocus = FocusManager.instance.primaryFocus;
          
          // Wenn kein Fokus existiert, einfach scrollen wenn möglich
          if (currentFocus == null) {
            if (_canScrollInDirection(key)) {
              _handleManualScroll(key);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }

          // Speichere den aktuellen Fokus
          _lastFocusedNode = currentFocus;

          // WICHTIG: Prüfe ZUERST ob wir scrollen können, bevor wir fokussieren
          // Das verhindert das Springen zur Sidebar wenn noch Content oben/unten ist
          final canScroll = _canScrollInDirection(key);
          
          // Versuche zu fokussieren
          bool didFocus = false;
          if (key == LogicalKeyboardKey.arrowDown) {
            didFocus = currentFocus.nextFocus();
          } else if (key == LogicalKeyboardKey.arrowUp) {
            didFocus = currentFocus.previousFocus();
          }

          // Prüfe ob der Fokus zu einem komplett anderen Widget gesprungen ist
          // (z.B. zur Sidebar) anstatt zum nächsten Element in der Scroll-Area
          final newFocus = FocusManager.instance.primaryFocus;
          
          if (didFocus && newFocus != null && _lastFocusedNode != null) {
            // Wenn der neue Fokus außerhalb unseres ScrollView ist (z.B. Sidebar)
            // UND wir können noch scrollen, dann scrollen wir stattdessen
            final newContext = newFocus.context;
            final scrollContext = context;
            
            bool isInScrollView = false;
            if (newContext != null) {
              // Prüfe ob der neue Fokus ein Kind unseres ScrollView ist
              newContext.visitAncestorElements((element) {
                if (element == scrollContext) {
                  isInScrollView = true;
                  return false;
                }
                return true;
              });
            }
            
            // Wenn der neue Fokus NICHT in unserem ScrollView ist UND wir können scrollen
            if (!isInScrollView && canScroll) {
              // Fokus zurücksetzen
              _lastFocusedNode?.requestFocus();
              // Stattdessen scrollen
              _handleManualScroll(key);
              return KeyEventResult.handled;
            }
          }

          if (!didFocus && canScroll) {
            _handleManualScroll(key);
            return KeyEventResult.handled;
          }
          
          return KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: widget.padding,
        child: widget.child,
      ),
    );
  }
}