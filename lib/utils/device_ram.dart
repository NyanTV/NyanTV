// lib/utils/device_ram.dart

enum BufferProfile {
  low,       // 32MB,  60s  — ≤2GB RAM
  medium,    // 64MB,  90s  — ≤3GB RAM  (DEFAULT)
  high,      // 96MB,  120s — 4GB RAM
  ultraHigh, // 128MB, 180s — 6GB+ RAM (flagship TV boxes)
}

class BufferConfig {
  final int bufferMB;
  final int cacheSecs;
  final int demuxerMaxMB;
  final int demuxerBackMB;

  /// Extra MPV options injected per profile
  final Map<String, String> extraMpvOptions;

  const BufferConfig({
    required this.bufferMB,
    required this.cacheSecs,
    required this.demuxerMaxMB,
    required this.demuxerBackMB,
    this.extraMpvOptions = const {},
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
    if (ramMB <= 5120) return BufferProfile.high;
    return BufferProfile.ultraHigh;
  }

  static BufferConfig getConfig(BufferProfile profile) {
    switch (profile) {
      case BufferProfile.low:
        return const BufferConfig(
          bufferMB: 32,
          cacheSecs: 60,
          demuxerMaxMB: 40,
          demuxerBackMB: 16,
          extraMpvOptions: {
            'cache-pause-wait': '5',
            'network-timeout': '30',
          },
        );
      case BufferProfile.medium:
        return const BufferConfig(
          bufferMB: 64,
          cacheSecs: 90,
          demuxerMaxMB: 75,
          demuxerBackMB: 28,
          extraMpvOptions: {
            'cache-pause-wait': '4',
            'network-timeout': '25',
          },
        );
      case BufferProfile.high:
        return const BufferConfig(
          bufferMB: 96,
          cacheSecs: 120,
          demuxerMaxMB: 110,
          demuxerBackMB: 40,
          extraMpvOptions: {
            'cache-pause-wait': '3',
            'network-timeout': '20',
          },
        );
      case BufferProfile.ultraHigh:
        return const BufferConfig(
          bufferMB: 128,
          cacheSecs: 180,
          demuxerMaxMB: 150,
          demuxerBackMB: 55,
          extraMpvOptions: {
            'cache-pause-wait': '2',
            'network-timeout': '15',
          },
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
        return 'High (4GB RAM)';
      case BufferProfile.ultraHigh:
        return 'Ultra High (6GB+ RAM)';
    }
  }

  static String getProfileDescription(BufferProfile profile) {
    switch (profile) {
      case BufferProfile.low:
        return 'Lower buffer for devices with limited RAM (32MB buffer, 60s cache)';
      case BufferProfile.medium:
        return 'Balanced performance for mid-range devices (64MB buffer, 90s cache)';
      case BufferProfile.high:
        return 'High buffer for capable devices (96MB buffer, 120s cache)';
      case BufferProfile.ultraHigh:
        return 'Maximum buffer for flagship TV boxes (128MB buffer, 180s cache)';
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