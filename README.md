# Flutter PPG (Photoplethysmography)

A Flutter package for real-time camera-based PPG (Photoplethysmography) signal processing.
This package extracts the raw red channel intensity from camera frames, filters the signal to isolate cardiac activity, and detects heartbeats (RR intervals).

## ⚠️ Requirements

1.  **Hardware**: A device with a **Camera** and a **Flash (Torch)**.
2.  **Platform**: iOS or Android (Real device required, Simulator/Emulator usually cannot provide camera/flash access).

## 🚀 Getting Started

### 1. Installation

Add `flutter_ppg` via pub:

```bash
flutter pub add flutter_ppg
```

Or add it to your `pubspec.yaml`:
```yaml
dependencies:
  flutter_ppg: ^0.2.4
```

### 2. Basic Usage

Use the `FlutterPPGService` to process a stream of `CameraImage`s from the `camera` package.

```dart
// 1. Initialize Service
final ppgService = FlutterPPGService();

// 2. Start Camera Image Stream
// (Assuming standard camera controller setup)
controller.startImageStream((CameraImage image) {
  // Bridge to stream if necessary, or just use the service directly if updated
});

// Since the current API expects a Stream<CameraImage>, you can use a StreamController:
final streamController = StreamController<CameraImage>();
controller.startImageStream((image) => streamController.add(image));

// 3. Process Stream
ppgService.processImageStream(streamController.stream).listen((PPGSignal signal) {
  print('Quality: ${signal.quality}');
  print('Filtered Value: ${signal.filteredIntensity}');
  if (signal.rrIntervals.isNotEmpty) {
    print('Last RR: ${signal.rrIntervals.last} ms');
  }
  if (signal.beatEvents.isNotEmpty) {
    final beat = signal.beatEvents.last;
    print('Peak: ${beat.peakTimestamp}, RR: ${beat.rrIntervalMs} ms');
  }
});

// Remember to dispose when done:
// streamController.close();
// ppgService.dispose();
```

See the `example/` directory for a complete working application.

### 3. Custom Configuration (PPGConfig)

You can override thresholds and timing using `PPGConfig`:

```dart
final config = PPGConfig(
  samplingRate: 30,
  windowSizeSeconds: 10,
  minRRMs: 300.0,
  maxRRMs: 2000.0,
  maxAdjacentRRChangeRatio: 0.30,
  maxAcceptableSDRRMs: 150.0,
  maxDriftRate: 50.0,
  minGoodSNR: 5.0,
  minFairSNR: 0.0,
  fingerPresenceMin: 30.0,
  fingerPresenceMax: 250.0,
  roiFraction: 0.30,
  roiSampleStride: 2,
);

final ppgService = FlutterPPGService(config: config);
```

For iOS BGRA8888 frames, `roiFraction` limits signal extraction to the
center of the image to reduce edge light leakage and background interference.
`roiSampleStride` reduces per-frame work by sampling every Nth pixel.

**Override Priority (SSOT rules):**
- If you pass custom instances (`qualityAssessor`, `outlierFilter`, `rrIntervalAnalyzer`, `peakDetector`),
  those **override** `PPGConfig` values for their respective behavior.
- If you do **not** pass a custom instance, `FlutterPPGService` builds it from `PPGConfig`.
- If you pass a custom `PeakDetector`, adaptive min-distance (FPS-based) is **not** applied.

### 4. Recommended Measurement Flow (Client-side)

The library emits raw metrics every frame. **Session control (warm-up, duration, acceptance) should
live in your app**, not inside the package.

Suggested gating logic:
- **Ignore the first ~10 seconds** (warm-up)
- Require **`signal.isFPSStable == true`**
- Require **`signal.rejectionRatio <= 0.20`**
- Require **`signal.isSDRRAcceptable == true`**

Note: when `isFPSStable` is false, the package skips RR interval generation
and emits empty `rrIntervals` for that frame.

Example (pseudo):
```dart
if (signal.isFPSStable &&
    signal.rejectionRatio <= 0.20 &&
    signal.isSDRRAcceptable &&
    signal.quality != SignalQuality.poor) {
  // Accept this signal for BPM/HRV calculation
}
```

### 5. Operational Notes (Recommended)

These are practical guidelines for more stable measurements in real apps:

