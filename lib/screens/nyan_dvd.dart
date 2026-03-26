import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/controllers/discord/discord_rpc.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:nyantv/main.dart';
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';

List<double> _calcVisualBounds(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final w = args['w'] as int;
  final h = args['h'] as int;
  int minX = w, minY = h, maxX = 0, maxY = 0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (bytes[(y * w + x) * 4 + 3] > 10) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }
  return [minX / w, minY / h, (maxX + 1) / w, (maxY + 1) / h];
}

final Map<Color, ui.Image> _tintedImages = {};
ui.Image? _activeImage;

Future<ui.Image> _bakeImage(ui.Image src, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImage(src, Offset.zero,
      Paint()..colorFilter = ColorFilter.mode(color, BlendMode.modulate));
  final picture = recorder.endRecording();
  return picture.toImage(src.width, src.height);
}

class InitialisingScreen extends StatefulWidget {
  final Widget child;
  final bool dvdMode;
  const InitialisingScreen(
      {super.key, required this.child, this.dvdMode = false});

  @override
  State<InitialisingScreen> createState() => _InitialisingScreenState();
}

class _InitialisingScreenState extends State<InitialisingScreen>
    with WidgetsBindingObserver {
  bool _isReady = false;
  double _opacity = 1.0;
  Timer? _rpcUpdateTimer;
  bool _initStarted = false;

  @override
  void initState() {
    super.initState();
    setExcludedScreen(true);
    WidgetsBinding.instance.addObserver(this);

    if (widget.dvdMode) {
      setDVDMode(true);
      WakelockPlus.enable();
      _rpcUpdateTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        DiscordRPCController.instance.updateBrowsingPresence(
          activity: 'NyanDVD',
          details: 'Idle',
        );
      });
      DiscordRPCController.instance.updateBrowsingPresence(
        activity: 'NyanDVD',
        details: 'Idle',
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startInit();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_initStarted) {
      _startInit();
    }
  }

  void _startInit() {
    if (_initStarted) return;
    _initStarted = true;
    _waitForInit();
  }

  Future<void> _waitForInit() async {
    final serviceHandler = Get.find<ServiceHandler>();
    final isFirstTime =
        Hive.box('themeData').get('isFirstTime', defaultValue: true);
    final minWait = isFirstTime
        ? const Duration(milliseconds: 3000)
        : const Duration(milliseconds: 1500);
    const maxWait = Duration(seconds: 10);
    final start = DateTime.now();

    await Future.wait([
      _precacheWelcomeAssets(),
      _waitForService(serviceHandler, start, minWait, maxWait),
    ]);

    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _opacity = 0.0);
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() => _isReady = true);
      if (!widget.dvdMode) {
        setExcludedScreen(false);
        final isFirstTime =
            Hive.box('themeData').get('isFirstTime', defaultValue: true);
        if (isFirstTime) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Get.find<Settings>().showWelcomeDialog(context);
          });
        }
      }
    }
  }

  Future<void> _waitForService(ServiceHandler handler, DateTime start,
      Duration minWait, Duration maxWait) async {
    while (DateTime.now().difference(start) < maxWait) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (DateTime.now().difference(start) >= minWait &&
          _isServiceReady(handler)) {
        break;
      }
    }
  }

  Future<void> _precacheWelcomeAssets() async {
    final isFirstTime =
        Hive.box('themeData').get('isFirstTime', defaultValue: true);
    if (!isFirstTime) return;

    if (!mounted) return;
    await precacheImage(
      const AssetImage('assets/images/logo_transparent.png'),
      context,
    );

    if (!mounted) return;
    await Future.wait([
      precacheImage(
          const AssetImage('assets/images/anilist-icon.png'), context),
      precacheImage(const AssetImage('assets/images/mal-icon.png'), context),
      precacheImage(const AssetImage('assets/images/simkl-icon.png'), context),
    ]);
  }

  bool _isServiceReady(ServiceHandler handler) =>
      handler.isLoggedIn.value ||
      (handler.profileData.value.name?.isNotEmpty ?? false);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rpcUpdateTimer?.cancel();
    if (widget.dvdMode) {
      WakelockPlus.disable();
      setDVDMode(false);
    }
    setExcludedScreen(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final physicalSize = view.physicalSize;
    final devicePixelRatio = view.devicePixelRatio;
    final realWidth = physicalSize.width / devicePixelRatio;
    final realHeight = physicalSize.height / devicePixelRatio;

    final bypass = UIScaleBypass.of(context);
    final isScaled = bypass?.bypassScale == true;
    final settings = Get.find<Settings>();
    final scale =
        (isScaled && settings.uiScale > 0.0 && settings.uiScale != 1.0)
            ? settings.uiScale
            : 1.0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF08080F) : const Color(0xFFF4F4F9);
    final textColor = (isDark ? Colors.white : Colors.black).withOpacity(0.35);
    final primary = Theme.of(context).colorScheme.primary;

    final neutralMediaQuery = MediaQuery.of(context).copyWith(
      textScaler: const TextScaler.linear(1.0),
      size: Size(realWidth, realHeight),
      devicePixelRatio: devicePixelRatio,
    );

    final scaffold = Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: _CachedDotGrid(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
              ),
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.85,
                    colors: [
                      primary.withOpacity(isDark ? 0.07 : 0.04),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: _DVDBounceLayer(dvdMode: widget.dvdMode),
            ),
          ),
          Positioned(
            bottom: 52,
            left: 0,
            right: 0,
            child: RepaintBoundary(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!widget.dvdMode)
                    const SizedBox(
                        width: 20,
                        height: 20,
                        child: ExpressiveLoadingIndicator()),
                  const SizedBox(height: 14),
                  Text(
                    widget.dvdMode ? 'PRESS BACK TO RETURN' : 'INITIALISING',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 3.5,
                      color: textColor,
                      fontFamily: 'Poppins-SemiBold',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    Widget content;
    if (scale != 1.0) {
      content = OverflowBox(
        minWidth: realWidth,
        maxWidth: realWidth,
        minHeight: realHeight,
        maxHeight: realHeight,
        alignment: Alignment.topLeft,
        child: Transform.scale(
          scale: 1.0 / scale,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: realWidth,
            height: realHeight,
            child: scaffold,
          ),
        ),
      );
    } else {
      content = scaffold;
    }

    return Stack(
      children: [
        widget.child,
        if (!_isReady)
          MediaQuery(
            data: neutralMediaQuery,
            child: AnimatedOpacity(
              opacity: _opacity,
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOut,
              child: content,
            ),
          ),
      ],
    );
  }
}

