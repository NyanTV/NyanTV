// lib/screens/anime/watch/controller/tv_remote_handler.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// TV Remote D-Pad handler for video playback
/// Implements menu-state-driven behavior with accumulative long-press seeking
class TVRemoteHandler {
  final Function(Duration) onSeek;
  final Function() onToggleMenu;
  final Function() onExitPlayer;
  final Function() getCurrentPosition;
  final Function() getVideoDuration;
  final Function() isMenuVisible;

  TVRemoteHandler({
    required this.onSeek,
    required this.onToggleMenu,
    required this.onExitPlayer,
    required this.getCurrentPosition,
    required this.getVideoDuration,
    required this.isMenuVisible,
  });

  // Seek configuration
  static const int shortPressSeekSeconds = 10;
  static const int longPressAccumulationStart = 5;
  static const int longPressAccumulationStep = 5;

  // State tracking
  Timer? _longPressTimer;
  int _accumulatedSeekSeconds = 0;
  bool _isLongPressing = false;
  SeekDirection _currentDirection = SeekDirection.none;

  // Visual feedback
  final RxInt seekCounter = 0.obs;
  final RxBool showSeekIndicator = false.obs;
  final Rx<SeekDirection> seekDirection = SeekDirection.none.obs;

  void dispose() {
    _cancelLongPress();
  }

  /// Main key event handler
  bool handleKeyEvent(KeyEvent event) {
    final menuVisible = isMenuVisible();

    if (event is KeyDownEvent) {
      return _handleKeyDown(event, menuVisible);
    } else if (event is KeyRepeatEvent) {
      return _handleKeyRepeat(event, menuVisible);
    } else if (event is KeyUpEvent) {
      return _handleKeyUp(event, menuVisible);
    }

    return false;
  }

  bool _handleKeyRepeat(KeyRepeatEvent event, bool menuVisible) {
    if (menuVisible) return false;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!_isLongPressing) {
        _startLongPress(SeekDirection.backward);
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (!_isLongPressing) {
        _startLongPress(SeekDirection.forward);
      }
      return true;
    }

    return false;
  }


  bool _handleKeyDown(KeyDownEvent event, bool menuVisible) {
    final key = event.logicalKey;

    // Menu visible state
    if (menuVisible) {
      if (key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.escape) {
        onToggleMenu(); // Close menu
        return true;
      }
      // Let menu handle other keys
      return false;
    }

    // Menu hidden state - playback controls active
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter) {
      onToggleMenu(); // Open menu
      return true;
    }

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
      onExitPlayer(); // Exit player
      return true;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _handleLeftKey(event);
      return true;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      _handleRightKey(event);
      return true;
    }

    return false;
  }

  bool _handleKeyUp(KeyUpEvent event, bool menuVisible) {
    final key = event.logicalKey;

    // Only handle directional releases when menu is hidden
    if (!menuVisible) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        _handleDirectionalRelease();
        return true;
      }
    }

    return false;
  }

  void _handleLeftKey(KeyDownEvent event) {
    if (_isLongPressing) return;

    _executeShortPress(SeekDirection.backward);

    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      _startLongPress(SeekDirection.backward);
    });
  }


  void _handleRightKey(KeyDownEvent event) {
    if (_isLongPressing) return;

    _executeShortPress(SeekDirection.forward);

    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      _startLongPress(SeekDirection.forward);
    });
  }



  void _executeShortPress(SeekDirection direction) {
    final currentPos = getCurrentPosition() as Duration;
    final duration = getVideoDuration() as Duration;

    int seekSeconds = direction == SeekDirection.backward
        ? -shortPressSeekSeconds
        : shortPressSeekSeconds;

    final targetPosition = _clampPosition(
      currentPos.inSeconds + seekSeconds,
      duration.inSeconds,
    );

    onSeek(Duration(seconds: targetPosition));
    
    // Show brief indicator
    _showBriefSeekIndicator(direction, shortPressSeekSeconds);
  }

  void _startLongPress(SeekDirection direction) {
    _isLongPressing = true;
    _currentDirection = direction;
    _accumulatedSeekSeconds = longPressAccumulationStart;

    // Show visual feedback
    showSeekIndicator.value = true;
    seekDirection.value = direction;
    seekCounter.value = _accumulatedSeekSeconds;

    // Start accumulation timer
    _longPressTimer?.cancel();
    _longPressTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (timer) => _accumulateSeek(direction),
    );
  }

  void _accumulateSeek(SeekDirection direction) {
    final currentPos = getCurrentPosition() as Duration;
    final duration = getVideoDuration() as Duration;

    // Calculate potential new accumulated value
    int newAccumulated =
        _accumulatedSeekSeconds + longPressAccumulationStep;

    // Calculate target position
    int targetSeconds = direction == SeekDirection.backward
        ? currentPos.inSeconds - newAccumulated
        : currentPos.inSeconds + newAccumulated;

    // Check bounds
    if (targetSeconds < 0 || targetSeconds > duration.inSeconds) {
      // Hit boundary - stop accumulation
      _longPressTimer?.cancel();
      // Keep current accumulated value (don't increment further)
      return;
    }

    // Valid increment
    _accumulatedSeekSeconds = newAccumulated;
    seekCounter.value = _accumulatedSeekSeconds;
  }

  void _handleDirectionalRelease() {
    if (!_isLongPressing) {
      // Was just a short press, already handled
      _cancelLongPress();
      return;
    }

    // Execute accumulated seek
    final currentPos = getCurrentPosition() as Duration;
    final duration = getVideoDuration() as Duration;

    int seekSeconds = _currentDirection == SeekDirection.backward
        ? -_accumulatedSeekSeconds
        : _accumulatedSeekSeconds;

    final targetPosition = _clampPosition(
      currentPos.inSeconds + seekSeconds,
      duration.inSeconds,
    );

    onSeek(Duration(seconds: targetPosition));

    // Reset state
    _cancelLongPress();
    
    // Hide indicator after brief delay
    Future.delayed(const Duration(milliseconds: 500), () {
      showSeekIndicator.value = false;
    });
  }

  void _showBriefSeekIndicator(SeekDirection direction, int seconds) {
    showSeekIndicator.value = true;
    seekDirection.value = direction;
    seekCounter.value = seconds;

    Future.delayed(const Duration(milliseconds: 800), () {
      showSeekIndicator.value = false;
    });
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _isLongPressing = false;
    _accumulatedSeekSeconds = 0;
    _currentDirection = SeekDirection.none;
    seekCounter.value = 0;
  }

  int _clampPosition(int targetSeconds, int maxSeconds) {
    return targetSeconds.clamp(0, maxSeconds);
  }
}

enum SeekDirection {
  none,
  forward,
  backward,
}