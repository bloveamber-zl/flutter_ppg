/// A fixed-size circular buffer for efficient sliding window operations.
class RingBuffer<T> {
  final List<T?> _buffer;
  final int capacity;
  int _head = 0;
  int _length = 0;

  RingBuffer(this.capacity) : _buffer = List<T?>.filled(capacity, null);

  void add(T element) {
    _buffer[_head] = element;
    _head = (_head + 1) % capacity;
    if (_length < capacity) {
      _length++;
    }
  }

  bool get isFull => _length == capacity;

  int get length => _length;

  /// Returns the elements in insertion order (oldest to newest).
  /// This operation is O(N).
  List<T> get toList {
    if (_length == 0) return [];

    // If not full, head is at next empty slot, but since we started at 0 and increments:
    // With current logic:
    // Add 1: buf[0]=1, head=1, len=1. list: buf[0..1]
    // ...
    // Full: head wraps.

    if (_length < capacity) {
      return _buffer.sublist(0, _length).cast<T>();
    }

    // If full, _head points to the *oldest* element (next to be overwritten).
    // so we start reading from _head to end, then 0 to _head.
    final result = <T>[];
    for (int i = 0; i < capacity; i++) {
      result.add(_buffer[(_head + i) % capacity] as T);
    }
    return result;
  }

  void clear() {
    _head = 0;
    _length = 0;
  }
}
