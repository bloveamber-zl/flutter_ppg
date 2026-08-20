import 'dart:math' as math;
import 'package:flutter_ppg/src/models/ppg_signal.dart';
import 'models/ppg_config.dart';

/// Assesses the quality of the PPG signal.
class SignalQualityAssessor {
  final double fingerPresenceMin;
  final double fingerPresenceMax;
  final double minGoodSNR;
  final double minFairSNR;
  final double maxDriftRate;

  /// Creates a [SignalQualityAssessor] with the specified thresholds.
  ///
  /// The following constraints must be satisfied (assertions will fail in debug mode):
  /// - [fingerPresenceMax] must be > [fingerPresenceMin]
  /// - [minGoodSNR] must be > [minFairSNR]
  /// - [maxDriftRate] must be >= 0
  const SignalQualityAssessor({
    required this.fingerPresenceMin,
    required this.fingerPresenceMax,
    required this.minGoodSNR,
    required this.minFairSNR,
    required this.maxDriftRate,
  }) : assert(fingerPresenceMax > fingerPresenceMin),
       assert(minGoodSNR > minFairSNR),
       assert(maxDriftRate >= 0);

  factory SignalQualityAssessor.fromConfig(PPGConfig config) {
    return SignalQualityAssessor(
      fingerPresenceMin: config.fingerPresenceMin,
      fingerPresenceMax: config.fingerPresenceMax,
      minGoodSNR: config.minGoodSNR,
      minFairSNR: config.minFairSNR,
      maxDriftRate: config.maxDriftRate,
    );
  }

  /// Checks if the finger is placed on the camera based on raw intensity.
  ///
  /// Heuristic:
  /// - Too dark (< 30): Finger removed or camera covered improperly.
  /// - Too bright (> 250): Flashlight causing saturation/blooming.
  /// - Good range: approx 60 - 240.
  bool isFingerPresent(double rawIntensity) {
    return rawIntensity > fingerPresenceMin && rawIntensity < fingerPresenceMax;
  }

  /// Calculates Signal-to-Noise Ratio (SNR) in decibels (dB).
  ///
  /// [signal]: Recent signal window (e.g., last 1-2 seconds).
  double calculateSNR(List<double> signal) {
    if (signal.length < 2) return 0.0;

    // Signal Power = Variance of the signal
    final signalVariance = _calculateVariance(signal);
    if (signalVariance == 0) return 0.0; // Flatline

    // Noise Power = Variance of the first derivative (diff)
    // This assumes noise is high-frequency jitter.
    final diffs = <double>[];
    for (int i = 1; i < signal.length; i++) {
      diffs.add(signal[i] - signal[i - 1]);
    }
    final noiseVariance = _calculateVariance(diffs);

    if (noiseVariance == 0) return 100.0; // Perfect signal (no jitter)

    return 10 * math.log(signalVariance / noiseVariance) / math.ln10;
  }

  /// Determines overall signal quality.
  ///
  /// If [frameRate] is provided, the minimum window size is derived from it
  /// (roughly 1 second of data). Otherwise, defaults to 30 samples.
  SignalQuality assessQuality(List<double> recentSignals, {double? frameRate}) {
    if (recentSignals.isEmpty) return SignalQuality.poor;

    // 1. Check Intensity Saturation on the *latest* sample
    final last = recentSignals.last;
    if (!isFingerPresent(last)) {
      return SignalQuality.poor;
    }

    // 2. Check SNR (requires window)
    final minSamples = frameRate != null ? frameRate.round() : 30;
    if (recentSignals.length < minSamples) {
      // Not enough data for robust stats
      return SignalQuality.fair;
    }

    final snr = calculateSNR(recentSignals);

    // Thresholds need tuning.
    // > 0 dB: Signal power > Noise power.
    // Typical good PPG might be 5-10 dB?
    if (snr > minGoodSNR) return SignalQuality.good;
    if (snr > minFairSNR) return SignalQuality.fair;
    return SignalQuality.poor;
  }

  /// Calculates the baseline drift rate (intensity units per second).
  ///
  /// Uses linear regression slope on the recent signal window.
  double calculateDriftRate(List<double> signal, double frameRate) {
    if (signal.length < 10) return 0.0;

    final n = signal.length;
    double sumX = 0.0;
    double sumY = 0.0;
    double sumXY = 0.0;
    double sumX2 = 0.0;

    for (int i = 0; i < n; i++) {
      final x = i.toDouble();
      final y = signal[i];
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }

    final denominator = (n * sumX2 - sumX * sumX);
    if (denominator == 0.0) return 0.0;

    final slope = (n * sumXY - sumX * sumY) / denominator;

    // Convert from units/frame to units/second
    return slope * frameRate;
  }

  /// Enhanced quality assessment including drift detection.
  SignalQuality assessQualityWithDrift(List<double> recentSignals, double frameRate) {
    final basicQuality = assessQuality(recentSignals, frameRate: frameRate);
    if (basicQuality == SignalQuality.poor) {
      return SignalQuality.poor;
    }

    final driftRate = calculateDriftRate(recentSignals, frameRate).abs();
    if (driftRate > maxDriftRate) {
      return basicQuality == SignalQuality.good ? SignalQuality.fair : SignalQuality.poor;
    }

    return basicQuality;
  }

  double _calculateVariance(List<double> data) {
    if (data.isEmpty) return 0.0;
    final mean = data.reduce((a, b) => a + b) / data.length;
    double sumSquaredDiff = 0.0;
    for (final x in data) {
      final diff = x - mean;
      sumSquaredDiff += diff * diff;
    }
    return sumSquaredDiff / data.length;
  }
}
