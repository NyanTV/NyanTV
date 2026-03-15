// ignore_for_file: invalid_use_of_protected_member
import 'package:nyantv/widgets/header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nyantv/utils/tv_scroll_mixin.dart';
import 'package:get/get.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/main.dart';

class AnimeHomePage extends StatefulWidget {
  final bool isActive;
  const AnimeHomePage({super.key, this.isActive = true});

  @override
  State<AnimeHomePage> createState() => _AnimeHomePageState();
}

class _AnimeHomePageState extends State<AnimeHomePage> with TVScrollMixin {
  late ScrollController _scrollController;
  final ValueNotifier<bool> _isAppBarVisible = ValueNotifier<bool>(true);

  @override
  ScrollController get scrollController => _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    initTVScroll();

    isAnimePageActive.value = widget.isActive;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<Settings>().checkForUpdates(context);
      _scrollController.addListener(() {
        final statusBarHeight = MediaQuery.of(context).padding.top;
        const appBarHeight = kToolbarHeight + 20;
        final threshold = statusBarHeight + appBarHeight;
        _isAppBarVisible.value = _scrollController.offset < threshold;
        final carouselHeight =
            MediaQuery.of(context).size.width > 600 ? 450.0 : 270.0;
        final carouselVisible = _scrollController.offset < carouselHeight;
        isAnimePageActive.value = widget.isActive && carouselVisible;
      });
    });
  }

  @override
  void didUpdateWidget(AnimeHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (!widget.isActive) {
        isAnimePageActive.value = false;
      } else {
        final carouselHeight =
            MediaQuery.of(context).size.width > 600 ? 450.0 : 270.0;
        final carouselVisible = _scrollController.offset < carouselHeight;
        isAnimePageActive.value = carouselVisible;
      }
    }
  }

  @override
  void dispose() {
    isAnimePageActive.value = false;
    _scrollController.dispose();
    _isAppBarVisible.dispose();
    disposeTVScroll();
    super.dispose();
  }

  KeyEventResult _handleTVKeyEvent(FocusNode node, KeyEvent event) {
    if (!Get.find<Settings>().isTV.value) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }

    if (_scrollController.hasClients && _scrollController.offset > 0) {
      final statusBarHeight = MediaQuery.of(context).padding.top;
      const appBarHeight = kToolbarHeight + 10;
      final scrollStep =
          _scrollController.offset < (statusBarHeight + appBarHeight + 40)
              ? statusBarHeight + appBarHeight + 40
              : 140.0;
      final target = (_scrollController.offset - scrollStep).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      if (target < 20.0) {
        _scrollController.jumpTo(0);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final serviceHandler = Get.find<ServiceHandler>();
    bool isTV = Get.find<Settings>().isTV.value;
    final isDesktop = isTV ? true : MediaQuery.of(context).size.width > 600;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    const appBarHeight = kToolbarHeight + 20;
    final double bottomNavBarHeight = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Focus(
            onKeyEvent: _handleTVKeyEvent,
            skipTraversal: true,
            canRequestFocus: false,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: getTVScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: statusBarHeight + appBarHeight),
                  const SizedBox(height: 10),
                  Obx(() => Column(
                        children: serviceHandler.animeWidgets(context),
                      )),
                  if (!isDesktop)
                    SizedBox(height: bottomNavBarHeight)
                  else
                    const SizedBox(height: 50),
                ],
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _isAppBarVisible,
            builder: (context, isVisible, _) => Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: isVisible
                  ? Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      padding: EdgeInsets.only(
                        top: statusBarHeight,
                        bottom: 10,
                      ),
                      child: const Header(type: PageType.anime),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
