// lib/utils/tv_scroll_mixin.dart
// Universal Mixin for TV Auto-Scroll

import 'package:nyantv/controllers/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 
/// Usage:
/// ```dart
/// class _MyPageState extends State<MyPage> with TVScrollMixin {
///   @override
///   void initState() {
///     super.initState();
///     initTVScroll();
///   }
///   
///   @override
///   void dispose() {
///     disposeTVScroll();
///     super.dispose();
///   }
/// }
/// ```
mixin TVScrollMixin<T extends StatefulWidget> on State<T> {
  
  void initTVScroll() {
    if (Get.find<Settings>().isTV.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusManager.instance.addListener(_handleTVFocusChange);
      });
    }
  }
  
  void disposeTVScroll() {
    if (Get.find<Settings>().isTV.value) {
      FocusManager.instance.removeListener(_handleTVFocusChange);
    }
  }
  
  void _handleTVFocusChange() {
    if (!mounted) return;
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext != null) {
      Scrollable.ensureVisible(
        focusedContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
  }
  
  ScrollPhysics getTVScrollPhysics() {
    return Get.find<Settings>().isTV.value
        ? const BouncingScrollPhysics()
        : const AlwaysScrollableScrollPhysics();
  }
}
