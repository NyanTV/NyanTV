import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:nyantv/utils/subtitle_server.dart';
import 'package:nyantv/utils/subtitle_translator.dart';

class _Cue {
  final int startMs;
  final int endMs;
  final String original;
  String? translated;
  _Cue({required this.startMs, required this.endMs, required this.original});
}

class _InstancePool {
  final _available = <String>[];
  final _failed = <String, DateTime>{};
  bool _disposed = false;
  static const _cooldown = Duration(minutes: 2);

  _InstancePool() {
    _available.addAll(SubtitleTranslator.instances);
  }

  String? tryAcquire() {
    if (_disposed) return null;
    final now = DateTime.now();
    final healthy = _available.where((i) {
      final failedAt = _failed[i];
      return failedAt == null || now.difference(failedAt) > _cooldown;
    }).toList();

    if (healthy.isNotEmpty) {
      final i = healthy.last;
      _available.remove(i);
      return i;
    }
    return null;
  }

  void release(String instance, {bool failed = false}) {
    if (_disposed) return;
    if (failed) {
      _failed[instance] = DateTime.now();
    } else {
      _available.add(instance);
    }
  }

  void releaseAll() {
    if (_disposed) return;
    for (final i in SubtitleTranslator.instances) {
      if (!_available.contains(i)) _available.add(i);
    }
  }

  void dispose() {
    _disposed = true;
    _available.clear();
  }
}

class SmartSubtitleManager {
  final _server = SubtitleServer();
  final _cues = <_Cue>[];
  bool _disposed = false;
  String? _activeServerUrl;

  Future<void> start() => _server.start();

  Future<String> serveRaw(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200 || _disposed) return url;
      final content = response.body.replaceAllMapped(
        RegExp(r'(\d{2}:\d{2}\.\d{3}) --> (\d{2}:\d{2}\.\d{3})'),
        (m) => '00:${m[1]} --> 00:${m[2]}',
      );
      if (_activeServerUrl != null) _server.remove(_activeServerUrl!);
      _activeServerUrl = _server.serve(content);
      return _activeServerUrl!;
    } catch (_) {
      return url;
    }
  }

  Future<void> loadAndTranslate({
    required String url,
    required String targetLang,
    required Duration Function() getCurrentPosition,
    required bool Function() isCancelled,
    required void Function() onCueReady,
  }) async {
    _cues.clear();
    _disposed = false;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200 || _disposed) return;
      final content = response.body.replaceAllMapped(
        RegExp(r'(\d{2}:\d{2}\.\d{3}) --> (\d{2}:\d{2}\.\d{3})'),
        (m) => '00:${m[1]} --> 00:${m[2]}',
      );
      _parseCues(content);
      if (_cues.isEmpty || _disposed) return;

      for (final cue in _cues) {
        final cached = SubtitleTranslator.getCached(targetLang, cue.original);
        if (cached != null) cue.translated = cached;
      }
      onCueReady();

      unawaited(_translateProgressively(
        targetLang: targetLang,
        startMs: (getCurrentPosition().inMilliseconds - 1000).clamp(0, 1 << 30),
        isCancelled: isCancelled,
        onCueReady: onCueReady,
      ));
    } catch (_) {}
  }

  List<String> getSubtitleAt(Duration position) {
    if (_cues.isEmpty) return [''];
    final ms = position.inMilliseconds;
    final results = [
      for (final cue in _cues)
        if (ms >= cue.startMs && ms < cue.endMs) cue.translated ?? cue.original,
    ];
    return results.isEmpty ? [''] : results;
  }

  void dispose() {
    _disposed = true;
    _cues.clear();
    if (_activeServerUrl != null) _server.remove(_activeServerUrl!);
    _server.dispose();
  }

  void _parseCues(String vtt) {
    for (final block in vtt.split(RegExp(r'\r?\n\r?\n'))) {
      final lines = block.trim().split(RegExp(r'\r?\n'));
      final tsIdx = lines.indexWhere((l) => l.contains('-->'));
      if (tsIdx == -1 || tsIdx + 1 >= lines.length) continue;
      final tsParts = lines[tsIdx].split('-->');
      final text = lines.sublist(tsIdx + 1).join('\n').trim();
      if (text.isEmpty) continue;
      _cues.add(_Cue(
        startMs: _parseMs(tsParts[0].trim()),
        endMs: _parseMs(tsParts[1].trim()),
        original: text,
      ));
    }
  }

  static int _parseMs(String ts) {
    try {
      final clean = ts.replaceAll(',', '.').split(' ').first;
      final parts = clean.split(':');
      if (parts.length == 3) {
        return ((int.parse(parts[0]) * 3600 +
                    int.parse(parts[1]) * 60 +
                    double.parse(parts[2])) *
                1000)
            .toInt();
      } else if (parts.length == 2) {
        return ((int.parse(parts[0]) * 60 + double.parse(parts[1])) * 1000)
            .toInt();
      }
    } catch (_) {}
    return 0;
  }

  Future<void> _translateProgressively({
    required String targetLang,
    required int startMs,
    required bool Function() isCancelled,
    required void Function() onCueReady,
  }) async {
    final pool = _InstancePool();
    const chunkSize = 10;

    final upcoming = <int>[];
    final past = <int>[];
    for (int i = 0; i < _cues.length; i++) {
      if (_cues[i].translated != null) continue;
      (_cues[i].endMs >= startMs ? upcoming : past).add(i);
    }

    for (int i = 0; i < upcoming.length; i += chunkSize) {
      if (_disposed || isCancelled()) {
        pool.dispose();
        return;
      }
      await _translateChunk(
        upcoming.sublist(i, (i + chunkSize).clamp(0, upcoming.length)),
        targetLang,
        pool,
        isCancelled,
        onCueReady,
      );
    }

    if (_disposed || isCancelled()) {
      pool.dispose();
      return;
    }

    for (int i = 0; i < past.length; i += chunkSize) {
      if (_disposed || isCancelled()) {
        pool.dispose();
        return;
      }
      await _translateChunk(
        past.sublist(i, (i + chunkSize).clamp(0, past.length)),
        targetLang,
        pool,
        isCancelled,
        onCueReady,
      );
    }

    pool.dispose();
  }

  Future<void> _translateChunk(
    List<int> indices,
    String targetLang,
    _InstancePool pool,
    bool Function() isCancelled,
    void Function() onCueReady,
  ) async {
    if (_disposed || isCancelled()) return;

    final toTranslate = <int>[];
    for (final i in indices) {
      final cached =
          SubtitleTranslator.getCached(targetLang, _cues[i].original);
      if (cached != null) {
        _cues[i].translated = cached;
      } else {
        toTranslate.add(i);
      }
    }
    if (toTranslate.isEmpty) {
      onCueReady();
      return;
    }

    for (final i in toTranslate) {
      if (_disposed || isCancelled()) return;

      final tried = <String>{};
      bool success = false;

      while (tried.length < SubtitleTranslator.instances.length) {
        final instance = pool.tryAcquire();
        if (instance == null) {
          await Future.delayed(const Duration(milliseconds: 500));
          pool.releaseAll();
          continue;
        }
        if (tried.contains(instance)) {
          pool.release(instance);
          break;
        }
        tried.add(instance);

        try {
          final result = await SubtitleTranslator.translateWithInstance(
              _cues[i].original, targetLang, instance);
          if (result != null) {
            _cues[i].translated = result;
            pool.release(instance);
            success = true;
            break;
          } else {
            pool.release(instance, failed: true);
          }
        } catch (_) {
          pool.release(instance, failed: true);
        }
      }

      if (!success) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    onCueReady();
  }
}
