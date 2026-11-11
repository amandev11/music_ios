/// Rolling estimate of how fast songs download, used by the "Auto" audio quality: a slow connection gets a
/// smaller stream so the song starts quickly, a fast one gets the best.
class NetworkQuality {
  static double _bytesPerSecond = 0;
  static int _samples = 0;

  /// Records one finished download. Tiny files are ignored (they measure latency, not bandwidth).
  static void record(int bytes, Duration took) {
    if (bytes < 200 * 1024 || took.inMilliseconds <= 0) return;
    final rate = bytes * 1000 / took.inMilliseconds;
    _bytesPerSecond = _samples == 0 ? rate : _bytesPerSecond * 0.6 + rate * 0.4;
    _samples++;
  }

  /// Measured speed in bytes per second (0 until the first download).
  static double get speed => _bytesPerSecond;

  /// 0 low, 1 medium, 2 high. Assumes a ~4 MB song: under 300 KB/s that takes 13 s+, so go smaller.
  static int get recommended {
    if (_samples == 0) return 2;
    if (_bytesPerSecond < 300 * 1024) return 0;
    if (_bytesPerSecond < 1024 * 1024) return 1;
    return 2;
  }

  static String get describe {
    if (_samples == 0) return 'not measured yet';
    final mb = _bytesPerSecond / (1024 * 1024);
    return mb >= 1 ? '${mb.toStringAsFixed(1)} MB/s' : '${(_bytesPerSecond / 1024).round()} KB/s';
  }
}
