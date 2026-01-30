// lib/screens/anime/watch/controls/widgets/tv_seek_indicator.dart
import 'package:anymex/screens/anime/watch/controller/tv_remote_handler.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Visual indicator for TV remote seeking
/// Shows direction and accumulated seek time during long press
class TVSeekIndicator extends StatelessWidget {
  final TVRemoteHandler handler;

  const TVSeekIndicator({
    super.key,
    required this.handler,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!handler.showSeekIndicator.value) {
        return const SizedBox.shrink();
      }

      final direction = handler.seekDirection.value;
      final seconds = handler.seekCounter.value;

      return Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    direction == SeekDirection.forward
                        ? Icons.fast_forward_rounded
                        : Icons.fast_rewind_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        direction == SeekDirection.forward ? '+' : '-',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$seconds',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        's',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hold to seek further',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}