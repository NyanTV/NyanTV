import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final InputDecoration? decoration;
  final TextStyle? style;
  final int? maxLines;
  final int? minLines;
  final bool autofocus;
  final bool enabled;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextInputAction? textInputAction;

  const TvTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.decoration,
    this.style,
    this.maxLines = 1,
    this.minLines,
    this.autofocus = false,
    this.enabled = true,
    this.keyboardType,
    this.obscureText = false,
    this.textInputAction,
  });

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> with WidgetsBindingObserver {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _readOnly = true;
  bool _keyboardOpenedByUs = false;
  bool _ignoreMetrics = false;
  static const _channel = MethodChannel('app/keyboard');
  static const _visibilityChannel = EventChannel('app/keyboard_visibility');
  StreamSubscription? _keyboardSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);

    _keyboardSubscription =
        _visibilityChannel.receiveBroadcastStream().listen((isVisible) {
      if (!isVisible && !_readOnly && _keyboardOpenedByUs && !_ignoreMetrics) {
        _channel.invokeMethod('show');
      }
    });

    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        if (mounted) setState(() => _readOnly = true);
      } else {
        _channel.invokeMethod('hide');
        if (mounted) setState(() => _readOnly = true);
      }
    });

    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.goBack ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        if (!_readOnly) {
          setState(() {
            _readOnly = true;
            _keyboardOpenedByUs = false;
          });
          _channel.invokeMethod('hide');
          return true;
        } else if (_focusNode.hasFocus) {
          _focusNode.unfocus();
          return true;
        }
      }
    }

    if (_readOnly && _focusNode.hasFocus && event is KeyDownEvent) {
      TraversalDirection? dir;
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        dir = TraversalDirection.down;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        dir = TraversalDirection.up;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        dir = TraversalDirection.left;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        dir = TraversalDirection.right;
      }
      if (dir != null) {
        FocusManager.instance.primaryFocus?.focusInDirection(dir);
        return true;
      }
    }

    return false;
  }

  @override
  void dispose() {
    _keyboardSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _handleEnter() {
    if (_readOnly) {
      _showKeyboard();
    } else {
      final text = widget.controller?.text ?? '';
      widget.onSubmitted?.call(text);
      setState(() {
        _readOnly = true;
        _keyboardOpenedByUs = false;
      });
      _channel.invokeMethod('hide');
      if (widget.onSubmitted == null) _focusNode.unfocus();
    }
  }

  void _showKeyboard() {
    if (!_focusNode.hasFocus) return;
    setState(() {
      _readOnly = false;
      _keyboardOpenedByUs = true;
      _ignoreMetrics = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _channel.invokeMethod('show');
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _ignoreMetrics = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.select): _showKeyboard,
        const SingleActivator(LogicalKeyboardKey.enter): _handleEnter,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _handleEnter,
      },
      child: TextField(
        focusNode: _focusNode,
        controller: widget.controller,
        onChanged: widget.onChanged,
        onSubmitted: (v) {
          widget.onSubmitted?.call(v);
          setState(() {
            _readOnly = true;
            _keyboardOpenedByUs = false;
          });
          _channel.invokeMethod('hide');
          if (widget.onSubmitted == null) _focusNode.unfocus();
        },
        decoration:
            widget.decoration ?? InputDecoration(hintText: widget.hintText),
        style: widget.style,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        enabled: widget.enabled,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscureText,
        autofocus: false,
        readOnly: _readOnly,
        showCursor: !_readOnly,
        enableInteractiveSelection: !_readOnly,
        textInputAction: widget.textInputAction ?? TextInputAction.done,
      ),
    );
  }
}