class _DVDBounceLayer extends StatefulWidget {
  final bool dvdMode;
  const _DVDBounceLayer({required this.dvdMode});

  @override
  State<_DVDBounceLayer> createState() => _DVDBounceLayerState();
}

class _DVDBounceLayerState extends State<_DVDBounceLayer>
    with TickerProviderStateMixin {
  double _x = 120.0;
  double _y = 130.0;
  double _vx = 1.8;
  double _vy = 1.5;
  double _maxX = 0.0;
  double _maxY = 0.0;
  late final double _logoSize;

  static const double _speed = 1.6;

  static const List<Color> _bounceColors = [
    Colors.white,
    Color(0xFF818CF8),
    Color(0xFF34D399),
    Color(0xFFF472B6),
    Color(0xFFFBBF24),
    Color(0xFF60A5FA),
    Color(0xFFA78BFA),
  ];
  int _colorIndex = 0;

  Color _fromColor = Colors.white;
  Color _toColor = Colors.white;
  Color _currentColor = Colors.white;
  double _colorT = 1.0;

  double _hue = 0.0;

  ui.Image? _logoImage;
  double _logoVisualLeft = 0.0;
  double _logoVisualTop = 0.0;
  double _logoVisualRight = 1.0;
  double _logoVisualBottom = 1.0;
  bool _boundsCalculated = false;

  static const double _fixedDtMs = 1000.0 / 120.0;
  double _accumulator = 0.0;
  double _renderX = 120.0;
  double _renderY = 130.0;
  double _prevX = 120.0;
  double _prevY = 130.0;

  final _repaintNotifier = _RepaintNotifier();
  late final Ticker _ticker;
  Duration _lastTickTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    ever(isBackButtonPressed, (pressed) {
      if (pressed && mounted) {
        isBackButtonPressed.value = false;
        Get.back();
      }
    });
    _logoSize = widget.dvdMode ? 150.0 : 350.0;

    final rng = Random();
    _vx = _speed * (rng.nextBool() ? 1.0 : -1.0);
    _vy = _speed * (rng.nextBool() ? 1.0 : -1.0) * 0.85;

    if (widget.dvdMode) {
      _loadImageAndBounds();
    } else {
      _loadImage();
    }

    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _loadImage() async {
    final data = await rootBundle.load('assets/images/logo_transparent.png');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: (_logoSize * 2).toInt(),
      targetHeight: (_logoSize * 2).toInt(),
    );
    final frame = await codec.getNextFrame();
    if (mounted) {
      _logoImage = frame.image;
      _repaintNotifier.notify();
    }
  }

  Future<void> _loadImageAndBounds() async {
    final data = await rootBundle.load('assets/images/logo_transparent.png');

    final codecFull = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frameFull = await codecFull.getNextFrame();
    final fullImage = frameFull.image;
    final byteData =
        await fullImage.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData != null) {
      final result = await compute(_calcVisualBounds, {
        'bytes': byteData.buffer.asUint8List(),
        'w': fullImage.width,
        'h': fullImage.height,
      });
      _logoVisualLeft = result[0];
      _logoVisualTop = result[1];
      _logoVisualRight = result[2];
      _logoVisualBottom = result[3];
      _boundsCalculated = true;
    }

    final codecScaled = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: (_logoSize * 2).toInt(),
      targetHeight: (_logoSize * 2).toInt(),
    );
    final frameScaled = await codecScaled.getNextFrame();
    if (mounted) {
      _logoImage = frameScaled.image;
      for (final color in _bounceColors) {
        _tintedImages[color] = await _bakeImage(_logoImage!, color);
      }
      _activeImage = _tintedImages[_bounceColors[0]];
      _repaintNotifier.notify();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final deltaMs = _lastTickTime == Duration.zero
        ? 16.667
        : (elapsed - _lastTickTime).inMicroseconds / 1000.0;
    _lastTickTime = elapsed;

    if (widget.dvdMode) {
      _accumulator += deltaMs.clamp(0.0, _fixedDtMs * 3);

      _prevX = _x;
      _prevY = _y;

      while (_accumulator >= _fixedDtMs) {
        _stepPhysics(_fixedDtMs);
        _accumulator -= _fixedDtMs;
      }

      final alpha = _accumulator / _fixedDtMs;
      _renderX = (_prevX + (_x - _prevX) * alpha);
      _renderY = (_prevY + (_y - _prevY) * alpha);

      _repaintNotifier.notify();
    } else {
      _updateStaticColorAnimation();
    }
  }

  void _stepPhysics(double dt) {
    if (_maxX <= 0.0 || _maxY <= 0.0) return;

    final vLeft = _boundsCalculated ? _logoVisualLeft * _logoSize : 0.0;
    final vTop = _boundsCalculated ? _logoVisualTop * _logoSize : 0.0;
    final vRight = _boundsCalculated ? _logoVisualRight * _logoSize : _logoSize;
    final vBottom =
        _boundsCalculated ? _logoVisualBottom * _logoSize : _logoSize;

    final minX = -vLeft;
    final maxX = _maxX + (_logoSize - vRight);
    final minY = -vTop;
    final maxY = _maxY + (_logoSize - vBottom);

    final step = _speed * (dt / 16.667);
    double nx = _x + _vx * step;
    double ny = _y + _vy * step;
    bool bounced = false;

    if (nx <= minX || nx >= maxX) {
      _vx = -_vx;
      nx = nx.clamp(minX, maxX);
      bounced = true;
    }
    if (ny <= minY || ny >= maxY) {
      _vy = -_vy;
      ny = ny.clamp(minY, maxY);
      bounced = true;
    }

    if (bounced) {
      _fromColor = _currentColor;
      _colorIndex = (_colorIndex + 1) % _bounceColors.length;
      _toColor = _bounceColors[_colorIndex];
      _colorT = 0.0;
      _activeImage = _tintedImages[_toColor];
    }

    if (_colorT < 1.0) {
      _colorT = (_colorT + dt / 320.0).clamp(0.0, 1.0);
      _currentColor =
          Color.lerp(_fromColor, _toColor, Curves.easeOut.transform(_colorT))!;
    }

    _x = nx;
    _y = ny;
  }

  void _updateStaticColorAnimation() {
    _hue = (_hue + 0.5) % 360.0;
    _currentColor = HSVColor.fromAHSV(1.0, _hue, 0.7, 0.95).toColor();
    _repaintNotifier.notify();
  }

  @override
  void dispose() {
    _ticker
      ..stop()
      ..dispose();
    _repaintNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _maxX = constraints.maxWidth - _logoSize;
      _maxY = constraints.maxHeight - _logoSize;

      return AnimatedBuilder(
        animation: _repaintNotifier,
        builder: (_, __) => CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _LogoPainter(
            image: _logoImage,
            x: widget.dvdMode
                ? _renderX
                : (constraints.maxWidth - _logoSize) / 2,
            y: widget.dvdMode
                ? _renderY
                : (constraints.maxHeight - _logoSize) / 2,
            size: _logoSize,
            color: _currentColor,
          ),
        ),
      );
    });
  }
}

