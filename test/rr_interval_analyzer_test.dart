import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ppg/src/rr_interval_analyzer.dart';
import 'package:flutter_ppg/src/models/ppg_config.dart';

void main() {
  group('RRIntervalAnalyzer', () {
    test('calculates SDRR for stable signal', () {
      final analyzer = RRIntervalAnalyzer.fromConfig(const PPGConfig());
      final rr = [850.0, 820.0, 880.0, 800.0, 840.0, 860.0, 810.0, 870.0];

      final sdrr = analyzer.calculateSDRR(rr);
      expect(sdrr, lessThan(150.0));
      expect(analyzer.isSDRRAcceptable(rr), isTrue);
    });

    test('flags noisy signal with high SDRR', () {
      final analyzer = RRIntervalAnalyzer.fromConfig(const PPGConfig());
      final rr = [850.0, 420.0, 1200.0, 650.0, 350.0, 950.0, 510.0, 1100.0];

      final sdrr = analyzer.calculateSDRR(rr);
      expect(sdrr, greaterThan(150.0));
      expect(analyzer.isSDRRAcceptable(rr), isFalse);
    });

    test('calculates mean BPM correctly', () {
      final analyzer = RRIntervalAnalyzer.fromConfig(const PPGConfig());
      final rr = [850.0, 820.0, 880.0, 800.0, 840.0, 860.0, 810.0, 870.0];

      final bpm = analyzer.calculateMeanBPM(rr);
      expect(bpm, closeTo(71.0, 1.0));
    });
  });
}
