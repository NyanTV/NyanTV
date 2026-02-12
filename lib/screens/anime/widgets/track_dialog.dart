import 'package:flutter/material.dart';

Future<bool?> showTrackingDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => const TrackingDialog(),
  );
}

class TrackingDialog extends StatelessWidget {
  const TrackingDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.bookmark_add_rounded,
                  size: 32,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Track your progress?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Sync your watch progress with AniList',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.tertiary,
                        foregroundColor: theme.colorScheme.onTertiary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(100),
                            bottomLeft: Radius.circular(100),
                            topRight: Radius.circular(5),
                            bottomRight: Radius.circular(5),
                          ),
                        ),
                      ).copyWith(
                        elevation: MaterialStateProperty.resolveWith<double>(
                          (states) => states.contains(MaterialState.focused) ? 8.0 : 2.0,
                        ),
                        side: MaterialStateProperty.resolveWith<BorderSide>(
                          (states) {
                            if (states.contains(MaterialState.focused)) {
                              return BorderSide(
                                color: theme.colorScheme.tertiary,
                                width: 3.0,
                              );
                            }
                            return BorderSide.none;
                          },
                        ),
                        overlayColor: MaterialStateProperty.resolveWith<Color>(
                          (states) => theme.colorScheme.onTertiary.withOpacity(
                            states.contains(MaterialState.focused) ? 0.2 : 0.1
                          ),
                        ),
                      ),
                      child: const Text('Not now'),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      autofocus: true,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(5),
                            bottomLeft: Radius.circular(5),
                            topRight: Radius.circular(100),
                            bottomRight: Radius.circular(100),
                          ),
                        ),
                      ).copyWith(
                        elevation: MaterialStateProperty.resolveWith<double>(
                          (states) => states.contains(MaterialState.focused) ? 8.0 : 2.0,
                        ),
                        side: MaterialStateProperty.resolveWith<BorderSide>(
                          (states) {
                            if (states.contains(MaterialState.focused)) {
                              return BorderSide(
                                color: theme.colorScheme.primary,
                                width: 3.0,
                              );
                            }
                            return BorderSide.none;
                          },
                        ),
                        overlayColor: MaterialStateProperty.resolveWith<Color>(
                          (states) => theme.colorScheme.onPrimary.withOpacity(
                            states.contains(MaterialState.focused) ? 0.2 : 0.1
                          ),
                        ),
                      ),
                      child: const Text('Track'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}