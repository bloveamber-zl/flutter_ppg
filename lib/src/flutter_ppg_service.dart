import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'models/ppg_signal.dart';
import 'models/ppg_config.dart';
import 'signal_processor.dart';
import 'peak_detector.dart';
import 'quality_assessor.dart';
import 'outlier_filter.dart';
import 'frame_rate_detector.dart';
import 'rr_interval_analyzer.dart';
import 'models/filter_result.dart';
import 'models/ppg_beat_event.dart';
import 'utils/ring_buffer.dart';

/// Service to process camera images into PPG signals and RR intervals.
///
/// This is the main entry point for PPG signal processing. It processes a stream
/// of camera images and produces a stream of [PPGSignal] objects containing
/// heart rate and RR interval information.
///
/// The service performs the following processing pipeline:
/// 1. Extracts intensity from camera frames (red channel)
/// 2. Detects actual frame rate from timestamps
/// 3. Applies bandpass filtering to remove noise
/// 4. Detects peaks in the filtered signal
/// 5. Calculates RR intervals from peak positions
/// 6. Filters outliers from RR intervals
/// 7. Assesses signal quality and provides metrics
///
/// Example usage:
/// ```dart
/// final service = FlutterPPGService(config: PPGConfig());
/// final signalStream = service.processImageStream(cameraStream);
/// await for (final signal in signalStream) {
///   print('Heart rate: ${signal.rrIntervals.length > 0 ?
///     60000 / signal.rrIntervals.average : 'N/A'} BPM');
/// }
/// ```
class FlutterPPGService {
  /// Configuration for PPG processing parameters.
  final PPGConfig config;

  final SignalProcessor _processor;
  final PeakDetector _peakDetector;
  final SignalQualityAssessor _qualityAssessor;
  final OutlierFilter _outlierFilter;
  final FrameRateDetector _frameRateDetector;
  final RRIntervalAnalyzer _rrAnalyzer;
  final bool _isCustomPeakDetector;

  // State
  late RingBuffer<double> _rawBuffer;
  late RingBuffer<double> _filteredBuffer;
  late RingBuffer<double> _filteredTimeBuffer;
  late PeakDetector _adaptivePeakDetector;
  int _adaptiveMinDistance = 0;
  double _adaptiveMinProminence = 0.0;
  final Stopwatch _frameStopwatch = Stopwatch();
  DateTime? _wallClockOrigin;
  int? _monotonicOriginMicros;

  /// Creates a new [FlutterPPGService] instance.
  ///
  /// All parameters are optional and will use default implementations if not provided.
  /// This allows for dependency injection and testing.
  ///
  /// [config] - Configuration for processing parameters. Defaults to [PPGConfig] with default values.
  /// [processor] - Signal processor for intensity extraction and filtering. Defaults to [SignalProcessor].
  /// [peakDetector] - Peak detection algorithm. If provided, uses fixed parameters instead of adaptive detection.
  /// [qualityAssessor] - Signal quality assessment. Defaults to [SignalQualityAssessor] configured from [config].
  /// [outlierFilter] - Outlier filter for RR intervals. Defaults to [OutlierFilter] configured from [config].
  /// [frameRateDetector] - Frame rate detection. Defaults to [FrameRateDetector].
  /// [rrIntervalAnalyzer] - RR interval analysis. Defaults to [RRIntervalAnalyzer] configured from [config].
  FlutterPPGService({
    this.config = const PPGConfig(),
    SignalProcessor? processor,
    PeakDetector? peakDetector,
    SignalQualityAssessor? qualityAssessor,
    OutlierFilter? outlierFilter,
    FrameRateDetector? frameRateDetector,
    RRIntervalAnalyzer? rrIntervalAnalyzer,
  }) : _processor =
           processor ??
           SignalProcessor(
             roiFraction: config.roiFraction,
             roiSampleStride: config.roiSampleStride,
           ),
       _peakDetector = peakDetector ?? const PeakDetector(),
       _qualityAssessor =
           qualityAssessor ?? SignalQualityAssessor.fromConfig(config),
       _outlierFilter = outlierFilter ?? OutlierFilter.fromConfig(config),
       _frameRateDetector = frameRateDetector ?? FrameRateDetector(),
       _rrAnalyzer =
           rrIntervalAnalyzer ?? RRIntervalAnalyzer.fromConfig(config),
       _isCustomPeakDetector = peakDetector != null {
    // Initialize buffer based on config
    // 30 FPS * 10 seconds = 300 samples
    int capacity = (config.samplingRate * config.windowSizeSeconds).round();
    _rawBuffer = RingBuffer<double>(capacity);
    _filteredBuffer = RingBuffer<double>(capacity);
    _filteredTimeBuffer = RingBuffer<double>(capacity);
    if (_isCustomPeakDetector) {
      _adaptivePeakDetector = _peakDetector;
      _adaptiveMinDistance = _peakDetector.minDistance;
      _adaptiveMinProminence = _peakDetector.minProminence;
    } else {
      _adaptiveMinDistance = _minDistanceFromFps(
        config.samplingRate.toDouble(),
      );
      _adaptiveMinProminence = _peakDetector.minProminence;
      _adaptivePeakDetector = PeakDetector(
        minProminence: _adaptiveMinProminence,
        minDistance: _adaptiveMinDistance,
      );
    }
  }

