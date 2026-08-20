/// Detects the actual frame rate from camera frame timestamps.
///
/// This class automatically detects the camera's frame rate by analyzing
/// the intervals between consecutive frames. It uses a rolling window of
/// frame intervals and calculates the median to determine the actual FPS,
/// which is then snapped to common frame rates (24, 25, 30, 60 FPS).
///
/// The detector requires a warmup period (default: 30 frames) before
/// considering the detection stable. This helps avoid false readings during
/// camera initialization.
///
/// Example usage:
/// ```dart
/// final detector = FrameRateDetector();
/// for (final image in cameraStream) {
///   detector.recordFrameMicros(Stopwatch().elapsedMicroseconds);
///   if (detector.isStable) {
///     print('Detected FPS: ${detector.fps}');
///   }
/// }
/// ```
class FrameRateDetector {
  /// Creates a new [FrameRateDetector] instance.
  ///
  /// The detector starts with a default frame rate of 30 FPS and requires
  /// a warmup period before detection is considered stable.
  FrameRateDetector();

  static const int _warmupFrames = 30;
  static const double _defaultFPS = 30.0;
  static const double _minStableFPS = 20.0;
  static const int _lowFpsStreakToUnstable = 3;

  final List<double> _frameIntervalsMs = [];
  int? _lastFrameMicros;
  double _detectedFPS = _defaultFPS;
  bool _isStable = false;
  int _lowFpsStreak = 0;

  /// Returns the currently detected frame rate.
  double get fps => _detectedFPS;

  /// Returns true if detection has stabilized.
  bool get isStable => _isStable;

  /// Records a new frame and updates FPS detection.
  ///
  /// Call this for every camera frame received.
  /// Records a new frame using a timestamp in microseconds.
  ///
  /// Prefer a monotonic time source (e.g., Stopwatch) to avoid clock jumps.
  void recordFrameMicros(int timestampMicros) {
    if (_lastFrameMicros != null) {
      final intervalMs = (timestampMicros - _lastFrameMicros!) / 1000.0;

      // Ignore extreme outliers (< 5ms or > 200ms)
      if (intervalMs >= 5.0 && intervalMs <= 200.0) {
        _frameIntervalsMs.add(intervalMs);

        // Keep a rolling window (2x warmup)
        if (_frameIntervalsMs.length > _warmupFrames * 2) {
          _frameIntervalsMs.removeAt(0);
        }

        if (_frameIntervalsMs.length >= _warmupFrames) {
          _updateFPS();
        }
      }
    }

    _lastFrameMicros = timestampMicros;
  }

  /// Records a new frame using a DateTime timestamp.
  ///
  /// This is less stable than a monotonic clock, but kept for convenience.
  void recordFrame(DateTime timestamp) {
    recordFrameMicros(timestamp.microsecondsSinceEpoch);
  }

  void _updateFPS() {
    if (_frameIntervalsMs.isEmpty) return;

    final sorted = List<double>.from(_frameIntervalsMs)..sort();
    final medianInterval = sorted[sorted.length ~/ 2];

    final rawFPS = 1000.0 / medianInterval;
    _detectedFPS = _snapToCommonFPS(rawFPS);

    if (_detectedFPS < _minStableFPS) {
      _lowFpsStreak++;
    } else {
      _lowFpsStreak = 0;
    }

    _isStable = _frameIntervalsMs.length >= _warmupFrames && _lowFpsStreak < _lowFpsStreakToUnstable;
  }

  double _snapToCommonFPS(double rawFPS) {
    const commonRates = [24.0, 25.0, 30.0, 60.0];
    const tolerance = 2.0;

    for (final rate in commonRates) {
      if ((rawFPS - rate).abs() <= tolerance) {
        return rate;
      }
    }
    return rawFPS;
  }

  /// Resets the detector state.
  void reset() {
    _frameIntervalsMs.clear();
    _lastFrameMicros = null;
    _detectedFPS = _defaultFPS;
    _isStable = false;
    _lowFpsStreak = 0;
  }
}
