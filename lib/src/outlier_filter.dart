import 'models/filter_result.dart';
import 'models/ppg_config.dart';

/// Filters RR intervals to remove artifacts and noise.
class OutlierFilter {
  static const _minimumStableRunLength = 3;

  /// Minimum acceptable RR interval in milliseconds.
  /// Values below this are considered physiologically implausible and rejected.
  final double minRRMs;

  /// Maximum acceptable RR interval in milliseconds.
  /// Values above this are considered physiologically implausible and rejected.
  final double maxRRMs;

  /// Maximum allowed change ratio between adjacent RR intervals (0.0-1.0).
  /// Sudden changes exceeding this ratio are considered artifacts and rejected.
  /// For example, 0.30 means a 30% change is the maximum allowed.
  final double maxAdjacentChangeRatio;

  /// Creates an [OutlierFilter] with the specified thresholds.
  ///
  /// The following constraints must be satisfied (assertions will fail in debug mode):
  /// - [minRRMs] must be > 0
  /// - [maxRRMs] must be > [minRRMs]
  /// - [maxAdjacentChangeRatio] must be >= 0
  const OutlierFilter({
    required this.minRRMs,
    required this.maxRRMs,
    required this.maxAdjacentChangeRatio,
  }) : assert(minRRMs > 0),
       assert(maxRRMs > minRRMs),
       assert(maxAdjacentChangeRatio >= 0);

  /// Creates an [OutlierFilter] from a [PPGConfig].
  ///
  /// Uses the RR interval thresholds and change ratio from the configuration.
  factory OutlierFilter.fromConfig(PPGConfig config) {
    return OutlierFilter(
      minRRMs: config.minRRMs,
      maxRRMs: config.maxRRMs,
      maxAdjacentChangeRatio: config.maxAdjacentRRChangeRatio,
    );
  }

  /// Filters outliers from RR intervals using Interquartile Range (IQR) method
  /// and physiological limits.
  ///
  /// Applies multiple filtering stages:
  /// 1. Physiological filter (removes values outside [minRRMs, maxRRMs])
  /// 2. Adjacent interval validation (removes sudden changes > maxAdjacentChangeRatio)
  /// 3. IQR method (removes statistical outliers)
  ///
  /// [rrIntervals] - List of RR intervals in milliseconds to filter.
  /// Returns a clean list of RR intervals that passed all filtering stages.
  List<double> filterOutliers(List<double> rrIntervals) {
    return filterOutliersWithStats(rrIntervals).intervals;
  }

  /// Filters outliers and returns filtering statistics.
  ///
  /// Same filtering process as [filterOutliers], but also returns statistics
  /// about how many intervals were rejected and the rejection ratio.
  ///
  /// [rrIntervals] - List of RR intervals in milliseconds to filter.
  /// Returns a [FilterResult] containing filtered intervals and statistics.
  FilterResult filterOutliersWithStats(List<double> rrIntervals) {
    final result = filterIndexed(rrIntervals, (value) => value);
    return FilterResult(
      intervals: result.values,
      totalInput: result.totalInput,
      rejectedCount: result.rejectedCount,
      rejectionRatio: result.rejectionRatio,
    );
  }

  /// Applies all RR filters while preserving each accepted source value.
  IndexedFilterResult<T> filterIndexed<T>(
    List<T> values,
    double Function(T value) intervalOf,
  ) {
    if (values.isEmpty) {
      return const IndexedFilterResult(
        values: [],
        acceptedIndices: [],
        totalInput: 0,
        rejectedCount: 0,
        rejectionRatio: 0.0,
      );
    }

    var accepted = <({T value, int index})>[];
    for (var index = 0; index < values.length; index++) {
      final interval = intervalOf(values[index]);
      if (interval >= minRRMs && interval <= maxRRMs) {
        accepted.add((value: values[index], index: index));
      }
    }

    if (accepted.length >= 2) {
      final stableRunStart = _findStableRunStart(accepted, intervalOf);
      final adjacent = <({T value, int index})>[];
      var nextIndex = 1;
      if (stableRunStart >= 0) {
        adjacent.addAll(
          accepted.skip(stableRunStart).take(_minimumStableRunLength),
        );
        nextIndex = stableRunStart + _minimumStableRunLength;
      } else {
        adjacent.add(accepted.first);
      }
      for (final candidate in accepted.skip(nextIndex)) {
        final recent = adjacent
            .skip(
              (adjacent.length - _minimumStableRunLength).clamp(
                0,
                adjacent.length,
              ),
            )
            .map((item) => intervalOf(item.value))
            .toList();
        final baseline = _median(recent);
        final current = intervalOf(candidate.value);
        if ((current - baseline).abs() / baseline <= maxAdjacentChangeRatio) {
          adjacent.add(candidate);
        }
      }
      accepted = adjacent;
    }

    if (accepted.length >= 4) {
      final sorted = accepted.map((item) => intervalOf(item.value)).toList()
        ..sort();
      final q1 = _percentile(sorted, 25);
      final q3 = _percentile(sorted, 75);
      final iqr = q3 - q1;
      final lowerBound = q1 - 1.5 * iqr;
      final upperBound = q3 + 1.5 * iqr;
      accepted = accepted.where((item) {
        final interval = intervalOf(item.value);
        return interval >= lowerBound && interval <= upperBound;
      }).toList();
    }

    final rejected = values.length - accepted.length;
    return IndexedFilterResult(
      values: accepted.map((item) => item.value).toList(),
      acceptedIndices: accepted.map((item) => item.index).toList(),
      totalInput: values.length,
      rejectedCount: rejected,
      rejectionRatio: rejected / values.length,
    );
  }

  int _findStableRunStart<T>(
    List<({T value, int index})> values,
    double Function(T value) intervalOf,
  ) {
    if (values.length < _minimumStableRunLength) return -1;

    for (
      var start = 0;
      start <= values.length - _minimumStableRunLength;
      start++
    ) {
      final run = values
          .skip(start)
          .take(_minimumStableRunLength)
          .map((item) => intervalOf(item.value))
          .toList();
      final baseline = _median(run);
      final isStable = run.every(
        (interval) =>
            (interval - baseline).abs() / baseline <= maxAdjacentChangeRatio,
      );
      if (isStable) return start;
    }
    return -1;
  }

  double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  /// Applies the Interquartile Range (IQR) method to filter outliers.
  ///
  /// Outliers are defined as values falling outside [Q1 - 1.5*IQR, Q3 + 1.5*IQR],
  /// where Q1 is the first quartile, Q3 is the third quartile, and IQR = Q3 - Q1.
  ///
  /// [data] - List of values to filter.
  /// Returns a list containing only values within the acceptable range.
  List<double> applyIQRMethod(List<double> data) {
    if (data.isEmpty) return [];

    final sorted = List<double>.from(data)..sort();
    final q1 = _percentile(sorted, 25);
    final q3 = _percentile(sorted, 75);
    final iqr = q3 - q1;

    final lowerBound = q1 - 1.5 * iqr;
    final upperBound = q3 + 1.5 * iqr;

    return data.where((val) => val >= lowerBound && val <= upperBound).toList();
  }

  double _percentile(List<double> sortedData, int percentile) {
    if (sortedData.isEmpty) return 0.0;

    final n = sortedData.length;
    final index = (percentile / 100) * (n - 1);
    final lower = index.floor();
    final upper = index.ceil();

    if (lower == upper) {
      return sortedData[lower];
    }

    final weight = index - lower;
    return sortedData[lower] * (1 - weight) + sortedData[upper] * weight;
  }
}