  /// Disposes of resources and resets internal state.
  ///
  /// Call this method when the service is no longer needed to free up memory
  /// and reset the frame rate detector. After calling [dispose], the service
  /// should not be used again.
  void dispose() {
    _rawBuffer.clear();
    _filteredBuffer.clear();
    _filteredTimeBuffer.clear();
    _frameRateDetector.reset();
    _frameStopwatch.stop();
    _wallClockOrigin = null;
    _monotonicOriginMicros = null;
  }

  /// Returns the currently detected frame rate in frames per second (FPS).
  ///
  /// This value is automatically detected from camera frame timestamps.
  /// Returns the configured fallback sampling rate if detection hasn't
  /// started yet or if detection is unstable.
  double get detectedFPS => _frameRateDetector.fps;

  /// Returns true if frame rate detection has stabilized.
  ///
  /// Frame rate detection requires a warmup period before it's considered
  /// stable. This property indicates whether enough frames have been processed
  /// and the detected frame rate is consistent.
  bool get isFPSStable => _frameRateDetector.isStable;

  /// Processes a stream of camera images and yields PPG signals.
  ///
  /// This is the main processing method that takes a stream of [CameraImage] objects
  /// and produces a stream of [PPGSignal] objects. Each frame is processed to extract
  /// intensity, filter the signal, detect peaks, and calculate RR intervals.
  ///
  /// The method yields a [PPGSignal] for each input frame, even if the signal quality
  /// is poor or insufficient data is available. In such cases, the signal will have
  /// empty RR intervals and appropriate quality indicators.
  ///
  /// Processing stages:
  /// 1. Frame rate detection and stabilization
  /// 2. Intensity extraction from camera frame
  /// 3. Signal quality assessment
  /// 4. Bandpass filtering
  /// 5. Peak detection (only when frame rate is stable)
  /// 6. RR interval calculation and outlier filtering
  /// 7. Signal quality metrics calculation
  ///
  /// [images] - Stream of camera images to process.
  /// Returns a stream of [PPGSignal] objects, one per input frame.
  Stream<PPGSignal> processImageStream(Stream<CameraImage> images) async* {
    await for (final image in images) {
      final now = DateTime.now();
      final frameMicros = _nowMicros();
      _wallClockOrigin ??= now;
      _monotonicOriginMicros ??= frameMicros;

      _frameRateDetector.recordFrameMicros(frameMicros);
      final effectiveFPS = _effectiveFrameRate();
      _resizeBuffersIfNeeded(effectiveFPS);

      // 1. Extract Signal
      double intensity;
      try {
        intensity = _processor.extractRedChannel(image);
      } catch (e) {
        // Skip frame on error
        continue;
      }

      // 2. Update Raw Buffer
      _rawBuffer.add(intensity);

      // 3. Early Exit if filling buffer
      final minSamplesForQuality = effectiveFPS.round();
      if (!_rawBuffer.isFull && _rawBuffer.length < minSamplesForQuality) {
        // Need at least 1s of data
        yield PPGSignal(
          rawIntensity: intensity,
          filteredIntensity: 0.0,
          rrIntervals: [],
          quality: SignalQuality.poor,
          timestamp: now,
          peakIndices: [],
          snr: 0.0,
          frameRate: _frameRateDetector.fps,
          isFPSStable: _frameRateDetector.isStable,
        );
        continue;
      }

      final rawWindow = _rawBuffer.toList;

      // 4. Quality Assessment
      final quality = _qualityAssessor.assessQualityWithDrift(
        rawWindow,
        effectiveFPS,
      );
      final driftRate = _qualityAssessor.calculateDriftRate(
        rawWindow,
        effectiveFPS,
      );

      if (quality == SignalQuality.poor) {
        // Even if poor, we might want to feed the filter to keep state?
        // Or just reset?
        // Let's add 0 to filtered buffer to maintain time alignment roughly,
        // or just add the raw trend.
        // Better: Calculate filter anyway to keep continuity if signal recovers.

        final filteredPoint = _processor.simpleBandpassFilter(rawWindow, 5);
        _filteredBuffer.add(filteredPoint);
        _filteredTimeBuffer.add(frameMicros.toDouble());

        yield PPGSignal(
          rawIntensity: intensity,
          filteredIntensity: filteredPoint,
          rrIntervals: [],
          quality: SignalQuality.poor,
          timestamp: now,
          peakIndices: [],
          snr: _qualityAssessor.calculateSNR(rawWindow),
          frameRate: _frameRateDetector.fps,
          isFPSStable: _frameRateDetector.isStable,
          driftRate: driftRate,
        );
        continue;
      }

      // 5. Filtering
      final filteredPoint = _processor.simpleBandpassFilter(rawWindow, 5);
      _filteredBuffer.add(filteredPoint);
      _filteredTimeBuffer.add(frameMicros.toDouble());

      // 6. Peak Detection & RR Intervals
      if (!_frameRateDetector.isStable) {
        final snr = _qualityAssessor.calculateSNR(rawWindow);
        yield PPGSignal(
          rawIntensity: intensity,
          filteredIntensity: filteredPoint,
          rrIntervals: [],
          quality: quality,
          timestamp: now,
          peakIndices: const [],
          snr: snr,
          frameRate: _frameRateDetector.fps,
          isFPSStable: false,
          driftRate: driftRate,
          sdrr: 0.0,
          isSDRRAcceptable: false,
          rejectionRatio: 0.0,
          rejectedIntervalCount: 0,
        );
        continue;
      }

      final filteredWindow = _filteredBuffer.toList;
      final filteredTimes = _filteredTimeBuffer.toList;
      final dynamicProminence = _dynamicMinProminence(filteredWindow);
      _updateAdaptivePeakDetector(effectiveFPS, dynamicProminence);
      final peakIndices = _adaptivePeakDetector.findPeaks(filteredWindow);

      // Map indices to local window time?
      // We need RR intervals.
      // Peaks are indices in the 'filteredWindow'.
      // Index N is 'now'. Index 0 is 'capacity' frames ago.

      List<double> rrIntervals = [];
      List<PPGBeatEvent> beatEvents = [];
      FilterResult filterResult = const FilterResult(
        intervals: [],
        totalInput: 0,
        rejectedCount: 0,
        rejectionRatio: 0.0,
      );
      RRAnalysisResult rrAnalysis = _rrAnalyzer.analyze(const <double>[]);
      if (peakIndices.length >= 2) {
        final peaks = _adaptivePeakDetector.interpolatePeakTimes(
          filteredWindow,
          filteredTimes,
          peakIndices,
        );
        final rawEvents = <PPGBeatEvent>[];
        for (var index = 1; index < peaks.length; index++) {
          final peak = peaks[index];
          final rrIntervalMs =
              (peak.timeMicros - peaks[index - 1].timeMicros) / 1000.0;
          rawEvents.add(
            PPGBeatEvent(
              peakTimeMicros: peak.timeMicros,
              peakTimestamp: _wallTimestampFor(peak.timeMicros),
              rrIntervalMs: rrIntervalMs,
              peakIndex: peak.index,
              subSampleOffset: peak.subSampleOffset,
            ),
          );
        }
        final eventFilter = _outlierFilter.filterIndexed(
          rawEvents,
          (event) => event.rrIntervalMs,
        );
        beatEvents = eventFilter.values;
        rrIntervals = beatEvents.map((event) => event.rrIntervalMs).toList();
        filterResult = FilterResult(
          intervals: rrIntervals,
          totalInput: eventFilter.totalInput,
          rejectedCount: eventFilter.rejectedCount,
          rejectionRatio: eventFilter.rejectionRatio,
        );
        rrAnalysis = _rrAnalyzer.analyze(rrIntervals);
      }

      final snr = _qualityAssessor.calculateSNR(rawWindow);

      yield PPGSignal(
        rawIntensity: intensity,
        filteredIntensity: filteredPoint,
        rrIntervals: rrIntervals,
        beatEvents: beatEvents,
        quality: quality,
        timestamp: now,
        peakIndices: peakIndices,
        snr: snr,
        frameRate: _frameRateDetector.fps,
        isFPSStable: _frameRateDetector.isStable,
        driftRate: driftRate,
        sdrr: rrAnalysis.sdrr,
        isSDRRAcceptable: rrAnalysis.isSDRRAcceptable,
        rejectionRatio: filterResult.rejectionRatio,
        rejectedIntervalCount: filterResult.rejectedCount,
      );
    }
  }

