# Changelog

All notable changes to this project will be documented in this file.

## [0.2.4] - 2026-01-22

### Added

- Comprehensive documentation comments for all public APIs including classes, enums, fields, constructors, and methods.
- Library-level documentation in `flutter_ppg.dart` with quick start example.
- Detailed comments for `assert` conditions in constructors to inform users about valid parameter ranges.

### Fixed

- Fixed typo in README.md ("ligthly" → "lightly").

## [0.2.3] - 2026-01-19

### Fixed

- Removed direct reference to `ImageFormatGroup.nv21` to maintain compatibility with older `camera` versions during downgrade testing, while still treating unsupported formats as errors at runtime.

## [0.2.2] - 2026-01-18

### Changed

- Expanded `camera` package dependency range from `^0.11.3` to `>=0.10.0` for better compatibility with projects using older camera versions.

## [0.2.1] - 2026-01-15

### Added

- Adaptive peak prominence based on recent filtered signal variability.
- Monotonic timestamp support for FPS detection with low-FPS stability gating.
- Example app console logging improvements (validity reasons and signal stats).

### Changed

- `isFPSStable=false` now skips RR generation to reduce false positives.
- Quality assessment window size scales with detected frame rate.
- Documentation updated for pub install and operational notes.

## [0.2.0] - 2026-01-14

### Added

- `FrameRateDetector` for automatic FPS detection (24/25/30/60 FPS snapping).
- `FrameRateDetector.recordFrameMicros` for monotonic timestamp input and stability gating on low FPS streaks.
- `RRIntervalAnalyzer` for SDRR and mean BPM analysis.
- `FilterResult` for outlier filtering statistics.
- `PPGSignal` fields: `frameRate`, `isFPSStable`, `sdrr`, `isSDRRAcceptable`, `driftRate`, `rejectionRatio`, `rejectedIntervalCount`.

### Changed

- RR interval calculation now uses detected FPS instead of fixed 30 FPS.
- Outlier filtering includes adjacent interval validation and rejection statistics.
- Signal quality assessment can degrade on excessive baseline drift.
- Threshold values are centralized in `PPGConfig`.
- Peak detection uses adaptive prominence based on recent filtered signal variability.
- Quality assessment window size now scales with frame rate.
- RR generation is skipped while `isFPSStable` is false.

### Fixed

- RR intervals were incorrect on non-30 FPS devices (e.g., 60 FPS).

## [0.1.2] - 2026-01-12

### Changed

- Updated `camera` dependency to ^0.11.3.

## [0.1.1] - 2026-01-12

### Changed

- Consolidated example app into single file for better pub.dev visibility.

## [0.1.0] - 2026-01-12

### Added

- Initial release of `flutter_ppg` package
- `FlutterPPGService` - Main orchestrator for PPG signal processing
- `SignalProcessor` - Red channel extraction and bandpass filtering
- `PeakDetector` - Heartbeat detection with minimum distance enforcement
- `SignalQualityAssessor` - Real-time signal quality assessment (Good/Fair/Poor)
- `OutlierFilter` - IQR-based outlier removal for RR intervals
- `RingBuffer` - Efficient sliding window utility
- Example app with:
  - Dual waveform visualization (Raw vs Filtered)
  - Peak markers on filtered signal
  - RR interval history display
  - Real-time SNR and quality stats
  - Start/Stop control with 30-second auto-timeout
# Unreleased

- Add monotonic per-frame timing and constrained quadratic peak interpolation.
- Add `PPGBeatEvent` so filtered RR intervals remain paired with peak times.
- Preserve existing `rrIntervals` and `peakIndices` APIs for compatibility.
- Add configurable central ROI sampling for iOS BGRA8888 camera frames.
