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
  });

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _readOnly = true; // starts as readOnly
  static const _channel = MethodChannel('app/keyboard');

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _showKeyboard() {
    if (!_focusNode.hasFocus) return;
    setState(() => _readOnly = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _channel.invokeMethod('show');
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.select): _showKeyboard,
        SingleActivator(LogicalKeyboardKey.enter): _showKeyboard,
        SingleActivator(LogicalKeyboardKey.numpadEnter): _showKeyboard,
      },
      child: TextField(
        focusNode: _focusNode,
        controller: widget.controller,
        onChanged: widget.onChanged,
        onSubmitted: (v) {
          widget.onSubmitted?.call(v);
          setState(() => _readOnly = true);
          _channel.invokeMethod('hide');
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
      ),
    );
  }
}