- **Low FPS segments**: if `signal.frameRate` drops significantly (e.g., <20 FPS),
  discard those samples from BPM/HRV aggregation.
- **isFPSStable behavior**: stability requires sustained FPS above a minimum threshold
  (internally, consecutive low-FPS updates will set `isFPSStable=false`).
- **Recommended measurement duration**: 30–60 seconds yields more stable HRV metrics.
- **UI load matters**: heavy animations or frequent setState can reduce FPS and degrade signal quality.
- **Finger placement**: cover both lens and flash; minimize motion and pressure changes.
- **FPS stability**: frame rate is estimated from a monotonic clock to reduce wall-clock jitter.
- **Logging (optional)**: for debugging, capture at least:
  - `frameRate`, `isFPSStable`, `quality`, `snr`
  - `sdrr`, `rejectionRatio`, `driftRate`
  - raw/filtered **mean + range** over a short window

**Adaptive prominence details (current defaults):**
- `minProminence = max(0.2, 0.5 * stddev)` computed from the **last ~60 filtered samples**
- The detector is updated only when the prominence changes by **≥ 0.05**
- If there is not enough data, the base `PeakDetector.minProminence` is used

## 👆 How to Measure

For accurate readings in the `example` app (or your implementation):

1.  **Enable Flash**: The back camera flash MUST be on (`FlashMode.torch`).
2.  **Cover Lens & Flash**: Place your fingertip gently over **both** the camera lens and the flash.
    - Do not press too hard (this restricts blood flow).
    - Do not press too lightly (ambient light leaks in).
3.  **Stay Still**: Motion introduces significant noise. Keep your finger and the phone steady.

## 📦 Features

- **Signal Processing**:
  - Red channel extraction (optimized for YUV420/BGRA8888).
  - Simple bandpass approximation (SMA short - SMA long) to isolate pulse band.
  - Detrending helper available (not wired into the current pipeline).
- **Peak Detection**:
  - Robust local maxima detection with minimum distance enforcement.
  - Monotonic per-frame timing and constrained quadratic peak interpolation.
  - `PPGBeatEvent` keeps each filtered RR paired with its peak timestamp.
  - Outlier rejection (IQR method) for cleaner RR intervals.
  - Adaptive prominence based on recent filtered signal variability.
- **Quality Assessment**:
  - Real-time Signal Quality Index (Good/Fair/Poor).
  - Finger presence detection based on light intensity.
  - SNR-based quality evaluation.

## 🧩 Architecture

The package follows clean architecture principles:

- `SignalProcessor`: Pure logic for math and filtering (Stateless).
- `PeakDetector`: Algorithms for identifying heartbeats.
- `SignalQualityAssessor`: Heuristics for signal validity.
- `FlutterPPGService`: Orchestrator (Stateful) managing the data flow and buffers.

## ✅ Current Defaults

**Current defaults (v0.2.4):**
- Sampling rate: 30 FPS (`PPGConfig.samplingRate`) - fallback value used before FPS stabilizes
- Window size: 10 seconds (`PPGConfig.windowSizeSeconds`)
- Peak min distance: derived from `PPGConfig.minRRMs` + detected FPS (adaptive)
- Peak min prominence: 0.5 (`PeakDetector.minProminence`) - adaptively adjusted based on signal variability
- RR physiological range: 300–2000ms (`PPGConfig.minRRMs` / `maxRRMs`)
- Max adjacent RR change: 30% (`PPGConfig.maxAdjacentRRChangeRatio`)
- Max acceptable SDRR: 150ms (`PPGConfig.maxAcceptableSDRRMs`)
- Max baseline drift: 50 intensity units/sec (`PPGConfig.maxDriftRate`)
- Finger presence: 30–250 intensity (`PPGConfig.fingerPresenceMin` / `fingerPresenceMax`)
- SNR quality: >5 dB = good, >0 dB = fair (`PPGConfig.minGoodSNR` / `minFairSNR`)
- Frame-rate auto detection: 24/25/30/60 FPS with adaptive timing windows (`FrameRateDetector`)

**Notes:**
- "Intensity" is derived from camera pixel data (0–255-ish scale).
- Time-based windows and min-distance are automatically derived from the detected FPS.
- Peak detection uses adaptive prominence based on the last ~60 filtered samples.

## 📝 License

MIT
# flutter_ppg
