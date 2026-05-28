import {
  formatCount,
  isEven,
  clamp,
  pluralize,
  sum,
  isValidCount,
} from '../utils/counterUtils';

describe('formatCount', () => {
  it('formats zero', () => {
    expect(formatCount(0)).toBe('0');
  });

  it('formats a positive integer', () => {
    expect(formatCount(42)).toBe('42');
  });

  it('formats a negative integer', () => {
    expect(formatCount(-7)).toBe('-7');
  });

  it('formats a large number', () => {
    expect(formatCount(1_000_000)).toBe('1000000');
  });
});

describe('isEven', () => {
  it('returns true for zero', () => {
    expect(isEven(0)).toBe(true);
  });

  it('returns true for positive even', () => {
    expect(isEven(4)).toBe(true);
  });

  it('returns false for positive odd', () => {
    expect(isEven(3)).toBe(false);
  });

  it('returns true for negative even', () => {
    expect(isEven(-2)).toBe(true);
  });

  it('returns false for negative odd', () => {
    expect(isEven(-5)).toBe(false);
  });
});

describe('clamp', () => {
  it('returns value when within range', () => {
    expect(clamp(5, 0, 10)).toBe(5);
  });

  it('returns min when value is below range', () => {
    expect(clamp(-3, 0, 10)).toBe(0);
  });

  it('returns max when value exceeds range', () => {
    expect(clamp(15, 0, 10)).toBe(10);
  });

  it('returns min when value equals min', () => {
    expect(clamp(0, 0, 10)).toBe(0);
  });

  it('returns max when value equals max', () => {
    expect(clamp(10, 0, 10)).toBe(10);
  });

  it('handles single-value range', () => {
    expect(clamp(5, 3, 3)).toBe(3);
  });
});

describe('pluralize', () => {
  it('returns singular for count of 1', () => {
    expect(pluralize(1, 'tap', 'taps')).toBe('tap');
  });

  it('returns plural for count of 0', () => {
    expect(pluralize(0, 'tap', 'taps')).toBe('taps');
  });

  it('returns plural for count greater than 1', () => {
    expect(pluralize(5, 'tap', 'taps')).toBe('taps');
  });

  it('returns plural for negative values', () => {
    expect(pluralize(-1, 'item', 'items')).toBe('items');
  });
});

describe('sum', () => {
  it('returns 0 for empty array', () => {
    expect(sum([])).toBe(0);
  });

  it('sums a single element', () => {
    expect(sum([7])).toBe(7);
  });

  it('sums multiple elements', () => {
    expect(sum([1, 2, 3, 4])).toBe(10);
  });

  it('sums with negative values', () => {
    expect(sum([10, -3, 5])).toBe(12);
  });
});

describe('isValidCount', () => {
  it('returns true for zero', () => {
    expect(isValidCount(0)).toBe(true);
  });

  it('returns true for positive integer', () => {
    expect(isValidCount(5)).toBe(true);
  });

  it('returns false for negative integer', () => {
    expect(isValidCount(-1)).toBe(false);
  });

  it('returns false for float', () => {
    expect(isValidCount(1.5)).toBe(false);
  });

  it('returns false for NaN', () => {
    expect(isValidCount(NaN)).toBe(false);
  });

  it('returns false for Infinity', () => {
    expect(isValidCount(Infinity)).toBe(false);
  });
});
