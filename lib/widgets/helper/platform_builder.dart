import 'dart:io';
import 'package:nyantv/constants/contants.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

bool _isMobileDevice() {
  try {
    final settings = Get.find<Settings>();
    if (settings.isTV.value) return false; // Android TV is NOT mobile
  } catch (e) {
  }
  return Platform.isAndroid || Platform.isIOS;
}

double getResponsiveSize(context,
    {required double mobileSize,
    required double desktopSize,
    bool isStrict = false}) {
  final currentWidth = MediaQuery.of(context).size.width;
  if (isStrict) {
    if (_isMobileDevice()) {
      return mobileSize;
    } else {
      return desktopSize;
    }
  } else {
    if (currentWidth > maxMobileWidth) {
      return desktopSize;
    } else {
      return mobileSize;
    }
  }
}

dynamic getResponsiveValueWithTablet(
  BuildContext context, {
  required dynamic mobileValue,
  required dynamic tabletValue,
  required dynamic desktopValue,
  bool strictMode = false,
}) {
  final currentWidth = MediaQuery.of(context).size.width;
  const double maxMobileWidth = 600;
  const double maxTabletWidth = 1024;
  final bool isMobilePlatform = _isMobileDevice();

  if (strictMode) {
    if (!isMobilePlatform) {
      return desktopValue;
    } else {
      return mobileValue;
    }
  } else {
    if (currentWidth > maxTabletWidth) {
      return desktopValue;
    } else if (currentWidth > maxMobileWidth) {
      return tabletValue;
    } else {
      return mobileValue;
    }
  }
}

dynamic getResponsiveValue(context,
    {required dynamic mobileValue,
    required dynamic desktopValue,
    bool strictMode = false}) {
  final currentWidth = MediaQuery.of(context).size.width;
  final isMobile = _isMobileDevice();
  if (strictMode) {
    if (!isMobile) {
      return desktopValue;
    } else {
      return mobileValue;
    }
  } else {
    if (currentWidth > maxMobileWidth) {
      return desktopValue;
    } else {
      return mobileValue;
    }
  }
}

dynamic getPlatform(context, {bool strictMode = false}) {
  final currentWidth = MediaQuery.of(context).size.width;
  final isMobile = _isMobileDevice();
  if (strictMode) {
    if (!isMobile) {
      return true;
    } else {
      return false;
    }
  } else {
    if (currentWidth > maxMobileWidth) {
      return true;
    } else {
      return false;
    }
  }
}

int getResponsiveCrossAxisCount(
  BuildContext context, {
  int baseColumns = 2,
  int maxColumns = 6,
  int mobileBreakpoint = 600,
  int tabletBreakpoint = 1200,
  int mobileItemWidth = 200,
  int tabletItemWidth = 200,
  int desktopItemWidth = 200,
}) {
  final currentWidth = MediaQuery.of(context).size.width;
  const mobileBreakpoint = 600;
  const tabletBreakpoint = 1200;

  int crossAxisCount;
  if (currentWidth < mobileBreakpoint) {
    crossAxisCount = (currentWidth / mobileItemWidth).floor();
  } else if (currentWidth < tabletBreakpoint) {
    crossAxisCount = (currentWidth / tabletItemWidth).floor();
  } else {
    crossAxisCount = (currentWidth / desktopItemWidth).floor();
  }

  return crossAxisCount.clamp(baseColumns, maxColumns);
}

class PlatformBuilder extends StatelessWidget {
  final Widget androidBuilder;
  final Widget desktopBuilder;
  final bool strictMode;
  const PlatformBuilder(
      {super.key,
      required this.androidBuilder,
      required this.desktopBuilder,
      this.strictMode = false});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (strictMode) {
        if (!_isMobileDevice()) {
          return desktopBuilder;
        } else {
          return androidBuilder;
        }
      } else {
        if (constraints.maxWidth > maxMobileWidth) {
          return desktopBuilder;
        } else {
          return androidBuilder;
        }
      }
    });
  }
}

class PlatformBuilderWithTablet extends StatelessWidget {
  final Widget androidBuilder;
  final Widget tabletBuilder;
  final Widget desktopBuilder;
  final bool strictMode;
  static const double maxMobileWidth = 500;
  static const double maxTabletWidth = 1024;

  const PlatformBuilderWithTablet({
    super.key,
    required this.androidBuilder,
    required this.tabletBuilder,
    required this.desktopBuilder,
    this.strictMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (strictMode) {
          if (!_isMobileDevice()) {
            return desktopBuilder;
          } else if (constraints.maxWidth > maxMobileWidth) {
            return tabletBuilder;
          } else {
            return androidBuilder;
          }
        } else {
          if (constraints.maxWidth > maxTabletWidth) {
            return desktopBuilder;
          } else if (constraints.maxWidth > maxMobileWidth) {
            return tabletBuilder;
          } else {
            return androidBuilder;
          }
        }
      },
    );
  }
}

class ConditionalBuilder extends StatelessWidget {
  final Widget falseBuilder;
  final Widget trueBuilder;
  final bool condition;
  const ConditionalBuilder(
      {super.key,
      required this.falseBuilder,
      required this.trueBuilder,
      required this.condition});

  @override
  Widget build(BuildContext context) {
    return condition ? trueBuilder : falseBuilder;
  }
}
