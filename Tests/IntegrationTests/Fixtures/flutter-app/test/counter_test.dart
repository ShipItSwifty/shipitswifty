import 'package:flutter_test/flutter_test.dart';
import 'package:shipit_flutter_test/counter.dart';

void main() {
  group('Counter', () {
    late Counter counter;

    setUp(() {
      counter = Counter();
    });

    test('starts at zero', () {
      expect(counter.count, equals(0));
    });

    test('increments count', () {
      counter.increment();
      expect(counter.count, equals(1));
    });

    test('increments multiple times', () {
      counter.increment();
      counter.increment();
      counter.increment();
      expect(counter.count, equals(3));
    });

    test('decrements count', () {
      counter.increment();
      counter.increment();
      counter.decrement();
      expect(counter.count, equals(1));
    });

    test('decrement does not go below zero', () {
      counter.decrement();
      expect(counter.count, equals(0));
    });

    test('reset returns count to zero', () {
      counter.increment();
      counter.increment();
      counter.increment();
      counter.reset();
      expect(counter.count, equals(0));
    });

    test('reset from zero stays at zero', () {
      counter.reset();
      expect(counter.count, equals(0));
    });

    test('increment after reset works correctly', () {
      counter.increment();
      counter.increment();
      counter.reset();
      counter.increment();
      expect(counter.count, equals(1));
    });

    test('decrement after increment reaches zero correctly', () {
      counter.increment();
      counter.decrement();
      expect(counter.count, equals(0));
    });

    test('mixed operations maintain correct state', () {
      counter.increment(); // 1
      counter.increment(); // 2
      counter.decrement(); // 1
      counter.increment(); // 2
      counter.increment(); // 3
      counter.reset();     // 0
      counter.increment(); // 1
      expect(counter.count, equals(1));
    });
  });
}
