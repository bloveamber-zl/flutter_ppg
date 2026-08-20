import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ppg/src/utils/ring_buffer.dart';

void main() {
  group('RingBuffer', () {
    test('works as circular buffer', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      expect(buffer.toList, [1, 2]);
      expect(buffer.length, 2);
      expect(buffer.isFull, false);

      buffer.add(3);
      expect(buffer.toList, [1, 2, 3]);
      expect(buffer.isFull, true);

      buffer.add(4); // Should overwrite 1
      expect(buffer.toList, [2, 3, 4]); // Oldest first
      expect(buffer.length, 3);

      buffer.add(5); // Should overwrite 2
      expect(buffer.toList, [3, 4, 5]);
    });

    test('clear resets buffer', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      buffer.clear();
      expect(buffer.toList, isEmpty);
      expect(buffer.length, 0);
      expect(buffer.isFull, false);
    });
  });
}
