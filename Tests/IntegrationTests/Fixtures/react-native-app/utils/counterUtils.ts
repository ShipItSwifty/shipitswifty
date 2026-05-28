export function formatCount(count: number): string {
  return count.toString();
}

export function isEven(n: number): boolean {
  return n % 2 === 0;
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

export function pluralize(
  count: number,
  singular: string,
  plural: string,
): string {
  return count === 1 ? singular : plural;
}

export function sum(values: number[]): number {
  return values.reduce((acc, v) => acc + v, 0);
}

export function isValidCount(n: number): boolean {
  return Number.isInteger(n) && n >= 0;
}
