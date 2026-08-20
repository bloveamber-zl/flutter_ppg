/// Flutter PPG (Photoplethysmography) - Camera-based heart rate detection.
///
/// This library provides real-time PPG signal processing from camera frames
/// to extract heart rate and RR interval information. It processes camera
/// images to detect cardiac activity through photoplethysmography.
///
/// ## Main Components
///
/// - [FlutterPPGService]: Main service class for processing camera image streams
/// - [PPGSignal]: Processed signal data containing RR intervals and quality metrics
/// - [PPGConfig]: Configuration for processing parameters and quality thresholds
/// - [FrameRateDetector]: Automatic frame rate detection from camera timestamps
/// - [RRIntervalAnalyzer]: Analysis tools for RR interval statistics
/// - [FilterResult]: Result of outlier filtering with rejection statistics
///
/// ## Quick Start
///
/// ```dart
/// import 'package:flutter_ppg/flutter_ppg.dart';
/// import 'package:camera/camera.dart';
///
/// final service = FlutterPPGService();
/// final signalStream = service.processImageStream(cameraStream);
///
/// await for (final signal in signalStream) {
///   if (signal.rrIntervals.isNotEmpty) {
///     final bpm = 60000 / signal.rrIntervals.reduce((a, b) => a + b) /
///                  signal.rrIntervals.length;
///     print('Heart rate: $bpm BPM');
///   }
/// }
/// ```
library;

export 'src/flutter_ppg_service.dart';
export 'src/models/ppg_signal.dart';
export 'src/models/ppg_beat_event.dart';
export 'src/models/ppg_config.dart';
export 'src/frame_rate_detector.dart';
export 'src/rr_interval_analyzer.dart';
export 'src/models/filter_result.dart';
