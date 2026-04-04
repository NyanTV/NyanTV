// lib/screens/anime/watch/widgets/shared_player_widgets.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:http/http.dart' as http;
import 'package:nyantv/controllers/settings/methods.dart';
import 'package:nyantv/models/Offline/Hive/video.dart' as model;
import 'package:nyantv/screens/anime/widgets/video_slider.dart';
import 'package:nyantv/utils/skip_times.dart';
import 'package:nyantv/utils/subtitle_server.dart';
import 'package:nyantv/utils/vtt_translator.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:nyantv/widgets/custom_widgets/custom_text.dart';
import 'package:nyantv/widgets/custom_widgets/custom_button.dart';
import 'package:nyantv/widgets/custom_widgets/custom_textspan.dart';
import 'package:nyantv/widgets/custom_widgets/nyantv_progress.dart';
import 'package:nyantv/widgets/helper/platform_builder.dart';
import 'package:nyantv/widgets/helper/tv_wrapper.dart';
import 'package:nyantv/widgets/non_widgets/snackbar.dart';

class ActiveSkip {
  final String label;
  final int start;
  final int end;
  const ActiveSkip(
      {required this.label, required this.start, required this.end});
}

class TVFocusGlass extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final FocusNode? focusNode;

  const TVFocusGlass({
    super.key,
    required this.child,
    required this.borderRadius,
    this.focusNode,
  });

  @override
  State<TVFocusGlass> createState() => _TVFocusGlassState();
}

class _TVFocusGlassState extends State<TVFocusGlass> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(TVFocusGlass old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode?.removeListener(_onFocusChange);
      widget.focusNode?.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    final hasFocus = widget.focusNode?.hasFocus ?? false;
    if (_focused != hasFocus) setState(() => _focused = hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        border: Border.all(
          color: _focused ? Colors.white.withOpacity(0.75) : Colors.transparent,
          width: 2,
        ),
        color: _focused ? Colors.white.withOpacity(0.12) : Colors.transparent,
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: Colors.white.withOpacity(0.08),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: widget.child,
    );
  }
}

Color rotateHue(Color base, double degrees) {
  final hsl = HSLColor.fromColor(base);
  return hsl.withHue((hsl.hue + degrees) % 360).toColor();
}

Widget buildPlayerIcon({VoidCallback? onTap, IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 3),
    child: NyantvOnTap(
      onTap: () => onTap?.call(),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
      ),
    ),
  );
}

Widget buildSubtitleTile(
  String text,
  IconData icon,
  bool isSelected,
  BuildContext context,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5.0),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 2.5, horizontal: 10),
      title: NyantvText(
        text: text,
        variant: TextVariant.bold,
        size: 16,
        color:
            isSelected ? Colors.black : Theme.of(context).colorScheme.primary,
      ),
      tileColor: isSelected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      trailing: Icon(
        icon,
        color:
            isSelected ? Colors.black : Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class PlayerBufferingIndicator extends StatelessWidget {
  const PlayerBufferingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final size = getResponsiveSize(context, mobileSize: 50, desktopSize: 70);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: getResponsiveSize(context, mobileSize: 25, desktopSize: 50),
      ),
      child: SizedBox(
        height: size,
        width: size,
        child: const NyantvProgressIndicator(),
      ),
    );
  }
}

class SkipButtonContent extends StatelessWidget {
  final bool invert;
  final int skipDuration;

  const SkipButtonContent({
    super.key,
    required this.invert,
    required this.skipDuration,
  });

  @override
  Widget build(BuildContext context) {
    if (invert) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.fast_rewind_rounded, color: Colors.white),
          const SizedBox(width: 5),
          NyantvText(
            text: "-${skipDuration}s",
            variant: TextVariant.semiBold,
            color: Colors.white,
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        NyantvText(
          text: "+${skipDuration}s",
          variant: TextVariant.semiBold,
          color: Colors.white,
        ),
        const SizedBox(width: 5),
        const Icon(Icons.fast_forward_rounded, color: Colors.white),
      ],
    );
  }
}

class SegmentOverlay extends StatelessWidget {
  final EpisodeSkipTimes skipTimes;
  final Duration currentPosition;
  final Duration episodeDuration;

