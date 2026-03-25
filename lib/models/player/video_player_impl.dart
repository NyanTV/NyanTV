import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'base_player.dart';

class _Sub {
  final Duration start, end;
  final List<String> lines;
  const _Sub(this.start, this.end, this.lines);
}

class BetterPlayerImpl extends BasePlayer {
  VideoPlayerController? _controller;
  final PlayerConfiguration config;

  final _pos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration>.broadcast();
  final _buf = StreamController<Duration>.broadcast();
  final _play = StreamController<bool>.broadcast();
  final _buff = StreamController<bool>.broadcast();
  final _trk = StreamController<PlayerTracks>.broadcast();
  final _rate = StreamController<double>.broadcast();
  final _err = StreamController<String>.broadcast();
  final _sub = StreamController<List<String>>.broadcast();
  final _h = StreamController<int?>.broadcast();
  final _done = StreamController<bool>.broadcast();

  PlayerState _state = const PlayerState();
  bool _disposed = false, _completed = false;
  Timer? _timer;
  double _currentRate = 1.0;
  List<_Sub> _subs = [];
  List<String> _lastSubLines = const [];

  BetterPlayerImpl({PlayerConfiguration? configuration})
      : config = configuration ??
            const PlayerConfiguration(playerType: PlayerType.betterPlayer);

  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<Duration> get durationStream => _dur.stream;
  @override
  Stream<Duration> get bufferStream => _buf.stream;
  @override
  Stream<bool> get playingStream => _play.stream;
  @override
  Stream<bool> get bufferingStream => _buff.stream;
  @override
  Stream<PlayerTracks> get tracksStream => _trk.stream;
  @override
  Stream<double> get rateStream => _rate.stream;
  @override
  Stream<String> get errorStream => _err.stream;
  @override
  Stream<List<String>> get subtitleStream => _sub.stream;
  @override
  Stream<int?> get heightStream => _h.stream;
  @override
  Stream<bool> get completedStream => _done.stream;
  @override
  PlayerState get state => _state;

  @override
  Future<void> initialize() async => WakelockPlus.enable();

