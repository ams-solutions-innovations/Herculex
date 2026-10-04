/// Weekly report guards (Phase 29, WR-04 / WR-05).
///
/// Pure TS, no imports from index.ts (avoids a cycle). Two jobs:
///  1. `sanitizeWeeklyReportFacts` - the server never trusts client
///     sanitising: strip control chars, cap strings, bound depth and size.
///  2. `assertNumbersInFacts` - every number the model states must occur in
///     the facts it was given.
///
/// The number extraction below is MIRRORED in Dart
/// (lib/features/weekly_report/domain/weekly_narrative.dart). Both are
/// exercised by test/fixtures/weekly_report_number_cases.json. Change one,
/// change the other.

export const maxFactsChars = 8000;
export const maxStringChars = 120;
export const maxDepth = 6;
export const maxNodes = 400;
/// Integers 0..60 are always allowed (day counts, week numbers, small counts).
export const alwaysAllowedMax = 60;

/// Keys whose values are dates; their digits never count as facts.
export const dateKeys: ReadonlySet<string> = new Set([
  "weekStartIso",
  "weekEndIso",
  "windowEnd",
  "start",
  "end",
]);

const controlChars = new RegExp(
  "[\u0000-\u001F\u007F-\u009F\u2028\u2029]+",
  "g",
);

function cleanString(value: string): string {
  const cleaned = value.replace(controlChars, " ").replace(/\s+/g, " ").trim();
  const points = Array.from(cleaned);
  if (points.length <= maxStringChars) return cleaned;
  return points.slice(0, maxStringChars).join("").trim();
}

/// Returns a sanitised copy of [facts], or null when it is not acceptable.
export function sanitizeWeeklyReportFacts(
  facts: unknown,
): Record<string, unknown> | null {
  if (!facts || typeof facts !== "object" || Array.isArray(facts)) return null;
  let nodes = 0;
  let failed = false;

  const walk = (value: unknown, depth: number): unknown => {
    if (failed) return null;
    nodes++;
    if (nodes > maxNodes || depth > maxDepth) {
      failed = true;
      return null;
    }
    if (value === null || typeof value === "boolean") return value;
    if (typeof value === "number") {
      if (!Number.isFinite(value)) failed = true;
      return value;
    }
    if (typeof value === "string") return cleanString(value);
    if (Array.isArray(value)) return value.map((v) => walk(v, depth + 1));
    if (typeof value === "object") {
      const out: Record<string, unknown> = {};
      for (const [key, v] of Object.entries(value as Record<string, unknown>)) {
        out[cleanString(key)] = walk(v, depth + 1);
      }
      return out;
    }
    failed = true;
    return null;
  };

  const result = walk(facts, 0);
  if (failed) return null;
  try {
    if (JSON.stringify(result).length > maxFactsChars) return null;
  } catch {
    return null;
  }
  return result as Record<string, unknown>;
}

// "2,150" / "2 150": 1-3 digits then exactly-3-digit groups. "3, 4" and
// "1,20" do not match the grouped form and stay separate numbers.
const numberPattern = /\d{1,3}(?:[, ]\d{3})+(?:\.\d+)?(?!\d)|\d+(?:\.\d+)?/g;

/// Canonical (absolute, Number()-normalised) numbers in [text], in order.
export function extractNumbers(text: string): number[] {
  const out: number[] = [];
  for (const match of text.matchAll(numberPattern)) {
    const n = Number(match[0].replace(/[, ]/g, ""));
    if (Number.isFinite(n)) out.push(n);
  }
  return out;
}

const isoDate = /^\d{4}-\d{2}-\d{2}$/;

/// Every number that may legitimately be quoted from [facts].
export function collectFactNumbers(facts: unknown): Set<number> {
  const out = new Set<number>();
  const walk = (value: unknown, key: string | null) => {
    if (key !== null && dateKeys.has(key)) return;
    if (typeof value === "number") {
      if (Number.isFinite(value)) out.add(Math.abs(value));
    } else if (typeof value === "string") {
      if (isoDate.test(value.trim())) return;
      for (const n of extractNumbers(value)) out.add(n);
    } else if (Array.isArray(value)) {
      for (const v of value) walk(v, null);
    } else if (value && typeof value === "object") {
      for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
        walk(v, k);
      }
    }
  };
  walk(facts, null);
  return out;
}

/// Throws naming the first number in summary/suggestions that is neither in
/// the facts nor an always-allowed integer 0..60.
export function assertNumbersInFacts(
  summary: string,
  suggestions: string[],
  facts: unknown,
): void {
  const allowed = collectFactNumbers(facts);
  for (const text of [summary, ...suggestions]) {
    for (const n of extractNumbers(text)) {
      const small = Number.isInteger(n) && n >= 0 && n <= alwaysAllowedMax;
      if (!small && !allowed.has(n)) {
        throw new Error(`Number not in facts: ${n}`);
      }
    }
  }
}
