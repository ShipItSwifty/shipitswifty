/**
 * Outcomes scripted through the environment so integration tests can drive every role from one project:
 *
 * - `SHIPIT_SAMPLE_FAIL=1`: `always fails when asked` fails.
 * - `SHIPIT_SAMPLE_FLAKY_DIR=<dir>`: `flaky` fails the first time and passes after, remembered by a marker file
 *   (a rerun is a separate process, so a file is the only state it shares).
 */
const fs = require('fs');
const path = require('path');

function firstAttempt(name) {
  const directory = process.env.SHIPIT_SAMPLE_FLAKY_DIR;
  if (!directory) {
    return false;
  }
  const marker = path.join(directory, name);
  if (fs.existsSync(marker)) {
    return false;
  }
  fs.mkdirSync(directory, {recursive: true});
  fs.writeFileSync(marker, '');
  return true;
}

describe('Scripted', () => {
  test('passes', () => {
    expect(1 + 1).toBe(2);
  });

  test.skip('skipped on purpose', () => {});

  test('flaky', () => {
    expect(firstAttempt('flaky')).toBe(false);
  });

  test('always fails when asked', () => {
    expect(process.env.SHIPIT_SAMPLE_FAIL).not.toBe('1');
  });
});
