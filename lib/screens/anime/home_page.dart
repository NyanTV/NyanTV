// ignore_for_file: invalid_use_of_protected_member

import 'package:nyantv/widgets/header.dart';
import 'package:nyantv/widgets/helper/platform_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nyantv/utils/tv_scroll_mixin.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';

import 'package:nyantv/controllers/cacher/cache_controller.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/controllers/settings/methods.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/widgets/common/scroll_aware_app_bar.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_button.dart';
import 'package:nyantv/widgets/custom_widgets/custom_text.dart';
import 'package:nyantv/widgets/custom_widgets/custom_textspan.dart';
import 'package:nyantv/widgets/history/tap_history_cards.dart';
import 'package:nyantv/widgets/non_widgets/snackbar.dart';

class AnimeHomePage extends StatefulWidget {
  const AnimeHomePage({
    super.key,
  });

  @override
  State<AnimeHomePage> createState() => _AnimeHomePageState();
}

class _AnimeHomePageState extends State<AnimeHomePage> with TVScrollMixin {
  late ScrollController _scrollController;
  final ValueNotifier<bool> _isAppBarVisibleExternally =
      ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<Settings>().checkForUpdates(context);
      Get.find<Settings>().showWelcomeDialog(context);
    });
    _scrollController = ScrollController();
    initTVScroll();
  }

  ScrollController get scrollController => _scrollController;

  @override
  void dispose() {
    _scrollController.dispose();
    _isAppBarVisibleExternally.dispose();
    
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
          CustomAnimatedAppBar(
            isVisible: _isAppBarVisibleExternally,
            scrollController: _scrollController,
            headerContent: const Header(type: PageType.anime),
            visibleStatusBarStyle: SystemUiOverlayStyle(
              statusBarIconBrightness:
                  Theme.of(context).brightness == Brightness.light
                      ? Brightness.dark
                      : Brightness.light,
              statusBarBrightness: Theme.of(context).brightness,
              statusBarColor: Colors.transparent,
            ),
            hiddenStatusBarStyle: SystemUiOverlayStyle(
              statusBarIconBrightness:
                  Theme.of(context).brightness == Brightness.light
                      ? Brightness.light
                      : Brightness.dark,
              statusBarBrightness:
                  Theme.of(context).brightness == Brightness.light
                      ? Brightness.dark
                      : Brightness.light,
              statusBarColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}