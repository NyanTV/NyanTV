import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

enum PlayerType { betterPlayer, libmpv }

class PlayerConfiguration {
  final PlayerType playerType;
  final bool autoPlay;
  final bool useBuffering;
  final int bufferSize;
  final bool useLibass;
  final Map<String, String> options;

  const PlayerConfiguration({
    this.playerType = PlayerType.libmpv,
    this.autoPlay = true,
    this.useBuffering = true,
    this.bufferSize = 32 * 1024 * 1024,
    this.useLibass = false,
    this.options = const {},
  });
}

class AudioTrack {
  final String id;
  final String? url;
  final String? title;
  final String? language;

  const AudioTrack({required this.id, this.url, this.title, this.language});

  factory AudioTrack.auto() => const AudioTrack(id: 'auto', title: 'Auto');
  factory AudioTrack.no() => const AudioTrack(id: 'no', title: 'None');
}

class SubtitleTrack {
  final String id;
  final String? url;
  final String? title;
  final String? language;

  const SubtitleTrack({required this.id, this.url, this.title, this.language});

  factory SubtitleTrack.no() => const SubtitleTrack(id: 'no', title: 'None');
}

class VideoTrack {
  final String id;
  final String? title;

  const VideoTrack({required this.id, this.title});

  factory VideoTrack.auto() => const VideoTrack(id: 'auto', title: 'Auto');
}

class PlayerTracks {
  final List<AudioTrack> audio;
  final List<SubtitleTrack> subtitle;
  final List<VideoTrack> video;

  const PlayerTracks({
    this.audio = const [],
    this.subtitle = const [],
    this.video = const [],
  });
}

class PlayerState {
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final int? videoHeight;
  final double rate;
  final double volume;

  const PlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffer = Duration.zero,
    this.videoHeight,
    this.rate = 1.0,
    this.volume = 1.0,
  });

  PlayerState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    Duration? buffer,
    int? videoHeight,
    double? rate,
    double? volume,
  }) =>
      PlayerState(
        isPlaying: isPlaying ?? this.isPlaying,
        isBuffering: isBuffering ?? this.isBuffering,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        buffer: buffer ?? this.buffer,
        videoHeight: videoHeight ?? this.videoHeight,
        rate: rate ?? this.rate,
        volume: volume ?? this.volume,
      );
}

abstract class BasePlayer {
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<Duration> get bufferStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<PlayerTracks> get tracksStream;
  Stream<double> get rateStream;
  Stream<String> get errorStream;
  Stream<List<String>> get subtitleStream;
  Stream<int?> get heightStream;
  Stream<bool> get completedStream;

  PlayerState get state;

  Future<void> initialize();
  Future<void> open(String url,
      {Map<String, String>? headers, Duration? startPosition});
  Future<void> seek(Duration position);
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> setVideoTrack(VideoTrack track);
  Future<void> setAudioTrack(AudioTrack track);
  Future<void> setSubtitleTrack(SubtitleTrack track);
  Future<Uint8List?> screenshot(
      {bool includeSubtitles = true, String format = 'image/png'});
  Future<void> setHardwareDecoding(String mode);
  Widget getVideoWidget({BoxFit? fit, double? width, double? height});
  Future<void> dispose();
  Future<void> toggleVideoFit(BoxFit fit);
}
