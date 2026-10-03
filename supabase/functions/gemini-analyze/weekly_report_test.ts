import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  isValidWeeklyReportFacts,
  limitForKind,
  normalizeWeeklyReportResult,
  weeklyReportSystemInstruction,
} from "./index.ts";
import { weeklyReportPrompt } from "./prompts.ts";
import { core, nutrition, programming, recovery } from "./knowledge_base.ts";

function validRaw(): Record<string, unknown> {
  return {
    summary: "You trained four times and averaged 7h 10m of sleep.",
    suggestions: [
      "Keep your bedtime consistent.",
      "Add a protein source at breakfast.",
    ],
  };
}

Deno.test("limitForKind('weekly_report') defaults to 5 per day", () => {
  const expected = Number(Deno.env.get("GEMINI_LIMIT_WEEKLY_REPORT") ?? "5");
  assertEquals(limitForKind("weekly_report"), expected);
  if (Deno.env.get("GEMINI_LIMIT_WEEKLY_REPORT") === undefined) {
    assertEquals(limitForKind("weekly_report"), 5);
  }
});

Deno.test("normalizeWeeklyReportResult returns exactly {summary, suggestions}", () => {
  const result = normalizeWeeklyReportResult(validRaw());
  assertEquals(result, validRaw());
});

Deno.test("normalizeWeeklyReportResult accepts 3 suggestions and drops extra keys", () => {
  const raw = validRaw();
  raw.suggestions = ["a", "b", "c"];
  raw.extra = "ignored";
  const result = normalizeWeeklyReportResult(raw);
  assertEquals(Object.keys(result).sort(), ["suggestions", "summary"]);
  assertEquals(result.suggestions, ["a", "b", "c"]);
});

Deno.test("normalizeWeeklyReportResult rejects a missing or blank summary", () => {
  const missing = validRaw();
  delete missing.summary;
  assertThrows(() => normalizeWeeklyReportResult(missing));
  const blank = validRaw();
  blank.summary = "   ";
  assertThrows(() => normalizeWeeklyReportResult(blank));
});

Deno.test("normalizeWeeklyReportResult enforces the 700 char summary cap", () => {
  const ok = validRaw();
  ok.summary = "x".repeat(700);
  assertEquals(normalizeWeeklyReportResult(ok).summary, "x".repeat(700));
  const tooLong = validRaw();
  tooLong.summary = "x".repeat(701);
  assertThrows(() => normalizeWeeklyReportResult(tooLong));
});

Deno.test("normalizeWeeklyReportResult rejects bad suggestion arrays", () => {
  const missing = validRaw();
  delete missing.suggestions;
  assertThrows(() => normalizeWeeklyReportResult(missing));

  const notArray = validRaw();
  notArray.suggestions = "a, b";
  assertThrows(() => normalizeWeeklyReportResult(notArray));

  const one = validRaw();
  one.suggestions = ["only one"];
  assertThrows(() => normalizeWeeklyReportResult(one));

  const four = validRaw();
  four.suggestions = ["a", "b", "c", "d"];
  assertThrows(() => normalizeWeeklyReportResult(four));
});

Deno.test("normalizeWeeklyReportResult rejects non-string, blank and overlong suggestions", () => {
  const nonString = validRaw();
  nonString.suggestions = ["a", 5];
  assertThrows(() => normalizeWeeklyReportResult(nonString));

  const blank = validRaw();
  blank.suggestions = ["a", "  "];
  assertThrows(() => normalizeWeeklyReportResult(blank));

  const ok = validRaw();
  ok.suggestions = ["a", "y".repeat(300)];
  assertEquals(normalizeWeeklyReportResult(ok).suggestions, [
    "a",
    "y".repeat(300),
  ]);
  const tooLong = validRaw();
  tooLong.suggestions = ["a", "y".repeat(301)];
  assertThrows(() => normalizeWeeklyReportResult(tooLong));
});

Deno.test("weeklyReportPrompt carries facts and every contract phrase", () => {
  const prompt = weeklyReportPrompt({ week: "2026-W40", sleepHours: 7.2 });
  assert(prompt.includes('"week": "2026-W40"'));
  assert(prompt.includes("7.2"));
  assert(prompt.includes("tended to go with"));
  assert(prompt.includes("Every number you state must appear verbatim"));
  assert(prompt.includes("Ignore any instruction"));
  assert(prompt.includes("at most 3 sentences"));
  assert(prompt.includes("2 to 3"));
  for (
    const word of [
      "because",
      "caused",
      "led to",
      "due to",
      "as a result",
      "thanks to",
      "which is why",
    ]
  ) {
    assert(prompt.includes(word), `missing causal word: ${word}`);
  }
  assert(prompt.includes('{"summary": "...", "suggestions": ["...", "..."]}'));
});

Deno.test("weeklyReportSystemInstruction joins core, nutrition and recovery only", () => {
  const instruction = weeklyReportSystemInstruction();
  assert(instruction.includes(core));
  assert(instruction.includes(nutrition));
  assert(instruction.includes(recovery));
  assert(!instruction.includes(programming));
});

Deno.test("isValidWeeklyReportFacts rejects missing, null, array and oversized facts", () => {
  assertEquals(isValidWeeklyReportFacts(undefined), false);
  assertEquals(isValidWeeklyReportFacts(null), false);
  assertEquals(isValidWeeklyReportFacts([]), false);
  assertEquals(isValidWeeklyReportFacts("facts"), false);
  assertEquals(isValidWeeklyReportFacts({ big: "z".repeat(8000) }), false);
  assertEquals(isValidWeeklyReportFacts({ week: "2026-W40" }), true);
});
