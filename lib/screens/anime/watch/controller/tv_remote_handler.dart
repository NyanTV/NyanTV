// lib/screens/anime/watch/controller/tv_remote_handler.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';

/// TV Remote D-Pad handler for video playback
/// Implements menu-state-driven behavior with enhanced features
class TVRemoteHandler {
  final Player player;
  final Function(Duration) onSeek;
  final Function() onToggleMenu;
  final Function() onExitPlayer;
  final Duration Function() getCurrentPosition;
  final Duration Function() getVideoDuration;
  final bool Function() isMenuVisible;
  final bool Function() isLocked;
  final BuildContext context;
  final int seekDuration;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onPreviousEpisode;
  final Function(bool)? onSkipSegments;
  final VoidCallback? onMenuInteraction;

  TVRemoteHandler({
    required this.player,
    required this.onSeek,
    required this.onToggleMenu,
    required this.onExitPlayer,
    required this.getCurrentPosition,
    required this.getVideoDuration,
    required this.isMenuVisible,
    required this.isLocked,
    required this.context,
    this.seekDuration = 10,
    this.onPlayPause,
    this.onNextEpisode,
    this.onPreviousEpisode,
    this.onSkipSegments,
    this.onMenuInteraction,
  });

  // Seek configuration
  int get shortPressSeekSeconds => seekDuration;
  Timer? _holdTimer;
  Timer? _accelerationTimer;
  int _accumulatedSeekSeconds = 0;
  SeekDirection? _currentHoldDirection;

  void dispose() {
    _cancelHoldTimers();
  }

  /// Main key event handler
  KeyEventResult handleKeyEvent(FocusNode node, KeyEvent event) {
    // Check if player is locked
    if (isLocked()) {
      // Only allow unlock action when locked
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          // Let the unlock button handle this
          return KeyEventResult.ignored;
        }
      }
      return KeyEventResult.handled; // Block all other keys when locked
    }

    final menuVisible = isMenuVisible();

    if (event is KeyDownEvent) {
      final result = _handleKeyDown(event, menuVisible);
      return result ? KeyEventResult.handled : KeyEventResult.ignored;
    } else if (event is KeyUpEvent) {
      final result = _handleKeyUp(event, menuVisible);
      return result ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  bool _handleKeyDown(KeyDownEvent event, bool menuVisible) {
    final key = event.logicalKey;

    // Menu visible state - Controls are shown
    if (menuVisible) {
      // Back/Escape closes menu
      if (key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.escape) {
        onToggleMenu(); // Close menu
        return true;
      }

      // Arrow keys for focus navigation when menu is visible
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        _handleFocusNavigation(key);
        onMenuInteraction?.call();
        return true;
      }

      // Enter/Select activates focused item
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter) {
        return false; // Allow Flutter to handle activation
      }

      // Media keys work even when menu is visible
      if (key == LogicalKeyboardKey.mediaPlayPause) {
        onPlayPause?.call();
        return true;
      }

      // Consume all other keys when menu is visible
      onMenuInteraction?.call();
      return true;
    }
    // Menu hidden state - Playback controls active

    
    // Select/Enter opens menu
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter) {
      onToggleMenu(); // Open menu
      return true;
    }

    // Back/Escape exits player
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
      onExitPlayer(); // Exit player
      return true;
    }

    // Arrow Left - Seek backward
    if (key == LogicalKeyboardKey.arrowLeft) {
      _startHoldSeek(SeekDirection.backward);
      return true;
    }

    // Arrow Right - Seek forward
    if (key == LogicalKeyboardKey.arrowRight) {
      _startHoldSeek(SeekDirection.forward);
      return true;
    }

    // Arrow Up - Next episode
    if (key == LogicalKeyboardKey.arrowUp) {
      onNextEpisode?.call();
      return true;
    }

    // Arrow Down - Previous episode
    if (key == LogicalKeyboardKey.arrowDown) {
      onPreviousEpisode?.call();
      return true;
    }

    // Media play/pause
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space) {
      onPlayPause?.call();
      return true;
    }

    // Media keys for seeking
    if (key == LogicalKeyboardKey.mediaRewind) {
      _handleSeek(SeekDirection.backward);
      return true;
    }

    if (key == LogicalKeyboardKey.mediaFastForward) {
      _handleSeek(SeekDirection.forward);
      return true;
    }

    return false;
  }

  bool _handleKeyUp(KeyUpEvent event, bool menuVisible) {
    final key = event.logicalKey;

    if (!menuVisible) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        _executeAccumulatedSeek();
        return true;
      }
    }

    return false;
  }

  void _handleFocusNavigation(LogicalKeyboardKey key) {
    final focusScope = FocusScope.of(context);
    
    switch (key) {
      case LogicalKeyboardKey.arrowLeft:
        focusScope.focusInDirection(TraversalDirection.left);
        break;
      case LogicalKeyboardKey.arrowRight:
        focusScope.focusInDirection(TraversalDirection.right);
        break;
      case LogicalKeyboardKey.arrowUp:
        focusScope.focusInDirection(TraversalDirection.up);
        break;
      case LogicalKeyboardKey.arrowDown:
        focusScope.focusInDirection(TraversalDirection.down);
        break;
      default:
        break;
    }
  }

  void _handleSeek(SeekDirection direction) {
    // Use the skip segments function if available (for visual feedback)
    if (onSkipSegments != null) {
      onSkipSegments!(direction == SeekDirection.backward);
      return;
    }

    // Fallback to direct seeking
    final currentPos = getCurrentPosition();
    final duration = getVideoDuration();

    int seekSeconds = direction == SeekDirection.backward
        ? -shortPressSeekSeconds
        : shortPressSeekSeconds;

    final targetPosition = _clampPosition(
      currentPos.inSeconds + seekSeconds,
      duration.inSeconds,
    );

    onSeek(Duration(seconds: targetPosition));
  }

  int _clampPosition(int targetSeconds, int maxSeconds) {
    return targetSeconds.clamp(0, maxSeconds);
  }

  void _startHoldSeek(SeekDirection direction) {
    _cancelHoldTimers();
    _currentHoldDirection = direction;
    _accumulatedSeekSeconds = shortPressSeekSeconds;
    
    // Initial seek feedback
    if (onSkipSegments != null) {
      onSkipSegments!(direction == SeekDirection.backward);
    }
    
    // Start acceleration after 1 second
    _holdTimer = Timer(const Duration(seconds: 1), () {
      _accelerationTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _accumulatedSeekSeconds += shortPressSeekSeconds;
        if (onSkipSegments != null) {
          onSkipSegments!(direction == SeekDirection.backward);
        }
      });
    });
  }

  void _executeAccumulatedSeek() {
    _cancelHoldTimers();
    
    if (_currentHoldDirection != null && _accumulatedSeekSeconds > 0) {
      final currentPos = getCurrentPosition();
      final duration = getVideoDuration();
      
      int seekSeconds = _currentHoldDirection == SeekDirection.backward
          ? -_accumulatedSeekSeconds
          : _accumulatedSeekSeconds;
      
      final targetPosition = _clampPosition(
        currentPos.inSeconds + seekSeconds,
        duration.inSeconds,
      );
      
      onSeek(Duration(seconds: targetPosition));
    }
    
    _accumulatedSeekSeconds = 0;
    _currentHoldDirection = null;
  }

  void _cancelHoldTimers() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _accelerationTimer?.cancel();
    _accelerationTimer = null;
  }

}

enum SeekDirection {
  none,
  forward,
  backward,
}