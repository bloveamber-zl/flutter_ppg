import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ppg/src/frame_rate_detector.dart';

void main() {
  group('FrameRateDetector', () {
    test('detects 30 FPS correctly', () {
      final detector = FrameRateDetector();
      var time = DateTime(2020, 1, 1);

      for (int i = 0; i < 60; i++) {
        detector.recordFrame(time);
        time = time.add(const Duration(milliseconds: 33));
      }

      expect(detector.isStable, isTrue);
      expect(detector.fps, closeTo(30.0, 1.0));
    });

    test('detects 60 FPS correctly', () {
      final detector = FrameRateDetector();
      var time = DateTime(2020, 1, 1);

      for (int i = 0; i < 120; i++) {
        detector.recordFrame(time);
        time = time.add(const Duration(milliseconds: 17));
      }

      expect(detector.isStable, isTrue);
      expect(detector.fps, closeTo(60.0, 1.0));
    });

    test('handles frame drops gracefully', () {
      final detector = FrameRateDetector();
      var time = DateTime(2020, 1, 1);

      for (int i = 0; i < 60; i++) {
        detector.recordFrame(time);
        final interval = (i % 10 == 0) ? 66 : 33;
        time = time.add(Duration(milliseconds: interval));
      }

      expect(detector.isStable, isTrue);
      expect(detector.fps, closeTo(30.0, 3.0));
    });

    test('snaps to common frame rates', () {
      final detector = FrameRateDetector();
      var time = DateTime(2020, 1, 1);

      for (int i = 0; i < 60; i++) {
        detector.recordFrame(time);
        time = time.add(const Duration(milliseconds: 34)); // ~29.4 FPS
      }

      expect(detector.fps, equals(30.0));
    });

    test('marks unstable when FPS is persistently low', () {
      final detector = FrameRateDetector();
      var time = DateTime(2020, 1, 1);

      // Simulate ~10 FPS (100ms interval)
      for (int i = 0; i < 60; i++) {
        detector.recordFrame(time);
        time = time.add(const Duration(milliseconds: 100));
      }

      expect(detector.fps, closeTo(10.0, 1.0));
      expect(detector.isStable, isFalse);
    });
  });
}