  double _effectiveFrameRate() {
    final detected = _frameRateDetector.fps;
    if (detected <= 0) {
      return config.samplingRate.toDouble();
    }
    return detected;
  }

  void _resizeBuffersIfNeeded(double fps) {
    if (!_frameRateDetector.isStable) return;

    final desiredCapacity = (fps * config.windowSizeSeconds).round();
    if (desiredCapacity <= 0) return;
    if (_rawBuffer.capacity == desiredCapacity) return;

    final rawValues = _rawBuffer.toList;
    final filteredValues = _filteredBuffer.toList;
    final filteredTimes = _filteredTimeBuffer.toList;

    final newRaw = RingBuffer<double>(desiredCapacity);
    final newFiltered = RingBuffer<double>(desiredCapacity);
    final newFilteredTimes = RingBuffer<double>(desiredCapacity);

    final rawStart = rawValues.length > desiredCapacity
        ? rawValues.length - desiredCapacity
        : 0;
    for (int i = rawStart; i < rawValues.length; i++) {
      newRaw.add(rawValues[i]);
    }

    final filteredStart = filteredValues.length > desiredCapacity
        ? filteredValues.length - desiredCapacity
        : 0;
    for (int i = filteredStart; i < filteredValues.length; i++) {
      newFiltered.add(filteredValues[i]);
      newFilteredTimes.add(filteredTimes[i]);
    }

    _rawBuffer = newRaw;
    _filteredBuffer = newFiltered;
    _filteredTimeBuffer = newFilteredTimes;
  }

