/// A detected heartbeat whose RR interval remains paired with its peak time.
class PPGBeatEvent {
  /// Monotonic peak time in microseconds since processing started.
  final double peakTimeMicros;

  /// Wall-clock estimate of [peakTimeMicros] for app integration.
  final DateTime peakTimestamp;

  /// Time since the preceding detected peak, in milliseconds.
  final double rrIntervalMs;

  /// Index of the peak in the current filtered signal window.
  final int peakIndex;

  /// Fractional offset from [peakIndex], constrained to adjacent samples.
  final double subSampleOffset;

  const PPGBeatEvent({
    required this.peakTimeMicros,
    required this.peakTimestamp,
    required this.rrIntervalMs,
    required this.peakIndex,
    this.subSampleOffset = 0.0,
  });
}
