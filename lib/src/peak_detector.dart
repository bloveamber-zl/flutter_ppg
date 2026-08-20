import 'dart:math' as math;

/// Detects peaks in a PPG signal for RR interval calculation.
class PeakDetector {
  /// Minimum prominence required for a peak to be detected.
  ///
  /// Prominence is the height of the peak relative to the surrounding signal.
  /// Higher values result in fewer, more prominent peaks being detected.
  /// Default: 0.5 (heuristic value, should be adaptive based on signal characteristics).
  final double minProminence;

  /// Minimum distance in samples between consecutive peaks.
  ///
  /// Prevents detection of peaks that are too close together.
  /// At 30 FPS, a value of 10 corresponds to approximately 330ms, which is above
  /// the minimum physiological limit of roughly 250ms (200 BPM).
  /// Default: 10.
  final int minDistance;

  /// Creates a [PeakDetector] with the specified parameters.
  ///
  /// [minProminence] - Minimum prominence for peak detection. Defaults to 0.5.
  /// [minDistance] - Minimum distance between peaks in samples. Defaults to 10.
  const PeakDetector({this.minProminence = 0.5, this.minDistance = 10});

  /// Finds indices of peaks in the [signal].
  ///
  /// Algorithm:
  /// 1. Find local maxima.
  /// 2. Filter by minimum distance.
  /// 3. Filter by prominence (optional adaptation).
  List<int> findPeaks(List<double> signal) {
    if (signal.length < 3) return [];

    final peaks = <int>[];

    // 1. Find local maxima
    for (int i = 1; i < signal.length - 1; i++) {
      if (signal[i] > signal[i - 1] && signal[i] > signal[i + 1]) {
        // Candidate peak

        // 2. Check minimum distance from last peak
        if (peaks.isNotEmpty) {
          if (i - peaks.last < minDistance) {
            // Keep the larger of the two if they are too close
            if (signal[i] > signal[peaks.last]) {
              peaks.removeLast();
              peaks.add(i);
            }
            continue;
          }
        }

        // 3. Check prominence (Legacy/Simple)
        // Ideally we'd scan left and right for minima.
        // For efficiency in this stream, we use a simple heuristic:
        // Value must be > local background.
        // But for better accuracy we really should do the prominence check if performance allows.

        // Let's implement a simplified prominence check:
        // Look back 'minDistance' samples and see if we are significantly higher than the minimum in that window.
        final startSearch = math.max(0, i - minDistance);
        final endSearch = math.min(signal.length, i + minDistance);

        double localMin = double.maxFinite;
        for (int j = startSearch; j < endSearch; j++) {
          if (signal[j] < localMin) localMin = signal[j];
        }

        if (signal[i] - localMin >= minProminence) {
          peaks.add(i);
        }
      }
    }

    return peaks;
  }

  /// Converts peak indices to RR intervals in milliseconds.
  ///
  /// [peakIndices]: List of indices where peaks were found.
  /// [frameRate]: The sampling rate of the signal (e.g., 30 FPS).
  List<double> peaksToRRIntervals(List<int> peakIndices, double frameRate) {
    if (peakIndices.length < 2) return [];

    final rrIntervals = <double>[];
    for (int i = 1; i < peakIndices.length; i++) {
      final diffFrames = peakIndices[i] - peakIndices[i - 1];
      final seconds = diffFrames / frameRate;
      rrIntervals.add(seconds * 1000.0); // Convert to ms
    }
    return rrIntervals;
  }

  /// Interpolates peak times on a non-uniform monotonic time axis.
  ///
  /// A quadratic is fitted to each peak and its two neighboring samples. The
  /// vertex is constrained to the neighboring timestamps. Degenerate fits fall
  /// back to the center sample time.
  List<InterpolatedPeak> interpolatePeakTimes(
    List<double> signal,
    List<double> timestampsMicros,
    List<int> peakIndices,
  ) {
    if (signal.length != timestampsMicros.length) {
      throw ArgumentError('signal and timestampsMicros must have equal length');
    }

    final peaks = <InterpolatedPeak>[];
    for (final index in peakIndices) {
      if (index <= 0 || index >= signal.length - 1) {
        continue;
      }
      final x0 = timestampsMicros[index - 1];
      final x1 = timestampsMicros[index];
      final x2 = timestampsMicros[index + 1];
      final y0 = signal[index - 1];
      final y1 = signal[index];
      final y2 = signal[index + 1];
      final lower = math.min(x0, x2);
      final upper = math.max(x0, x2);

      var peakTime = x1;
      final d0 = (x0 - x1) * (x0 - x2);
      final d1 = (x1 - x0) * (x1 - x2);
      final d2 = (x2 - x0) * (x2 - x1);
      if (d0 != 0 && d1 != 0 && d2 != 0) {
        final a = y0 / d0 + y1 / d1 + y2 / d2;
        final b =
            -y0 * (x1 + x2) / d0 - y1 * (x0 + x2) / d1 - y2 * (x0 + x1) / d2;
        if (a.isFinite && b.isFinite && a < 0) {
          final vertex = -b / (2 * a);
          if (vertex.isFinite) {
            peakTime = vertex.clamp(lower, upper).toDouble();
          }
        }
      }

      final localStep = x2 - x0;
      final offset = localStep == 0 ? 0.0 : (peakTime - x1) * 2 / localStep;
      peaks.add(
        InterpolatedPeak(
          index: index,
          timeMicros: peakTime,
          subSampleOffset: offset.clamp(-1.0, 1.0).toDouble(),
        ),
      );
    }
    return peaks;
  }
}

class InterpolatedPeak {
  final int index;
  final double timeMicros;
  final double subSampleOffset;

  const InterpolatedPeak({
    required this.index,
    required this.timeMicros,
    required this.subSampleOffset,
  });
}