class _CachedDotGrid extends StatelessWidget {
  final Color color;
  const _CachedDotGrid({required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DotGridPainter(color: color),
      isComplex: false,
      willChange: false,
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final Color color;
  _DotGridPainter({required this.color});

  static List<Offset>? _cachedPoints;
  static Size _cachedSize = Size.zero;

  late final Paint _paint = Paint()
    ..color = color
    ..style = PaintingStyle.fill
    ..isAntiAlias = false
    ..strokeWidth = 2.4;

  @override
  void paint(Canvas canvas, Size size) {
    if (_cachedPoints == null || _cachedSize != size) {
      const spacing = 28.0;
      final points = <Offset>[];
      for (double x = spacing; x < size.width; x += spacing) {
        for (double y = spacing; y < size.height; y += spacing) {
          points.add(Offset(x, y));
        }
      }
      _cachedPoints = points;
      _cachedSize = size;
    }
    canvas.drawPoints(ui.PointMode.points, _cachedPoints!, _paint);
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}

class _RepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _LogoPainter extends CustomPainter {
  final ui.Image? image;
  final double x, y, size;
  final Color color;

  _LogoPainter({
    required this.image,
    required this.x,
    required this.y,
    required this.size,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (image == null) return;
    final paint = Paint()
      ..colorFilter = ColorFilter.mode(color, BlendMode.modulate)
      ..filterQuality = FilterQuality.low;
    canvas.drawImageRect(
      image!,
      Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble()),
      Rect.fromLTWH(x, y, size, size),
      paint,
    );
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.x != x || old.y != y || old.color != color || old.image != image;
}
