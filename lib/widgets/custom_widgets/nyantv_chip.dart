import 'package:nyantv/controllers/settings/methods.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NyantvChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final Function(bool e) onSelected;
  final bool showCheck;
  const NyantvChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onSelected,
    this.showCheck = true,
  });

  @override
  State<NyantvChip> createState() => _NyantvChipState();
}

class _NyantvChipState extends State<NyantvChip> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  BoxShadow glowingShadow(BuildContext context) {
    final controller = Get.find<Settings>();
    if (controller.glowMultiplier == 0.0) {
      return const BoxShadow(color: Colors.transparent);
    } else {
      return BoxShadow(
        color: Theme.of(context).colorScheme.primary.withOpacity(
            Theme.of(context).brightness == Brightness.dark ? 0.1 : 0.2),
        blurRadius: 20.0.multiplyBlur(),
        spreadRadius: -1.0.multiplyGlow(),
        offset: const Offset(0, 0),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [glowingShadow(context)]),
      child: FilterChip(
        focusNode: _focusNode,
        selected: widget.isSelected,
        onSelected: widget.onSelected,
        label: Text(widget.label),
        side: _focusNode.hasFocus
            ? BorderSide(
                color: Theme.of(context).colorScheme.onSurface,
                width: 2,
              )
            : BorderSide.none,
        labelStyle: TextStyle(
          color: widget.isSelected
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        checkmarkColor: widget.isSelected
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        selectedColor: Theme.of(context).colorScheme.primary,
        showCheckmark: widget.showCheck,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

class NyantvIconChip extends StatefulWidget {
  final Widget icon;
  final bool isSelected;
  final Function(bool e) onSelected;
  final bool showCheck;
  const NyantvIconChip({
    super.key,
    required this.icon,
    required this.isSelected,
    required this.onSelected,
    this.showCheck = true,
  });

  @override
  State<NyantvIconChip> createState() => _NyantvIconChipState();
}

class _NyantvIconChipState extends State<NyantvIconChip> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      focusNode: _focusNode,
      selected: widget.isSelected,
      onSelected: widget.onSelected,
      showCheckmark: widget.showCheck,
      label: widget.icon,
      side: _focusNode.hasFocus
          ? BorderSide(
              color: Theme.of(context).colorScheme.onSurface,
              width: 2,
            )
          : BorderSide.none,
      checkmarkColor: widget.isSelected
          ? Theme.of(context).colorScheme.onPrimary
          : Theme.of(context).colorScheme.onSurfaceVariant,
      labelStyle: TextStyle(
        color: widget.isSelected
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      selectedColor: Theme.of(context).colorScheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}