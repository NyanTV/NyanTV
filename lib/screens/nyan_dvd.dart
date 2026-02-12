import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:nyantv/controllers/service_handler/service_handler.dart';
import 'package:nyantv/controllers/discord/discord_rpc.dart';
import 'package:nyantv/controllers/settings/settings.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:nyantv/main.dart';

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
    WidgetsBinding.instance.addObserver(this);

    if (widget.dvdMode) {
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
      final state = SchedulerBinding.instance.lifecycleState;
      if (state == AppLifecycleState.resumed) {
        _startInit();
      }
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
    const minWait = Duration(milliseconds: 900);
    const maxWait = Duration(seconds: 10);
    final start = DateTime.now();

    while (DateTime.now().difference(start) < maxWait) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (DateTime.now().difference(start) >= minWait &&
          _isServiceReady(serviceHandler)) break;
    }

    if (!mounted) return;
    setState(() => _opacity = 0.0);
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() => _isReady = true);
  }

  bool _isServiceReady(ServiceHandler handler) =>
      handler.isLoggedIn.value ||
      (handler.profileData.value.name?.isNotEmpty ?? false);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rpcUpdateTimer?.cancel();
    if (widget.dvdMode) WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isReady) return widget.child;

    final view = View.of(context);
    final physicalSize = view.physicalSize;
    final devicePixelRatio = view.devicePixelRatio;
    final realWidth = physicalSize.width / devicePixelRatio;
    final realHeight = physicalSize.height / devicePixelRatio;

    final bypass = UIScaleBypass.of(context);
    final isScaled = bypass?.bypassScale == true;
    final settings = Get.find<Settings>();
    final scale = (isScaled && settings.uiScale > 0.0 && settings.uiScale != 1.0)
        ? settings.uiScale
        : 1.0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF08080F) : const Color(0xFFF4F4F9);
    final textColor =
        (isDark ? Colors.white : Colors.black).withOpacity(0.35);
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
            child: _DVDBounceLayer(dvdMode: widget.dvdMode),
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
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: primary.withOpacity(0.7),
                      ),
                    ),
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

    return MediaQuery(
      data: neutralMediaQuery,
      child: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOut,
        child: content,
      ),
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
  double _y = 140.0;
  double _vx = 1.8;
  double _vy = 1.5;
  double _maxX = 0.0;
  double _maxY = 0.0;

  static const double _logoSize = 95.0;
  static const double _speed = 4.2;

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

  late final AnimationController _colorCtrl;
  late Animation<Color?> _colorAnim;
  Color _fromColor = Colors.white;
  Color _toColor = Colors.white;

  late final Ticker _ticker;
  Duration _lastTickTime = Duration.zero;
  static const Duration _targetFrameDuration = Duration(milliseconds: 33); // ~30 FPS

  double _hue = 0.0;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _vx = _speed * (rng.nextBool() ? 1.0 : -1.0);
    _vy = _speed * (rng.nextBool() ? 1.0 : -1.0) * 0.85;

    _colorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _rebuildColorAnim();

    _ticker = createTicker(_onTick)..start();
  }

  void _rebuildColorAnim() {
    _colorAnim = ColorTween(begin: _fromColor, end: _toColor)
        .animate(CurvedAnimation(parent: _colorCtrl, curve: Curves.easeOut));
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    if (elapsed - _lastTickTime < _targetFrameDuration) return;
    
    final deltaMs = _lastTickTime == Duration.zero 
        ? _targetFrameDuration.inMilliseconds 
        : (elapsed - _lastTickTime).inMilliseconds;
    _lastTickTime = elapsed;

    if (widget.dvdMode) {
      _updateBounceAnimation(deltaMs);
    } else {
      _updateStaticColorAnimation();
    }
  }

  void _updateBounceAnimation(int deltaMs) {
    if (_maxX <= 0.0 || _maxY <= 0.0) return;
    
    final deltaFactor = deltaMs / 16.67;
    double nx = _x + (_vx * deltaFactor);
    double ny = _y + (_vy * deltaFactor);
    bool bounced = false;

    if (nx <= 0.0 || nx >= _maxX) {
      _vx = -_vx;
      nx = nx.clamp(0.0, _maxX);
      bounced = true;
    }
    if (ny <= 0.0 || ny >= _maxY) {
      _vy = -_vy;
      ny = ny.clamp(0.0, _maxY);
      bounced = true;
    }

    if (bounced) {
      _fromColor = _colorAnim.value ?? _toColor;
      _colorIndex = (_colorIndex + 1) % _bounceColors.length;
      _toColor = _bounceColors[_colorIndex];
      _rebuildColorAnim();
      _colorCtrl.forward(from: 0.0);
    }

    _x = nx;
    _y = ny;

    setState(() {});
  }

  void _updateStaticColorAnimation() {
    _hue = (_hue + 0.5) % 360.0;
    setState(() {});
  }

  @override
  void dispose() {
    _ticker
      ..stop()
      ..dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _maxX = constraints.maxWidth - _logoSize;
      _maxY = constraints.maxHeight - _logoSize;

      if (!widget.dvdMode) {
        final centerX = (constraints.maxWidth - _logoSize) / 2;
        final centerY = (constraints.maxHeight - _logoSize) / 2;
        final rgbColor = HSVColor.fromAHSV(1.0, _hue, 0.7, 0.95).toColor();

        return Stack(children: [
          Positioned(
            left: centerX,
            top: centerY,
            child: RepaintBoundary(
              child: _BouncingLogo(size: _logoSize, color: rgbColor),
            ),
          ),
        ]);
      }

      return Stack(children: [
        Positioned(
          left: _x,
          top: _y,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _colorAnim,
              builder: (context, child) => _BouncingLogo(
                  size: _logoSize, color: _colorAnim.value ?? Colors.white),
            ),
          ),
        ),
      ]);
    });
  }
}

class _BouncingLogo extends StatelessWidget {
  final double size;
  final Color color;
  const _BouncingLogo({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size / 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          child: Image.asset(
            'assets/images/logo_transparent.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            cacheWidth: (size * MediaQuery.of(context).devicePixelRatio).round(),
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
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