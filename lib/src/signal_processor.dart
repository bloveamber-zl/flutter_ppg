import 'dart:typed_data';
import 'package:camera/camera.dart';

/// Processes raw camera data and digital signals to extract physiological information.
///
/// Follows strict signal processing principles:
/// - Stateless processing where possible (dependencies injected or passed as args)
/// - Fail-fast validation of inputs
/// - Optimized for real-time 30FPS processing
class SignalProcessor {
  /// Fraction of the image width and height sampled for BGRA8888 frames.
  final double roiFraction;

  /// Pixel step used while sampling the BGRA8888 region of interest.
  final int roiSampleStride;

  const SignalProcessor({this.roiFraction = 1.0, this.roiSampleStride = 1})
    : assert(roiFraction > 0 && roiFraction <= 1),
      assert(roiSampleStride > 0);

  /// Extracts the mean Red channel intensity from a [CameraImage].
  ///
  /// Supports:
  /// - YUV420 (Android default): Uses statistical approx `Mean(R) ≈ Mean(Y) + 1.402 * (Mean(V) - 128)`
  /// - BGRA8888 (iOS default): Direct byte access
  ///
  /// Throws [UnsupportedError] for other formats (including NV21 on older camera
  /// plugin versions where it may not be explicitly exposed as an enum value).
  double extractRedChannel(CameraImage image) {
    // Fail Fast: Validate image format
    switch (image.format.group) {
      case ImageFormatGroup.yuv420:
        return _extractRedFromYUV420(image);
      case ImageFormatGroup.bgra8888:
        return _extractRedFromBGRA8888(image);
      default:
        // Attempt fallback or fail if strictly unsupported.
        // For now, fail fast as these require specific implementations.
        throw UnsupportedError(
          'Unsupported image format: ${image.format.group}',
        );
    }
  }

  /// Optimized YUV420 extraction.
  ///
  /// Avoids full pixel conversion.
  /// R = Y + 1.402 * (V - 128)
  /// Mean(R) = Mean(Y) + 1.402 * (Mean(V) - 128)
  double _extractRedFromYUV420(CameraImage image) {
    // Plane 0 is Y (Luminance)
    final yPlane = image.planes[0];
    final yBytes = yPlane.bytes;
    final yMean = _calculateMean(yBytes);

    // Plane 2 is V (Cr - Chrominance Red)
    // Note: In Flutter camera YUV420, planes are: 0=Y, 1=U, 2=V
    final vPlane = image.planes[2];
    final vBytes = vPlane.bytes;
    final vMean = _calculateMean(vBytes);

    return yMean + 1.402 * (vMean - 128);
  }

  /// Extracts Red from BGRA8888 image buffer.
  double _extractRedFromBGRA8888(CameraImage image) {
    final plane = image.planes[0];
    final bytes = plane.bytes;
    final width = plane.width ?? image.width;
    final height = plane.height ?? image.height;
    final pixelStride = plane.bytesPerPixel ?? 4;
    final roiWidth = (width * roiFraction).round().clamp(1, width);
    final roiHeight = (height * roiFraction).round().clamp(1, height);
    final left = (width - roiWidth) ~/ 2;
    final top = (height - roiHeight) ~/ 2;
    final right = left + roiWidth;
    final bottom = top + roiHeight;

    int sum = 0;
    int count = 0;

    for (int y = top; y < bottom; y += roiSampleStride) {
      final rowOffset = y * plane.bytesPerRow;
      for (int x = left; x < right; x += roiSampleStride) {
        final redOffset = rowOffset + x * pixelStride + 2;
        if (redOffset < bytes.length) {
          sum += bytes[redOffset];
          count++;
        }
      }
    }

    return count == 0 ? 0.0 : sum / count;
  }

  double _calculateMean(Uint8List bytes) {
    if (bytes.isEmpty) return 0.0;

    // Performance optimization:
    // For very large images, subsampling might be preferred,
    // but calculating mean of a byte array is essentially O(N) and very fast in Dart
    // if we don't allocate new objects.

    int sum = 0;
    for (final byte in bytes) {
      sum += byte;
    }
    return sum / bytes.length;
  }

