import 'dart:io';

import 'package:get/get.dart';
import 'package:nyantv/controllers/source/source_controller.dart';
import 'package:nyantv/utils/tv_text_field.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

class GitHubRepoDialog extends StatefulWidget {
  final ItemType type;
  final String managerId;

  const GitHubRepoDialog({
    super.key,
    required this.type,
    required this.managerId,
  });

  @override
  State<GitHubRepoDialog> createState() => _GitHubRepoDialogState();

  void show({
    required BuildContext context,
  }) {
    showDialog(
      context: context,
      builder: (context) => GitHubRepoDialog(type: type, managerId: managerId),
    );
  }
}

class _GitHubRepoDialogState extends State<GitHubRepoDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _errorMessage;
  bool _isLoading = false;
  final FocusNode _cancelFocusNode = FocusNode();
  final FocusNode _submitFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      setState(() {
        _controller.text = sourceController.activeAnimeRepo;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _cancelFocusNode.dispose();
    _submitFocusNode.dispose();
    super.dispose();
  }

  String? _validateUrl(String url) {
    if (url.isEmpty) {
      return 'Please enter a GitHub repository URL';
    }

    return null;
  }

  void _handleSubmit() async {
    final url = _controller.text.trim();
    final error = _validateUrl(url);

    setState(() {
      _errorMessage = error;
    });

    if (error == null) {
      setState(() {
        _isLoading = true;
      });

      await Future.delayed(const Duration(milliseconds: 500));
      final em = Get.find<ExtensionManager>();
      await em.addRepo(url, widget.type, widget.managerId);

      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      insetPadding:
          Platform.isIOS ? const EdgeInsets.symmetric(horizontal: 8) : null,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer.withOpacity(0.3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      HugeIcons.strokeRoundedGithub,
                      color: colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add ${widget.type.name.toUpperCase()} Repository',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Enter GitHub repository URL',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Repository URL',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _errorMessage != null
                            ? colorScheme.error
                            : colorScheme.outline.withOpacity(0.3),
                        width: 1,
                      ),
                      color: colorScheme.surfaceContainerLowest,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: KeyboardListener(
                        focusNode: FocusNode(),
                        onKeyEvent: (event) {
                          if (event is KeyDownEvent && _focusNode.hasFocus) {
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowDown) {
                              _cancelFocusNode.requestFocus();
                            }
                          }
                        },
                        child: TvTextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            hintText: 'https://github.com/username/repo.json',
                            hintStyle: TextStyle(
                              color:
                                  colorScheme.onSurfaceVariant.withOpacity(0.6),
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              HugeIcons.strokeRoundedLink01,
                              color: colorScheme.onSurfaceVariant,
                              size: 18,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                          onSubmitted: (_) => _handleSubmit(),
                          onChanged: (value) {
                            if (_errorMessage != null) {
                              setState(() {
                                _errorMessage = null;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedAlert02,
                          size: 16,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: Focus(
                          focusNode: _cancelFocusNode,
                          onKeyEvent: (node, event) {
                            if (event is! KeyDownEvent)
                              return KeyEventResult.ignored;
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowUp) {
                              _focusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowRight) {
                              _submitFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey == LogicalKeyboardKey.select ||
                                event.logicalKey == LogicalKeyboardKey.enter) {
                              Navigator.of(context).pop();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: _cancelFocusNode.hasFocus
                                    ? BorderSide(
                                        color: colorScheme.primary,
                                        width: 2,
                                      )
                                    : BorderSide.none,
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Focus(
                          focusNode: _submitFocusNode,
                          onKeyEvent: (node, event) {
                            if (event is! KeyDownEvent)
                              return KeyEventResult.ignored;
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowUp) {
                              _focusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowLeft) {
                              _cancelFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey == LogicalKeyboardKey.select ||
                                event.logicalKey == LogicalKeyboardKey.enter) {
                              _handleSubmit();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: FilledButton(
                            onPressed: _isLoading ? null : _handleSubmit,
                            style: FilledButton.styleFrom(
                              backgroundColor: _submitFocusNode.hasFocus
                                  ? colorScheme.primary.withOpacity(0.85)
                                  : colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: _submitFocusNode.hasFocus
                                    ? BorderSide(
                                        color: colorScheme.onPrimary
                                            .withOpacity(0.4),
                                        width: 2,
                                      )
                                    : BorderSide.none,
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: ExpressiveLoadingIndicator(
                                      color: colorScheme.onPrimary,
                                    ),
                                  )
                                : Text(
                                    'Add Repository',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onPrimary,
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
          ],
        ),
      ),
    );
  }
}