  DateTime _wallTimestampFor(double monotonicMicros) {
    final wallOrigin = _wallClockOrigin!;
    final monotonicOrigin = _monotonicOriginMicros!;
    return wallOrigin.add(
      Duration(microseconds: (monotonicMicros - monotonicOrigin).round()),
    );
  }

  void _updateAdaptivePeakDetector(
    double fps, [
    double? minProminenceOverride,
  ]) {
    if (_isCustomPeakDetector) return;
    final minDistanceFrames = _minDistanceFromFps(fps);
    final minProminence = minProminenceOverride ?? _adaptiveMinProminence;
    final prominenceChanged =
        (minProminence - _adaptiveMinProminence).abs() >= 0.05;
    if (minDistanceFrames == _adaptiveMinDistance && !prominenceChanged) return;

    _adaptivePeakDetector = PeakDetector(
      minProminence: minProminence,
      minDistance: minDistanceFrames,
    );
    _adaptiveMinDistance = minDistanceFrames;
    _adaptiveMinProminence = minProminence;
  }

  int _minDistanceFromFps(double fps) {
    int minDistanceFrames = (fps * (config.minRRMs / 1000.0)).round();
    if (minDistanceFrames < 1) {
      minDistanceFrames = 1;
    }
    return minDistanceFrames;
  }

  int _nowMicros() {
    if (!_frameStopwatch.isRunning) {
      _frameStopwatch.start();
    }
    return _frameStopwatch.elapsedMicroseconds;
  }

  double _dynamicMinProminence(List<double> signal) {
    if (signal.length < 10) {
      return _adaptiveMinProminence > 0.0
          ? _adaptiveMinProminence
          : _peakDetector.minProminence;
    }
    final start = signal.length > 60 ? signal.length - 60 : 0;
    final stdDev = _calculateStdDev(signal.sublist(start));
    final computed = stdDev * 0.5;
    return computed < 0.2 ? 0.2 : computed;
  }

  double _calculateStdDev(List<double> values) {
    if (values.isEmpty) return 0.0;
    double sum = 0.0;
    for (final v in values) {
      sum += v;
    }
    final mean = sum / values.length;
    double varianceSum = 0.0;
    for (final v in values) {
      final diff = v - mean;
      varianceSum += diff * diff;
    }
    final variance = varianceSum / values.length;
    return variance <= 0.0 ? 0.0 : math.sqrt(variance);
  }
}
