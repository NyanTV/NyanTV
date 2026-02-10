// lib/utils/device_ram.dart
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

enum BufferProfile {
  low,    // 32MB, 60s
  medium, // 48MB, 90s (DEFAULT)
  high,   // 64MB, 120s
}

class BufferConfig {
  final int bufferMB;
  final int cacheSecs;
  final int demuxerMaxMB;
  final int demuxerBackMB;

  const BufferConfig({
    required this.bufferMB,
    required this.cacheSecs,
    required this.demuxerMaxMB,
    required this.demuxerBackMB,
  });

  int get bufferBytes => bufferMB * 1024 * 1024;
  String get demuxerMax => '${demuxerMaxMB}M';
  String get demuxerBack => '${demuxerBackMB}M';
}

class DeviceRamHelper {
  static int? _cachedRamMB;

  static int getDeviceRamMB() {
    if (_cachedRamMB != null) return _cachedRamMB!;
    
    try {
      _cachedRamMB = 4096;
      return _cachedRamMB!;
    } catch (e) {
      _cachedRamMB = 2048;
      return _cachedRamMB!;
    }
  }

  static BufferProfile getRecommendedProfile() {
    final ramMB = getDeviceRamMB();
    
    if (ramMB <= 2048) return BufferProfile.low;
    if (ramMB <= 3072) return BufferProfile.medium;
    return BufferProfile.high;
  }

  static BufferConfig getConfig(BufferProfile profile) {
    switch (profile) {
      case BufferProfile.low:
        return const BufferConfig(
          bufferMB: 32,
          cacheSecs: 60,
          demuxerMaxMB: 50,
          demuxerBackMB: 20,
        );
      case BufferProfile.medium:
        return const BufferConfig(
          bufferMB: 48,
          cacheSecs: 90,
          demuxerMaxMB: 65,
          demuxerBackMB: 25,
        );
      case BufferProfile.high:
        return const BufferConfig(
          bufferMB: 64,
          cacheSecs: 120,
          demuxerMaxMB: 75,
          demuxerBackMB: 30,
        );
    }
  }

  static String getProfileName(BufferProfile profile) {
    switch (profile) {
      case BufferProfile.low:
        return 'Low (≤2GB RAM)';
      case BufferProfile.medium:
        return 'Medium (≤3GB RAM)';
      case BufferProfile.high:
        return 'High (4GB+ RAM)';
    }
  }

  static String getProfileDescription(BufferProfile profile) {
    switch (profile) {
      case BufferProfile.low:
        return 'Lower buffer for devices with limited RAM (32MB buffer, 60s cache)';
      case BufferProfile.medium:
        return 'Balanced performance for mid-range devices (48MB buffer, 90s cache)';
      case BufferProfile.high:
        return 'Maximum buffer for high-end devices (64MB buffer, 120s cache)';
    }
  }

  static String profileToString(BufferProfile profile) {
    return profile.toString().split('.').last;
  }

  static BufferProfile stringToProfile(String value) {
    return BufferProfile.values.firstWhere(
      (profile) => profile.toString().split('.').last == value,
      orElse: () => BufferProfile.medium,
    );
  }
}