  /// Applies a Simple Moving Average (SMA) filter to smooth the signal.
  ///
  /// [windowSize] determines the smoothing factor. typical values are 3-5.
  double applyMovingAverage(List<double> buffer) {
    if (buffer.isEmpty) return 0.0;

    double sum = 0.0;
    for (final val in buffer) {
      sum += val;
    }
    return sum / buffer.length;
  }

  /// Removes low-frequency trend from the signal (Detrending).
  ///
  /// Returns the signal centered around 0.
  ///
  /// Implementation checks:
  /// - Uses a simple mean subtraction of the whole provided buffer.
  /// - For sliding window detrending, the caller should pass the appropriate window.
  double detrend(List<double> signal) {
    if (signal.isEmpty) return 0.0;
    final mean = applyMovingAverage(signal);
    return signal.last - mean;
  }

  /// Applies a bandpass-like filter effect using Moving Averages.
  ///
  /// This is a specialized simplified filter that:
  /// 1. Removes trend (High-pass equivalent)
  /// 2. Smooths noise (Low-pass equivalent)
  ///
  /// [rawSignalWindow]: The recent history of raw values.
  /// Must be long enough for the detrending window.
  /// [smoothingWindow]: Number of samples for the low-pass SMA.
  double simpleBandpassFilter(
    List<double> rawSignalWindow,
    int smoothingWindow,
  ) {
    if (rawSignalWindow.length < smoothingWindow) {
      // Not enough data yet, return raw or 0
      return 0.0;
    }

    // 1. Detrend (High-pass): Remove DC offset / baseline drift
    // We use the mean of the entire provided window as the baseline
    // final detrended = detrend(rawSignalWindow); // Unused in current algorithm

    // 2. Smooth (Low-pass):
    // Construct a small window of the most recent detrended values?
    // Actually, to do this correctly in a stream without re-processing everything,
    // we usually smooth the *output*.
    // But since this function returns a single double (current filtered value),
    // and 'detrend' operates on the *current* point relative to history...

    // Let's refine the logic for a single stream step:
    // The Input is the buffer of RAW values ending at 'now'.
    // We want the Filtered value at 'now'.

    // A better approach for "Simple Bandpass" without complex state:
    // Filtered = (SMA(small_window) - SMA(large_window))
    // SMA(small_window) preserves high-ish freq (removes very high freq noise)
    // SMA(large_window) captures the trend (low freq)
    // Subtracting them removes the trend and keeps the band of interest.

    // Let's stick to the plan: "Detrending -> Moving Average"

    // If we assume `rawSignalWindow` is effectively the "Large Window" used for detrending:
    // final trend = applyMovingAverage(rawSignalWindow); // Unused
    // final detrendedVal = rawSignalWindow.last - trend; // Unused in current algorithm

    // Now we need to smooth this `detrendedVal`.
    // But we don't have the history of *detrended* values passed in, only raw.
    // If we want to smooth, we strictly need history of the *result* or allow calculating
    // the "smoothed raw" first then detrending.

    // Alternative:
    // SMA_HighPass = Raw - SMA_Slow(Raw)
    // Result = SMA_Fast(SMA_HighPass)
    // This requires history of SMA_HighPass.

    // Simplified approximation for this "Stateless" processor (caller holding raw history):
    // We will just return the Detrended value here.
    // Smoothing is best applied *before* or *after* by the Service managing the buffers.
    // BUT the prompt asks for "simpleBandpassFilter".

    // Let's implement the "SMA(small) - SMA(large)" approach as it is fully functional
    // given just the raw history buffer.
    // Bandpass ~= SMA(short) - SMA(long)
    // SMA(short) = LowPass (cutoff high)
    // SMA(long) = Trends (cutoff low)
    // Diff = BandPass.

    final int n = rawSignalWindow.length;
    if (n < smoothingWindow) return 0.0;

    // SMA(current, short_window)
    final shortStart = n - smoothingWindow;
    final shortWindow = rawSignalWindow.sublist(shortStart);
    final smoothed = applyMovingAverage(shortWindow);

    // SMA(current, long_window) -> which is the whole buffer passed in roughly
    final trendVal = applyMovingAverage(rawSignalWindow);

    return smoothed - trendVal;
  }
}
