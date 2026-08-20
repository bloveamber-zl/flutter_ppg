import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ppg/src/outlier_filter.dart';
import 'package:flutter_ppg/src/models/ppg_config.dart';

void main() {
  group('OutlierFilter', () {
    final filter = OutlierFilter.fromConfig(const PPGConfig());

    test('filterOutliers removes physiological impossible values', () {
      final input = [50.0, 800.0, 900.0, 2500.0, 1000.0];
      // 50 (too low, >300), 2500 (too high, <2000)
      final output = filter.filterOutliers(input);
      expect(output, containsAllInOrder([800.0, 900.0, 1000.0]));
      expect(output.length, 3);
    });

    test('applyIQRMethod removes statistical outliers', () {
      // Median ~100. Outlier 500.
      final input = [98.0, 99.0, 100.0, 101.0, 102.0, 500.0];

      // Sorted: 98, 99, 100, 101, 102, 500
      // Q1 (25%): index 1.25 -> mix of 99 and 100? or index based.
      // Q3 (75%): index 3.75 -> mix of 101 and 102?

      // Let's trust the calc. 1.5*IQR usually keeps the cluster.

      final output = filter.applyIQRMethod(input);
      expect(output, containsAll([98.0, 99.0, 100.0, 101.0, 102.0]));
      expect(output, isNot(contains(500.0)));
    });

    test('adjacent RR validation accepts gradual changes', () {
      final rr = [800.0, 820.0, 840.0, 860.0, 880.0];
      final result = filter.filterOutliersWithStats(rr);
      expect(result.intervals.length, equals(5));
      expect(result.rejectionRatio, equals(0.0));
    });

    test('adjacent RR validation rejects impossible jumps', () {
      final rr = [800.0, 400.0, 850.0];
      final result = filter.filterOutliersWithStats(rr);
      expect(result.rejectedCount, greaterThan(0));
    });

    test('stable RR run replaces an initial placement transient', () {
      final rr = [522.0, 845.0, 850.0, 840.0];

      final result = filter.filterOutliersWithStats(rr);

      expect(result.intervals, [845.0, 850.0, 840.0]);
      expect(result.rejectedCount, 1);
      expect(result.rejectionRatio, 0.25);
    });

    test('rejects PhiBui example case', () {
      final rr = [850.0, 420.0, 1200.0, 650.0, 350.0, 950.0, 510.0, 1100.0];
      final result = filter.filterOutliersWithStats(rr);
      expect(result.rejectionRatio, greaterThan(0.20));
      expect(result.isQualityAcceptable, isFalse);
    });

    test('filterIndexed preserves accepted source identity', () {
      final values = [
        (id: 'a', rr: 800.0),
        (id: 'noise', rr: 200.0),
        (id: 'b', rr: 820.0),
        (id: 'c', rr: 840.0),
      ];

      final result = filter.filterIndexed(values, (value) => value.rr);

      expect(result.values.map((value) => value.id), ['a', 'b', 'c']);
      expect(result.acceptedIndices, [0, 2, 3]);
      expect(result.rejectedCount, 1);
    });
  });
}
