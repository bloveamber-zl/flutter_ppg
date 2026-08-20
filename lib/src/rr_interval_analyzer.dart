import 'dart:math' as math;
import 'models/ppg_config.dart';

/// Analyzes RR interval quality metrics and calculates heart rate statistics.
///
/// This class provides tools for analyzing sets of RR intervals (time between
/// consecutive heartbeats) to calculate heart rate, variability measures,
/// and quality indicators. It uses the Standard Deviation of RR intervals
/// (SDRR) as a key metric for assessing signal quality and heart rate variability.
///
/// Example usage:
/// ```dart
/// final analyzer = RRIntervalAnalyzer.fromConfig(config);
/// final result = analyzer.analyze(rrIntervals);
/// print('Heart rate: ${result.meanBPM} BPM');
/// print('Variability (SDRR): ${result.sdrr} ms');
/// ```
class RRIntervalAnalyzer {
  /// Maximum acceptable Standard Deviation of RR intervals (SDRR) in milliseconds.
  ///
  /// Used to determine if the heart rate variability is within acceptable
  /// range for reliable measurements. Higher values allow more variability.
  final double maxAcceptableSDRR;

  /// Creates an [RRIntervalAnalyzer] with the specified SDRR threshold.
  ///
  /// [maxAcceptableSDRR] - Maximum acceptable SDRR in milliseconds.
  /// Must be >= 0 (assertion will fail in debug mode if violated).
  const RRIntervalAnalyzer({required this.maxAcceptableSDRR}) : assert(maxAcceptableSDRR >= 0);

  /// Creates an [RRIntervalAnalyzer] from a [PPGConfig].
  ///
  /// Uses the `maxAcceptableSDRRMs` value from the configuration.
  factory RRIntervalAnalyzer.fromConfig(PPGConfig config) {
    return RRIntervalAnalyzer(maxAcceptableSDRR: config.maxAcceptableSDRRMs);
  }

  /// Calculates the Standard Deviation of RR intervals (SDRR) in milliseconds.
  ///
  /// SDRR is a measure of heart rate variability. Lower values indicate more
  /// regular heart rhythm, while higher values indicate greater variability.
  ///
  /// [rrIntervals] - List of RR intervals in milliseconds.
  /// Returns the SDRR in milliseconds, or 0.0 if fewer than 2 intervals are provided.
  double calculateSDRR(List<double> rrIntervals) {
    if (rrIntervals.length < 2) return 0.0;

    final mean = rrIntervals.reduce((a, b) => a + b) / rrIntervals.length;
    double sumSquaredDiff = 0.0;
    for (final rr in rrIntervals) {
      final diff = rr - mean;
      sumSquaredDiff += diff * diff;
    }
    final variance = sumSquaredDiff / rrIntervals.length;
    return math.sqrt(variance);
  }

  /// Calculates mean heart rate in beats per minute (BPM) from RR intervals.
  ///
  /// The calculation is: 60000 / meanRR, where meanRR is the average of all
  /// RR intervals in milliseconds.
  ///
  /// [rrIntervals] - List of RR intervals in milliseconds.
  /// Returns the mean heart rate in BPM, or 0.0 if the list is empty.
  double calculateMeanBPM(List<double> rrIntervals) {
    if (rrIntervals.isEmpty) return 0.0;
    final meanRR = rrIntervals.reduce((a, b) => a + b) / rrIntervals.length;
    return 60000.0 / meanRR;
  }

  /// Checks if the SDRR of the given RR intervals is within acceptable range.
  ///
  /// Uses the [maxAcceptableSDRR] threshold to determine acceptability.
  /// This is useful for quality assessment of heart rate measurements.
  ///
  /// [rrIntervals] - List of RR intervals in milliseconds.
  /// Returns true if the calculated SDRR is <= [maxAcceptableSDRR].
  bool isSDRRAcceptable(List<double> rrIntervals) {
    final sdrr = calculateSDRR(rrIntervals);
    return sdrr <= maxAcceptableSDRR;
  }

  /// Performs comprehensive analysis of RR intervals.
  ///
  /// Calculates mean heart rate (BPM), SDRR (Standard Deviation of RR intervals),
  /// and determines if the SDRR is within acceptable range. Returns a
  /// [RRAnalysisResult] containing all calculated metrics.
  ///
  /// [rrIntervals] - List of RR intervals in milliseconds.
  /// Returns [RRAnalysisResult] with all calculated metrics, or a zero-filled
  /// result if the input list is empty.
  RRAnalysisResult analyze(List<double> rrIntervals) {
    if (rrIntervals.isEmpty) {
      return const RRAnalysisResult(meanBPM: 0.0, sdrr: 0.0, isSDRRAcceptable: false, intervalCount: 0);
    }

    final sdrr = calculateSDRR(rrIntervals);
    return RRAnalysisResult(meanBPM: calculateMeanBPM(rrIntervals), sdrr: sdrr, isSDRRAcceptable: sdrr <= maxAcceptableSDRR, intervalCount: rrIntervals.length);
  }
}

/// Result of RR interval analysis.
///
/// Contains statistical metrics calculated from a set of RR intervals,
/// including heart rate, variability measures, and quality indicators.
class RRAnalysisResult {
  /// Mean heart rate in beats per minute (BPM).
  /// Calculated from the average RR interval.
  final double meanBPM;

  /// Standard Deviation of RR intervals (SDRR) in milliseconds.
  /// Measures heart rate variability. Lower values indicate more regular rhythm.
  final double sdrr;

  /// Whether the SDRR is within acceptable range for reliable measurements.
  /// Based on the configured `maxAcceptableSDRR` threshold.
  final bool isSDRRAcceptable;

  /// Number of RR intervals used in the analysis.
  final int intervalCount;

  /// Creates an [RRAnalysisResult] with the specified metrics.
  ///
  /// [meanBPM] - Mean heart rate in beats per minute.
  /// [sdrr] - Standard Deviation of RR intervals in milliseconds.
  /// [isSDRRAcceptable] - Whether SDRR is within acceptable range.
  /// [intervalCount] - Number of RR intervals used in the analysis.
  const RRAnalysisResult({required this.meanBPM, required this.sdrr, required this.isSDRRAcceptable, required this.intervalCount});
}
