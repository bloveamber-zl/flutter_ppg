import 'ppg_beat_event.dart';

/// Signal quality assessment levels for PPG signals.
enum SignalQuality {
  /// Poor quality signal - insufficient for reliable heart rate detection.
  /// Typically indicates low SNR, excessive noise, or unstable signal.
  poor,

  /// Fair quality signal - usable but may have some noise or artifacts.
  /// Heart rate detection is possible but may be less accurate.
  fair,

  /// Good quality signal - high SNR and stable, suitable for accurate
  /// heart rate and RR interval detection.
  good,
}

/// Photoplethysmography (PPG) signal data extracted from camera frames.
///
/// This class represents a single processed PPG signal sample containing
/// raw and filtered intensity values, detected RR intervals, quality metrics,
/// and various diagnostic information for heart rate analysis.
class PPGSignal {
  /// Raw intensity value extracted from the camera frame (typically red channel).
  /// This is the unprocessed signal before filtering.
  final double rawIntensity;

  /// Filtered intensity value after bandpass filtering.
  /// This signal is used for peak detection and RR interval calculation.
  final double filteredIntensity;

  /// List of RR intervals in milliseconds detected from the signal.
  /// Each value represents the time between consecutive heartbeats.
  /// Empty if insufficient peaks are detected or signal quality is poor.
  final List<double> rrIntervals;

  /// RR intervals paired with their interpolated monotonic peak timestamps.
  final List<PPGBeatEvent> beatEvents;

  /// Overall signal quality assessment.
  final SignalQuality quality;

  /// Timestamp when this signal was processed.
  final DateTime timestamp;

  /// Indices of detected peaks in the current filtered window.
  /// Used for visualization of peak detection algorithm.
  final List<int> peakIndices;

  /// Signal-to-Noise Ratio in dB.
  final double snr;

  /// Detected frame rate used for RR calculations.
  final double frameRate;

  /// Whether frame rate detection has stabilized.
  final bool isFPSStable;

  /// Baseline drift rate in intensity units per second.
  final double driftRate;

  /// Standard deviation of RR intervals (SDRR) in milliseconds.
  final double sdrr;

  /// Whether SDRR is within acceptable range.
  /// The threshold is determined by [PPGConfig.maxAcceptableSDRRMs] (default: 150ms).
  final bool isSDRRAcceptable;

  /// Ratio of RR intervals rejected during filtering (0.0-1.0).
  final double rejectionRatio;

  /// Number of RR intervals rejected during filtering.
  final int rejectedIntervalCount;

  /// Creates a [PPGSignal] instance with the specified values.
  ///
  /// [rawIntensity] - Raw intensity value from camera frame (required).
  /// [filteredIntensity] - Filtered intensity value after bandpass filtering (required).
  /// [rrIntervals] - List of detected RR intervals in milliseconds (required).
  /// [quality] - Signal quality assessment (required).
  /// [timestamp] - Timestamp when signal was processed (required).
  /// [peakIndices] - Indices of detected peaks in filtered window. Defaults to empty list.
  /// [snr] - Signal-to-Noise Ratio in dB. Defaults to 0.0.
  /// [frameRate] - Detected frame rate in FPS. Defaults to 30.0.
  /// [isFPSStable] - Whether frame rate detection has stabilized. Defaults to false.
  /// [driftRate] - Baseline drift rate in intensity units per second. Defaults to 0.0.
  /// [sdrr] - Standard deviation of RR intervals in milliseconds. Defaults to 0.0.
  /// [isSDRRAcceptable] - Whether SDRR is within acceptable range. Defaults to true.
  /// [rejectionRatio] - Ratio of rejected RR intervals (0.0-1.0). Defaults to 0.0.
  /// [rejectedIntervalCount] - Number of rejected RR intervals. Defaults to 0.
  PPGSignal({
    required this.rawIntensity,
    required this.filteredIntensity,
    required this.rrIntervals,
    required this.quality,
    required this.timestamp,
    this.beatEvents = const [],
    this.peakIndices = const [],
    this.snr = 0.0,
    this.frameRate = 30.0,
    this.isFPSStable = false,
    this.driftRate = 0.0,
    this.sdrr = 0.0,
    this.isSDRRAcceptable = true,
    this.rejectionRatio = 0.0,
    this.rejectedIntervalCount = 0,
  });
}
