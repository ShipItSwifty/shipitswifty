import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Outcomes scripted through the environment so integration tests can drive every role from one project:
///
/// * `SHIPIT_SAMPLE_FAIL=1`: `always fails when asked` fails.
/// * `SHIPIT_SAMPLE_FLAKY_DIR=<dir>`: `flaky` fails the first time and passes after, remembered by a marker file
///   (a rerun is a separate process, so a file is the only state it shares).
bool _firstAttempt(String name) {
  final directory = Platform.environment['SHIPIT_SAMPLE_FLAKY_DIR'];
  if (directory == null) return false;
  final marker = File('$directory/$name');
  if (marker.existsSync()) return false;
  marker.createSync(recursive: true);
  return true;
}

void main() {
  group('Scripted', () {
    test('passes', () => expect(1 + 1, 2));

    test('skipped on purpose', () {}, skip: 'skipped on purpose');

    test('flaky', () {
      expect(_firstAttempt('flaky'), isFalse, reason: 'fails on the first attempt only');
    });

    test('always fails when asked', () {
      expect(Platform.environment['SHIPIT_SAMPLE_FAIL'], isNot('1'), reason: 'asked to fail');
    });
  });
}
