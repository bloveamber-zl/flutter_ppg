/// Configuration for PPG processing and quality thresholds.
///
/// Units:
/// - Time: milliseconds (ms)
/// - SNR: decibels (dB)
/// - Intensity: camera-derived value (0-255-ish scale)
class PPGConfig {
  /// Fallback sampling rate in FPS (used before FPS stabilizes).
  final int samplingRate;

  /// Sliding window length in seconds.
  final int windowSizeSeconds;

  /// Minimum RR interval (ms). 300ms ≈ 200 BPM.
  final double minRRMs;

  /// Maximum RR interval (ms). 2000ms ≈ 30 BPM.
  final double maxRRMs;

  /// Max adjacent RR change ratio (0.30 = 30%).
  final double maxAdjacentRRChangeRatio;

  /// Maximum acceptable SDRR (ms).
  final double maxAcceptableSDRRMs;

  /// Maximum baseline drift rate (intensity units/sec).
  final double maxDriftRate;

  /// SNR threshold for "good" quality (dB).
  final double minGoodSNR;

  /// SNR threshold for "fair" quality (dB).
  final double minFairSNR;

  /// Minimum intensity for finger presence detection.
  final double fingerPresenceMin;

  /// Maximum intensity for finger presence detection.
  final double fingerPresenceMax;

  /// Fraction of the image width and height sampled for BGRA8888 frames.
  final double roiFraction;

  /// Pixel step used while sampling the BGRA8888 region of interest.
  final int roiSampleStride;

  /// Creates a [PPGConfig] with the specified parameters.
  ///
  /// All parameters have default values suitable for most use cases.
  /// The following constraints must be satisfied (assertions will fail in debug mode):
  /// - [samplingRate] must be > 0
  /// - [windowSizeSeconds] must be > 0
  /// - [minRRMs] must be > 0
  /// - [maxRRMs] must be > [minRRMs]
  /// - [maxAdjacentRRChangeRatio] must be >= 0
  /// - [maxAcceptableSDRRMs] must be >= 0
  /// - [maxDriftRate] must be >= 0
  /// - [fingerPresenceMax] must be > [fingerPresenceMin]
  /// - [minGoodSNR] must be > [minFairSNR]
  /// - [roiFraction] must be > 0 and <= 1
  /// - [roiSampleStride] must be > 0
  const PPGConfig({
    this.samplingRate = 30, // FPS
    this.windowSizeSeconds = 10,
    this.minRRMs = 300.0,
    this.maxRRMs = 2000.0,
    this.maxAdjacentRRChangeRatio = 0.30,
    this.maxAcceptableSDRRMs = 150.0,
    this.maxDriftRate = 50.0,
    this.minGoodSNR = 5.0,
    this.minFairSNR = 0.0,
    this.fingerPresenceMin = 30.0,
    this.fingerPresenceMax = 250.0,
    this.roiFraction = 0.30,
    this.roiSampleStride = 2,
  }) : assert(samplingRate > 0),
       assert(windowSizeSeconds > 0),
       assert(minRRMs > 0),
       assert(maxRRMs > minRRMs),
       assert(maxAdjacentRRChangeRatio >= 0),
       assert(maxAcceptableSDRRMs >= 0),
       assert(maxDriftRate >= 0),
       assert(fingerPresenceMax > fingerPresenceMin),
       assert(minGoodSNR > minFairSNR),
       assert(roiFraction > 0 && roiFraction <= 1),
       assert(roiSampleStride > 0);
}
