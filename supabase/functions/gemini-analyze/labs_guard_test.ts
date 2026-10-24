import { labsPrompt, sanitizeLabsFacts } from "./labs_guard.ts";
function assert(value: unknown): asserts value {
  if (!value) throw new Error("Assertion failed");
}
Deno.test("Labs aggregate contract excludes raw logs, names, notes and injected keys", () => {
  const facts = sanitizeLabsFacts({
    notes: "private",
    findings: [{
      category: "sleep",
      support: "Collecting data",
      observedDays: 4,
      raw: [1, 2],
      name: "private",
      before: null,
      after: null,
      delta: null,
      q: null,
      coverage: .2,
    }],
  });
  assert(facts);
  assert(!JSON.stringify(facts).includes("private"));
  assert(!JSON.stringify(facts).includes("raw"));
  assert(labsPrompt(facts).includes("observational"));
});
Deno.test("Labs rejects unknown categories, support levels and nonfinite numbers", () => {
  assert(
    sanitizeLabsFacts({
      findings: [{ category: "medical", support: "Collecting data" }],
    }) === null,
  );
  assert(
    sanitizeLabsFacts({
      findings: [{ category: "sleep", support: "Proven cause" }],
    }) === null,
  );
  assert(
    sanitizeLabsFacts({
      findings: [{
        category: "sleep",
        support: "Collecting data",
        before: Infinity,
      }],
    }) === null,
  );
  assert(
    sanitizeLabsFacts({ findings: Array.from({ length: 13 }, () => ({})) }) ===
      null,
  );
});
