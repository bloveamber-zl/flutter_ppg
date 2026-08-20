import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ppg/src/signal_processor.dart';

void main() {
  group('SignalProcessor', () {
    const processor = SignalProcessor();

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('BGRA extraction samples the configured central ROI', () {
      final image = _bgraImage(
        redValues: [
          [10, 10, 10, 10],
          [10, 100, 100, 10],
          [10, 100, 100, 10],
          [10, 10, 10, 10],
        ],
        bytesPerRow: 20,
      );

      const roiProcessor = SignalProcessor(
        roiFraction: 0.5,
        roiSampleStride: 1,
      );

      expect(roiProcessor.extractRedChannel(image), 100.0);
      expect(processor.extractRedChannel(image), 32.5);
    });

    test('BGRA extraction applies the configured pixel stride', () {
      final image = _bgraImage(
        redValues: [
          [100, 0, 100, 0],
          [0, 0, 0, 0],
          [100, 0, 100, 0],
          [0, 0, 0, 0],
        ],
        bytesPerRow: 20,
      );

      const stridedProcessor = SignalProcessor(
        roiFraction: 1.0,
        roiSampleStride: 2,
      );

      expect(stridedProcessor.extractRedChannel(image), 100.0);
    });

    test('applyMovingAverage calculates correct mean', () {
      final buffer = [1.0, 2.0, 3.0, 4.0, 5.0];
      expect(processor.applyMovingAverage(buffer), 3.0);
    });

    test('applyMovingAverage returns 0 for empty buffer', () {
      expect(processor.applyMovingAverage([]), 0.0);
    });

    test('detrend removes DC offset', () {
      final buffer = [10.0, 11.0, 12.0, 13.0, 14.0];
      // Mean is 12.0. Last is 14.0. Detrended = 14.0 - 12.0 = 2.0
      expect(processor.detrend(buffer), closeTo(2.0, 0.0001));
    });

    test('simpleBandpassFilter attenuates trend and noise', () {
      // 1. DC Trend: 100
      // 2. Signal: +1 (at end)
      // 3. Noise: ignored for simple test, let's just test logic math

      // Buffer: [100, 100, 100, 100, 101]
      // smoothingWindow: 2

      // Short SMA (last 2): (100+101)/2 = 100.5
      // Long SMA (all 5): 501/5 = 100.2
      // Result: 100.5 - 100.2 = 0.3

      final buffer = [100.0, 100.0, 100.0, 100.0, 101.0];
      final result = processor.simpleBandpassFilter(buffer, 2);

      expect(result, closeTo(0.3, 0.0001));
    });

    test('simpleBandpassFilter handles short buffers', () {
      final buffer = [1.0];
      // If len < smoothingWindow (e.g. 5), returns raw.last which is 1.0?
      // The impl says: if (n < smoothingWindow) return 0.0;
      expect(processor.simpleBandpassFilter(buffer, 5), 0.0);
    });
  });
}

CameraImage _bgraImage({
  required List<List<int>> redValues,
  required int bytesPerRow,
}) {
  final height = redValues.length;
  final width = redValues.first.length;
  final bytes = Uint8List(bytesPerRow * height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      bytes[y * bytesPerRow + x * 4 + 2] = redValues[y][x];
    }
  }

  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData({
    'format': 1111970369, // kCVPixelFormatType_32BGRA
    'height': height,
    'width': width,
    'planes': [
      {
        'bytes': bytes,
        'bytesPerPixel': null,
        'bytesPerRow': bytesPerRow,
        'height': height,
        'width': width,
      },
    ],
  });
}
