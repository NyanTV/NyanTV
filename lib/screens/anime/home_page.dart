// ignore_for_file: invalid_use_of_protected_member
import 'package:nyantv/widgets/header.dart';
import 'package:flutter/material.dart';
import 'package:nyantv/utils/tv_scroll_mixin.dart';
import 'package:get/get.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/controllers/settings/settings.dart';

class AnimeHomePage extends StatefulWidget {
  const AnimeHomePage({super.key});

  @override
  State<AnimeHomePage> createState() => _AnimeHomePageState();
}

class _AnimeHomePageState extends State<AnimeHomePage> with TVScrollMixin {
  late ScrollController _scrollController;
  final ValueNotifier<bool> _isAppBarVisible = ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<Settings>().checkForUpdates(context);
      Get.find<Settings>().showWelcomeDialog(context);

      _scrollController.addListener(() {
        final statusBarHeight = MediaQuery.of(context).padding.top;
        const appBarHeight = kToolbarHeight + 20;
        final threshold = statusBarHeight + appBarHeight;
        _isAppBarVisible.value = _scrollController.offset < threshold;
      });
    });
    _scrollController = ScrollController();
    initTVScroll();
  }

  ScrollController get scrollController => _scrollController;

  @override
  void dispose() {
    _scrollController.dispose();
    _isAppBarVisible.dispose();
    disposeTVScroll();
    super.dispose();
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
          SingleChildScrollView(
            controller: _scrollController,
            physics: getTVScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: statusBarHeight + appBarHeight),
                const SizedBox(height: 10),
                Obx(() {
                  return Column(
                    children: serviceHandler.animeWidgets(context),
                  );
                }),
                if (!isDesktop)
                  SizedBox(height: bottomNavBarHeight)
                else
                  const SizedBox(height: 50),
              ],
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