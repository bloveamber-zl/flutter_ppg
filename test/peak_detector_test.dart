import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ppg/src/peak_detector.dart';

void main() {
  group('PeakDetector', () {
    const detector = PeakDetector(minProminence: 10.0, minDistance: 5);

    test('findPeaks detects simple peaks', () {
      // 0, 100(Peak), 0, 0, 0, 0, 100(Peak), 0
      final signal = [0.0, 100.0, 0.0, 0.0, 0.0, 0.0, 100.0, 0.0];
      final peaks = detector.findPeaks(signal);
      expect(peaks, [1, 6]);
    });

    test('findPeaks respects minimum distance', () {
      // Peak at 1, Peak at 3 (too close), Peak at 10 (ok)
      // distance=5. 3-1=2 < 5. Should pick larger one.
      final signal = [
        0.0,
        50.0,
        0.0,
        100.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        50.0,
        0.0,
      ];
      // Peak at 1 (50). Peak at 3 (100).
      // 3 stays, 1 removed? Or just skip 3?
      // Impl logic: "if (signal[i] > signal[peaks.last]) { peaks.removeLast(); peaks.add(i); }"
      // So 3 replaces 1.

      final peaks = detector.findPeaks(signal);
      expect(peaks, [3, 10]);
    });

    test('findPeaks respects prominence', () {
      // Peak at 1 (value 100, localMin 0 -> prom 100 >= 10) -> OK
      // Peak at 4 (value 5, localMin 0 -> prom 5 < 10) -> Skip
      final signal = [0.0, 100.0, 0.0, 0.0, 5.0, 0.0, 0.0];
      final peaks = detector.findPeaks(signal);
      expect(peaks, [1]);
    });

    test('peaksToRRIntervals calculates ms correctly', () {
      // 30 FPS. Index 0 and 30. Diff 30. 30/30 = 1s = 1000ms.
      final indices = [0, 30];
      final rr = detector.peaksToRRIntervals(indices, 30.0);
      expect(rr.first, closeTo(1000.0, 0.001));
    });

    test('interpolates a peak on a non-uniform monotonic time axis', () {
      const interpolationDetector = PeakDetector(
        minProminence: 0.1,
        minDistance: 1,
      );
      final signal = [0.0, 8.0, 10.0, 7.0, 0.0];
      final timestamps = [0.0, 30000.0, 70000.0, 105000.0, 140000.0];

      final peaks = interpolationDetector.interpolatePeakTimes(
        signal,
        timestamps,
        [2],
      );

      expect(peaks, hasLength(1));
      expect(peaks.single.timeMicros, inInclusiveRange(30000.0, 105000.0));
      expect(peaks.single.timeMicros, isNot(equals(70000.0)));
      expect(peaks.single.subSampleOffset, inInclusiveRange(-1.0, 1.0));
    });

    test('rejects mismatched signal and timestamp lengths', () {
      expect(
        () => detector.interpolatePeakTimes([0.0, 1.0, 0.0], [0.0], [1]),
        throwsArgumentError,
      );
    });
  });
}