  const SegmentOverlay({
    super.key,
    required this.skipTimes,
    required this.currentPosition,
    required this.episodeDuration,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = episodeDuration.inMilliseconds.toDouble();
    if (totalMs <= 0) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      const hPad = 10.0;
      final trackWidth = constraints.maxWidth - hPad * 2;
      const markerH = 7.0;
      final markerTop = (constraints.maxHeight - markerH) / 2;

      final cs = Theme.of(context).colorScheme;
      final currentSecs = currentPosition.inSeconds;

      final segments = <(SkipIntervals?, Color)>[
        (skipTimes.op, rotateHue(cs.primary, 45)),
        (skipTimes.mixedOp, rotateHue(cs.primary, 45)),
        (skipTimes.ed, cs.secondary),
        (skipTimes.mixedEd, cs.secondary),
        (skipTimes.recap, cs.tertiary),
      ];

      final markers = <Widget>[];
      for (final (seg, color) in segments) {
        if (seg == null) continue;
        if (seg.end <= currentSecs) continue;
        final effectiveStart =
            seg.start < currentSecs ? currentSecs : seg.start;
        final startPx = hPad + (effectiveStart * 1000 / totalMs) * trackWidth;
        final endPx = hPad + (seg.end * 1000 / totalMs) * trackWidth;
        final w = endPx - startPx;
        if (w <= 0) continue;
        markers.add(Positioned(
          left: startPx,
          width: w,
          top: markerTop,
          height: markerH,
          child: Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.95),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ));
      }

      if (markers.isEmpty) return const SizedBox.shrink();
      return Stack(children: markers);
    });
  }
}

class SkipOpEdButton extends StatelessWidget {
  final ActiveSkip? skip;
  final FocusNode focusNode;
  final VoidCallback onSkip;

