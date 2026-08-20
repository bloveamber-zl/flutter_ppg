/// Result of RR interval filtering with statistics.
///
/// Contains the filtered RR intervals and statistics about the filtering process,
/// including how many intervals were rejected as outliers.
class FilterResult {
  /// Filtered RR intervals in milliseconds that passed the outlier detection.
  final List<double> intervals;

  /// Total number of RR intervals before filtering.
  final int totalInput;

  /// Number of RR intervals rejected as outliers during filtering.
  final int rejectedCount;

  /// Ratio of rejected intervals to total input (0.0-1.0).
  /// Higher values indicate more noise or artifacts in the signal.
  final double rejectionRatio;

  /// Creates a [FilterResult] with the specified filtering statistics.
  ///
  /// [intervals] - Filtered RR intervals that passed outlier detection.
  /// [totalInput] - Total number of RR intervals before filtering.
  /// [rejectedCount] - Number of intervals rejected as outliers.
  /// [rejectionRatio] - Ratio of rejected intervals (0.0-1.0).
  const FilterResult({
    required this.intervals,
    required this.totalInput,
    required this.rejectedCount,
    required this.rejectionRatio,
  });

  /// Returns true if rejection ratio is acceptable (<20%).
  bool get isQualityAcceptable => rejectionRatio < 0.20;
}

/// Generic filtering result that preserves accepted source objects.
class IndexedFilterResult<T> {
  final List<T> values;
  final List<int> acceptedIndices;
  final int totalInput;
  final int rejectedCount;
  final double rejectionRatio;

  const IndexedFilterResult({
    required this.values,
    required this.acceptedIndices,
    required this.totalInput,
    required this.rejectedCount,
    required this.rejectionRatio,
  });
}
