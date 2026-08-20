import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_ppg/flutter_ppg.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.red, useMaterial3: true),
      home: const PPGExamplePage(),
    );
  }
}

class PPGExamplePage extends StatefulWidget {
  const PPGExamplePage({super.key});

  @override
  State<PPGExamplePage> createState() => _PPGExamplePageState();
}

class _PPGExamplePageState extends State<PPGExamplePage> {
  CameraController? _controller;
  final _ppgService = FlutterPPGService();

  // State for UI
  PPGSignal? _currentSignal;
  String _status = 'Initializing...';
  bool _isScanning = false;
  bool _isTransitioning = false;
  int _timeLeft = 30;
  Timer? _timer;
  Timer? _uiUpdateTimer;
  DateTime? _lastLogTime;
  static const Duration _logInterval = Duration(seconds: 1);
  final bool _enableConsoleLog = true;
  static const int _bpmWindowSize = 8;
  static const int _statsWindowSize = 60;

  // Data buffers for visualization
  final List<double> _rawHistory = [];
  final List<double> _filteredHistory = [];
  final List<double> _rrHistory = [];
  List<int> _currentPeakIndices = [];
  static const int _historyLimit = 150;

  PPGSignal? _pendingSignal;
  StreamController<CameraImage>? _imageStreamController;
  StreamSubscription<PPGSignal>? _ppgSubscription;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _status = 'No cameras found.');
        return;
      }
      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      _controller = CameraController(camera, ResolutionPreset.low, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await _controller!.initialize();
      if (mounted) setState(() => _status = 'Ready. Press Start to measure.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Camera error: $e');
    }
  }

  void _toggleScanning() {
    if (_isTransitioning) return;
    _isScanning ? _stopProcessing() : _startProcessing();
  }

  Future<void> _startProcessing() async {
    if (_controller == null || !_controller!.value.isInitialized || _isTransitioning) return;
    _isTransitioning = true;

    setState(() {
      _isScanning = true;
      _timeLeft = 30;
      _rawHistory.clear();
      _filteredHistory.clear();
      _rrHistory.clear();
      _currentPeakIndices = [];
      _currentSignal = null;
      _pendingSignal = null;
      _status = 'Starting...';
    });

    try {
      await _controller!.setFlashMode(FlashMode.torch);
    } catch (e) {
      debugPrint('Flash error: $e');
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isScanning) {
        setState(() => _timeLeft--);
        if (_timeLeft <= 0) _stopProcessing();
      }
    });

    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _pendingSignal != null) _applyPendingSignal();
    });

    _imageStreamController = StreamController<CameraImage>();
    try {
      await _controller!.startImageStream((image) {
        if (_imageStreamController != null && !_imageStreamController!.isClosed) {
          _imageStreamController!.add(image);
        }
      });
    } catch (e) {
      debugPrint('Image stream error: $e');
      _isTransitioning = false;
      await _stopProcessing();
      return;
    }

    _ppgSubscription = _ppgService.processImageStream(_imageStreamController!.stream).listen((signal) {
      _maybeLogSignal(signal);
      _pendingSignal = signal;
      _rawHistory.add(signal.rawIntensity);
      _filteredHistory.add(signal.filteredIntensity);
      if (_rawHistory.length > _historyLimit) _rawHistory.removeAt(0);
      if (_filteredHistory.length > _historyLimit) _filteredHistory.removeAt(0);
      _currentPeakIndices = signal.peakIndices;
      for (final rr in signal.rrIntervals) {
        _rrHistory.add(rr);
        if (_rrHistory.length > 20) _rrHistory.removeAt(0);
      }
    });

    _isTransitioning = false;
  }

  void _maybeLogSignal(PPGSignal signal) {
    if (!_enableConsoleLog) return;
    final now = DateTime.now();
    if (_lastLogTime != null && now.difference(_lastLogTime!) < _logInterval) return;
    _lastLogTime = now;

    final meanRR = _meanRecentRR();
    final bpm = meanRR > 0 ? (60000 / meanRR).round() : 0;
    final isValid = _isSignalValid(signal);
    final validityReason = _validityReason(signal);
    final rawStats = _calcStats(_rawHistory);
    final filteredStats = _calcStats(_filteredHistory);

    debugPrint(
      '[flutter_ppg][example] '
      'fps=${signal.frameRate.toStringAsFixed(1)} '
      'stable=${signal.isFPSStable} '
      'quality=${signal.quality.name} '
      'snr=${signal.snr.toStringAsFixed(1)}dB '
      'bpm=${bpm == 0 ? "--" : bpm} '
      'sdrr=${signal.sdrr.toStringAsFixed(1)} '
      'rej=${(signal.rejectionRatio * 100).toStringAsFixed(0)}% '
      'drift=${signal.driftRate.toStringAsFixed(1)} '
      'valid=$isValid '
      'reason=${validityReason.isEmpty ? "-" : validityReason} '
      'raw=${signal.rawIntensity.toStringAsFixed(1)} '
      'rawMean=${rawStats.mean.toStringAsFixed(1)} '
      'rawRange=${rawStats.min.toStringAsFixed(1)}..${rawStats.max.toStringAsFixed(1)} '
      'filt=${signal.filteredIntensity.toStringAsFixed(2)} '
      'filtMean=${filteredStats.mean.toStringAsFixed(2)} '
      'filtRange=${filteredStats.min.toStringAsFixed(2)}..${filteredStats.max.toStringAsFixed(2)} '
      'peaks=${_currentPeakIndices.length} '
      'rrCount=${signal.rrIntervals.length}',
    );
  }

  double _meanRecentRR() {
    if (_rrHistory.isEmpty) return 0.0;
    final start = _rrHistory.length > _bpmWindowSize ? _rrHistory.length - _bpmWindowSize : 0;
    double sum = 0.0;
    int count = 0;
    for (int i = start; i < _rrHistory.length; i++) {
      sum += _rrHistory[i];
      count++;
    }
    return count == 0 ? 0.0 : sum / count;
  }

  bool _isSignalValid(PPGSignal signal) {
    return signal.quality != SignalQuality.poor &&
        signal.isSDRRAcceptable &&
        signal.rejectionRatio <= 0.20;
  }

  String _validityReason(PPGSignal signal) {
    final reasons = <String>[];
    if (signal.quality == SignalQuality.poor) reasons.add('quality');
    if (!signal.isSDRRAcceptable) reasons.add('sdrr');
    if (signal.rejectionRatio > 0.20) reasons.add('rejection');
    return reasons.join('+');
  }

  _Stats _calcStats(List<double> values) {
    if (values.isEmpty) return const _Stats(0.0, 0.0, 0.0);
    final start = values.length > _statsWindowSize ? values.length - _statsWindowSize : 0;
    double sum = 0.0;
    double minV = double.maxFinite;
    double maxV = -double.maxFinite;
    int count = 0;
    for (int i = start; i < values.length; i++) {
      final v = values[i];
      sum += v;
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
      count++;
    }
    final mean = count == 0 ? 0.0 : sum / count;
    if (count == 0) return const _Stats(0.0, 0.0, 0.0);
    return _Stats(mean, minV, maxV);
  }

  void _applyPendingSignal() {
    if (_pendingSignal == null) return;
    final signal = _pendingSignal!;
    _pendingSignal = null;
    setState(() {
      _currentSignal = signal;
      _status = signal.quality == SignalQuality.good
          ? 'Signal Good - Detecting...'
          : signal.quality == SignalQuality.fair
          ? 'Signal Fair - Keep steady'
          : 'Signal Poor - Cover camera';
    });
  }

  Future<void> _stopProcessing() async {
    if (_isTransitioning) return;
    _isTransitioning = true;

    _timer?.cancel();
    _uiUpdateTimer?.cancel();
    await _ppgSubscription?.cancel();
    await _imageStreamController?.close();
    _timer = null;
    _uiUpdateTimer = null;
    _ppgSubscription = null;
    _imageStreamController = null;

    if (_controller != null && _controller!.value.isInitialized) {
      try {
        if (_controller!.value.isStreamingImages) await _controller!.stopImageStream();
        await _controller!.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint('Stop camera error: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isScanning = false;
        _status = 'Measurement Complete.';
      });
    }
    _isTransitioning = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _uiUpdateTimer?.cancel();
    _ppgSubscription?.cancel();
    _imageStreamController?.close();
    _controller?.dispose();
    _ppgService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String hrDisplay = '--';
    final meanRR = _meanRecentRR();
    if (meanRR > 0) hrDisplay = '${(60000 / meanRR).round()}';

    return Scaffold(
      appBar: AppBar(title: const Text('Flutter PPG Demo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCameraPreview(),
                const SizedBox(width: 16),
                Expanded(child: _buildStatsPanel(hrDisplay)),
              ],
            ),
            const SizedBox(height: 16),
            _buildWaveformCard('Raw Signal (Red Channel)', _rawHistory, Colors.red.shade300, []),
            const SizedBox(height: 12),
            _buildWaveformCard('Filtered Signal (Bandpass)', _filteredHistory, Colors.greenAccent, _currentPeakIndices),
            const SizedBox(height: 12),
            _buildRRHistoryCard(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isTransitioning ? null : _toggleScanning,
        backgroundColor: _isTransitioning ? Colors.grey : (_isScanning ? Colors.red : Colors.green),
        icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
        label: Text(_isScanning ? 'STOP' : 'START'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildCameraPreview() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Container(
        height: 100,
        width: 100,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade800),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return Container(
      height: 100,
      width: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _getQualityColor(), width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: CameraPreview(_controller!),
    );
  }

  Widget _buildStatsPanel(String hrDisplay) {
    final snr = _currentSignal?.snr ?? 0.0;
    final quality = _currentSignal?.quality ?? SignalQuality.poor;
    final rejectionRatio = _currentSignal?.rejectionRatio ?? 0.0;
    final sdrr = _currentSignal?.sdrr ?? 0.0;
    final isValid = _currentSignal != null && _isSignalValid(_currentSignal!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$hrDisplay BPM',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _getQualityColor()),
                ),
                if (_isScanning)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                    child: Text('$_timeLeft s'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_status, style: TextStyle(color: _getQualityColor())),
            const SizedBox(height: 8),
            Text(
              'Quality: ${quality.name.toUpperCase()} | SNR: ${snr.toStringAsFixed(1)} dB | Peaks: ${_currentPeakIndices.length}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              'Valid: ${isValid ? "YES" : "NO"} | SDRR: ${sdrr.toStringAsFixed(1)} ms | Rej: ${(rejectionRatio * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveformCard(String title, List<double> data, Color color, List<int> peaks) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: CustomPaint(painter: _WaveformPainter(data, color, peaks), child: Container()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRRHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('RR Intervals (ms)', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            _rrHistory.isEmpty
                ? const Text('Waiting for data...', style: TextStyle(color: Colors.white54))
                : Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _rrHistory.map((rr) {
                      final isOutlier = rr < 400 || rr > 1500;
                      return Chip(
                        label: Text('${rr.round()}'),
                        backgroundColor: isOutlier ? Colors.orange.shade800 : Colors.green.shade800,
                        labelStyle: const TextStyle(fontSize: 11),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
          ],
        ),
      ),
    );
  }

  Color _getQualityColor() {
    if (!_isScanning || _currentSignal == null) return Colors.grey;
    return switch (_currentSignal!.quality) {
      SignalQuality.good => Colors.greenAccent,
      SignalQuality.fair => Colors.orangeAccent,
      SignalQuality.poor => Colors.redAccent,
    };
  }
}

/// Lightweight waveform painter with optional peak markers.
class _WaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final List<int> peaks;

  _WaveformPainter(this.data, this.color, this.peaks);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    final w = size.width, h = size.height, len = data.length;

    double minV = data.reduce((a, b) => a < b ? a : b), maxV = data.reduce((a, b) => a > b ? a : b);
    final range = maxV - minV, pad = range * 0.1;
    minV -= pad;
    maxV += pad;
    final scaleY = (maxV == minV) ? 1.0 : h / (maxV - minV);
    final stepX = w / (len - 1);

    for (int i = 0; i < len; i++) {
      final x = i * stepX, y = h - ((data[i] - minV) * scaleY);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);

    if (peaks.isNotEmpty) {
      final peakPaint = Paint()
        ..color = Colors.yellowAccent
        ..style = PaintingStyle.fill;
      for (final idx in peaks) {
        if (idx >= 0 && idx < len) {
          canvas.drawCircle(Offset(idx * stepX, h - ((data[idx] - minV) * scaleY)), 5, peakPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => old.data != data || old.peaks != peaks || old.color != color;
}

class _Stats {
  final double mean;
  final double min;
  final double max;

  const _Stats(this.mean, this.min, this.max);
}