  const SkipOpEdButton({
    super.key,
    required this.skip,
    required this.focusNode,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    if (skip == null) return const SizedBox.shrink();

    final borderRadius = BorderRadius.circular(20.multiplyRoundness());

    final btn = BlurWrapper(
      borderRadius: borderRadius,
      child: Focus(
        focusNode: focusNode,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select) {
            onSkip();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: NyanTVButton(
          height: 50,
          width: 160,
          variant: ButtonVariant.simple,
          borderRadius: borderRadius,
          backgroundColor: Colors.transparent,
          onTap: onSkip,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fast_forward_rounded, color: Colors.white),
              const SizedBox(width: 5),
              NyantvText(
                text: skip!.label,
                variant: TextVariant.semiBold,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );

    return TVFocusGlass(
      borderRadius: borderRadius,
      focusNode: focusNode,
      child: btn,
    );
  }
}

class PlayerControlsHeader extends StatelessWidget {
  final bool isLocked;
  final bool isEpisodeDialogOpen;
  final String episodeNumber;
  final String? episodeTitle;
  final String animeTitle;
  final Color fgColor;
  final VoidCallback onBack;
  final VoidCallback onEpisodeDialog;
  final VoidCallback onSpeedDialog;
  final VoidCallback onToggleLock;

  const PlayerControlsHeader({
    super.key,
    required this.isLocked,
    required this.isEpisodeDialogOpen,
    required this.episodeNumber,
    required this.episodeTitle,
    required this.animeTitle,
    required this.fgColor,
    required this.onBack,
    required this.onEpisodeDialog,
    required this.onSpeedDialog,
    required this.onToggleLock,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isLocked) ...[
          BlurWrapper(
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: getResponsiveSize(context,
                mobileSize: Get.width * 0.3,
                desktopSize:
                    isEpisodeDialogOpen ? Get.width * 0.3 : Get.width * 0.6),
            padding: const EdgeInsets.only(top: 3.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NyantvText(
                  text:
                      'Episode $episodeNumber${episodeTitle != null ? ': $episodeTitle' : ''}',
                  variant: TextVariant.semiBold,
                  maxLines: 3,
                  color: fgColor,
                ),
                NyantvText(
                  text: animeTitle.toUpperCase(),
                  variant: TextVariant.bold,
                  color: Colors.white.withOpacity(0.8),
                ),
              ],
            ),
          ),
        ],
        const Spacer(),
        BlurWrapper(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!isLocked) ...[
                buildPlayerIcon(
                    onTap: onEpisodeDialog,
                    icon: HugeIcons.strokeRoundedFolder03),
                buildPlayerIcon(
                    onTap: onSpeedDialog, icon: HugeIcons.strokeRoundedClock01),
              ],
              buildPlayerIcon(
                onTap: onToggleLock,
                icon: isLocked ? Icons.lock : Icons.lock_open,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class PlayerTimeRow extends StatelessWidget {
  final String formattedTime;
  final String formattedDuration;
  final Color fgColor;
  final bool isLocked;
  final ActiveSkip? activeSkip;
  final Widget skipButton;

  const PlayerTimeRow({
    super.key,
    required this.formattedTime,
    required this.formattedDuration,
    required this.fgColor,
    required this.isLocked,
    required this.activeSkip,
    required this.skipButton,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        NyantvTextSpans(
          maxLines: 1,
          spans: [
            NyantvTextSpan(
              text: '$formattedTime ',
              variant: TextVariant.semiBold,
              color: fgColor.withOpacity(0.8),
            ),
            NyantvTextSpan(
              variant: TextVariant.semiBold,
              text: ' /  $formattedDuration',
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const SizedBox(width: 8),
            if (!isLocked && activeSkip == null) skipButton,
          ],
        ),
      ],
    );
  }
}

void handlePlayerPopInvoked({
  required bool didPop,
  required RxBool isEpisodeDialogOpen,
  required bool isMenuInteractionPaused,
  required VoidCallback startHideControlsTimer,
  required RxBool showControls,
  required VoidCallback toggleControls,
  required bool isLocked,
  required bool shouldTrack,
  required VoidCallback onDiscordUpdate,
}) {
  if (didPop) return;
  if (isEpisodeDialogOpen.value) {
    isEpisodeDialogOpen.value = false;
    startHideControlsTimer();
    return;
  }
  if (showControls.value) {
    toggleControls();
    return;
  }
  if (!isLocked) {
    if (shouldTrack) onDiscordUpdate();
    Get.back();
  }
}

class PlayerSeekBar extends StatelessWidget {
  final Duration currentPosition;
  final Duration episodeDuration;
  final Duration buffered;
  final Color trackColor;
  final Color inactiveColor;
  final bool isLocked;
  final EpisodeSkipTimes? skipTimes;
  final VoidCallback onSeekStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onSeekEnd;

  const PlayerSeekBar({
    super.key,
    required this.currentPosition,
    required this.episodeDuration,
    required this.buffered,
    required this.trackColor,
    required this.inactiveColor,
    required this.isLocked,
    required this.skipTimes,
    required this.onSeekStart,
    required this.onChanged,
    required this.onSeekEnd,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: isLocked,
      child: SizedBox(
        height: 27,
        child: Stack(
          children: [
            VideoSliderTheme(
              color: trackColor,
              inactiveTrackColor: inactiveColor,
              child: Slider(
                focusNode:
                    FocusNode(canRequestFocus: false, skipTraversal: true),
                min: 0,
                value: currentPosition.inMilliseconds.toDouble(),
                max: (currentPosition.inMilliseconds >
                            episodeDuration.inMilliseconds
                        ? currentPosition.inMilliseconds
                        : episodeDuration.inMilliseconds)
                    .toDouble(),
                secondaryTrackValue: buffered.inMilliseconds.toDouble(),
                onChangeStart: (_) => onSeekStart(),
                onChanged: onChanged,
                onChangeEnd: onSeekEnd,
              ),
            ),
            if (skipTimes != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: SegmentOverlay(
                    skipTimes: skipTimes!,
                    currentPosition: currentPosition,
                    episodeDuration: episodeDuration,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

model.Video fetchPreferredStream(
  List<model.Video> video,
  String preferredQuality,
) {
  return video.firstWhere(
    (e) => e.quality == preferredQuality,
    orElse: () {
      snackBar("Preferred Stream Not Found, Selecting ${video[0].quality}");
      return video[0];
    },
  );
}

class SubtitleManager {
  final _server = SubtitleServer();
  String? _activeUrl;
  bool _disposed = false;

  Future<void> start() => _server.start();

  Future<String> normalizeVtt(String url) async {
    _disposed = false;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200 || _disposed) return url;
      String content = response.body;
      content = content.replaceAllMapped(
        RegExp(r'(\d{2}:\d{2}\.\d{3}) --> (\d{2}:\d{2}\.\d{3})'),
        (m) => '00:${m[1]} --> 00:${m[2]}',
      );
      final lang = Get.find<Settings>().subtitleTranslationLang;
      if (lang != 'none' && !_disposed) {
        content = await VttTranslator.translate(content, lang, () => _disposed);
      }
      if (_disposed) return url;
      if (_activeUrl != null) _server.remove(_activeUrl!);
      _activeUrl = _server.serve(content);
      return _activeUrl!;
    } catch (e) {
      return url;
    }
  }

  void dispose() {
    _disposed = true;
    _server.dispose();
    _activeUrl = null;
  }
}