  @override
  Future<void> open(String url,
      {Map<String, String>? headers, Duration? startPosition}) async {
    _completed = false;
    _subs = [];
    _lastSubLines = const [];
    await _kill();

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: headers ?? {},
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller!.addListener(_onChange);
    await _controller!.initialize();

    final d = _controller!.value.duration;
    _state = _state.copyWith(duration: d, isBuffering: false);
    _dur.add(d);

    final sz = _controller!.value.size;
    if (sz.height > 0) {
      _h.add(sz.height.toInt());
    }

    _trk.add(PlayerTracks(
      audio: [AudioTrack.auto()],
      subtitle: [SubtitleTrack.no()],
      video: [VideoTrack.auto()],
    ));

    if (startPosition != null && startPosition.inMilliseconds > 0) {
      await _controller!.seekTo(startPosition);
    }
    await _controller!.setPlaybackSpeed(_currentRate);
    await _controller!.play();

    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_disposed) return;
      final p = _controller?.value.position;
      if (p != null && p != _state.position) {
        _state = _state.copyWith(position: p);
        _pos.add(p);
        _tickSubs(p);
      }
    });
  }

  void _onChange() {
    final v = _controller?.value;
    if (v == null || _disposed) return;

    if (v.isPlaying != _state.isPlaying) {
      _state = _state.copyWith(isPlaying: v.isPlaying);
      _play.add(v.isPlaying);
    }
    if (v.isBuffering != _state.isBuffering) {
      _state = _state.copyWith(isBuffering: v.isBuffering);
      _buff.add(v.isBuffering);
    }
    if (v.buffered.isNotEmpty) {
      final b = v.buffered.last.end;
      if (b != _state.buffer) {
        _state = _state.copyWith(buffer: b);
        _buf.add(b);
      }
    }
    if (!_completed &&
        v.duration.inMilliseconds > 0 &&
        v.position >= v.duration) {
      _completed = true;
      _done.add(true);
    }
  }

  void _tickSubs(Duration pos) {
    if (_subs.isEmpty) {
      if (_lastSubLines.isNotEmpty) {
        _lastSubLines = const [];
        _sub.add(const []);
      }
      return;
    }
    final cur = _subs
        .where((e) => pos >= e.start && pos < e.end)
        .expand((e) => e.lines)
        .toList();
    if (cur.join() != _lastSubLines.join()) {
      _lastSubLines = cur;
      _sub.add(cur);
    }
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    _subs = [];
    _lastSubLines = const [];
    _sub.add(const []);
    if (track.id == 'no' || (track.url ?? '').isEmpty) return;
    try {
      final uri = Uri.parse(track.url!);
      final res = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': uri.origin,
      });
      if (res.statusCode == 200) {
        _subs = _parse(utf8.decode(res.bodyBytes));
      }
    } catch (e) {
      debugPrint('Subtitle load error: $e');
    }
  }

  List<_Sub> _parse(String raw) {
    final s = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return s.contains('[Events]') ? _parseAss(s) : _parseSrtVtt(s);
  }

  List<_Sub> _parseSrtVtt(String s) {
    final out = <_Sub>[];
    final lines = s.split('\n');
    int i = 0;
    while (i < lines.length) {
      final l = lines[i].trim();
      if (l.contains('-->')) {
        final t = _ts(l);
        if (t != null) {
          i++;
          final txt = <String>[];
          while (i < lines.length && lines[i].trim().isNotEmpty) {
            final x = lines[i].trim().replaceAll(RegExp(r'<[^>]+>'), '');
            if (x.isNotEmpty) txt.add(x);
            i++;
          }
          if (txt.isNotEmpty) out.add(_Sub(t.$1, t.$2, txt));
          continue;
        }
      }
      i++;
    }
    return out;
  }

  List<_Sub> _parseAss(String s) {
    final out = <_Sub>[];
    bool inEvents = false;
    List<String> fmt = [];
    for (final raw in s.split('\n')) {
      final l = raw.trim();
      if (l == '[Events]') {
        inEvents = true;
        continue;
      }
      if (l.startsWith('[') && l != '[Events]') {
        inEvents = false;
        continue;
      }
      if (!inEvents) continue;
      if (l.startsWith('Format:')) {
        fmt = l.substring(7).split(',').map((e) => e.trim()).toList();
        continue;
      }
      if (!l.startsWith('Dialogue:') || fmt.isEmpty) continue;
      final v = l.substring(9).split(',');
      final si = fmt.indexOf('Start'),
          ei = fmt.indexOf('End'),
          ti = fmt.indexOf('Text');
      if (si < 0 || ei < 0 || ti < 0 || v.length <= ti) continue;
      final text = v
          .sublist(ti)
          .join(',')
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .replaceAll(r'\N', '\n')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\h', ' ')
          .trim();
      final st = _assD(v[si].trim()), en = _assD(v[ei].trim());
      if (st == null || en == null || text.isEmpty) continue;
      out.add(
          _Sub(st, en, text.split('\n').where((x) => x.isNotEmpty).toList()));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  (Duration, Duration)? _ts(String l) {
    final m = RegExp(r'([\d:]+[.,]\d+)\s*-->\s*([\d:]+[.,]\d+)').firstMatch(l);
    if (m == null) return null;
    final s = _srtD(m.group(1)!), e = _srtD(m.group(2)!);
    return (s == null || e == null) ? null : (s, e);
  }

  Duration? _srtD(String s) {
    try {
      s = s.replaceAll(',', '.');
      final p = s.split(':');
      if (p.length == 3) {
        final sp = p[2].split('.');
        return Duration(
            hours: int.parse(p[0]),
            minutes: int.parse(p[1]),
            seconds: int.parse(sp[0]),
            milliseconds: int.parse(sp[1].padRight(3, '0').substring(0, 3)));
      }
    } catch (_) {}
    return null;
  }

  Duration? _assD(String s) {
    // h:mm:ss.cs
    try {
      final p = s.split(':');
      if (p.length != 3) return null;
      final sp = p[2].split('.');
      return Duration(
          hours: int.parse(p[0]),
          minutes: int.parse(p[1]),
          seconds: int.parse(sp[0]),
          milliseconds: int.parse(sp[1].padRight(2, '0').substring(0, 2)) * 10);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> seek(Duration p) async => _controller?.seekTo(p);
  @override
  Future<void> play() async => _controller?.play();
  @override
  Future<void> pause() async => _controller?.pause();
  @override
  Future<void> playOrPause() async =>
      (_controller?.value.isPlaying ?? false) ? pause() : play();

  @override
  Future<void> setRate(double r) async {
    _currentRate = r;
    await _controller?.setPlaybackSpeed(r);
    _state = _state.copyWith(rate: r);
    _rate.add(r);
  }

  @override
  Future<void> setVolume(double v) async => _controller?.setVolume(v);
  @override
  Future<void> setAudioTrack(AudioTrack t) async {}
  @override
  Future<void> setVideoTrack(VideoTrack t) async {}
  @override
  Future<void> setHardwareDecoding(String m) async {}
  @override
  Future<void> toggleVideoFit(BoxFit f) async {}
  @override
  Future<Uint8List?> screenshot(
          {bool includeSubtitles = true, String format = 'image/png'}) async =>
      null;

  @override
  Widget getVideoWidget({BoxFit? fit, double? width, double? height}) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: fit ?? BoxFit.contain,
        child: SizedBox(
          width: c.value.size.width,
          height: c.value.size.height,
          child: VideoPlayer(c),
        ),
      ),
    );
  }

  Future<void> _kill() async {
    _timer?.cancel();
    _controller?.removeListener(_onChange);
    await _controller?.dispose();
    _controller = null;
  }

  @override
  Future<void> dispose() async {
    WakelockPlus.disable();
    _disposed = true;
    await _kill();
    await Future.wait([
      _pos,
      _dur,
      _buf,
      _play,
      _buff,
      _trk,
      _rate,
      _err,
      _sub,
      _h,
      _done
    ].map((c) => c.close()));
  }
}
