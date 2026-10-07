import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  imageConsentError,
  normalizeDreamPhysiqueResult,
  normalizePhysiqueCheckinResult,
} from "./index.ts";

const consent = {
  granted: true,
  version: "dream_physique_images_v1",
};

Deno.test("imageConsentError rejects physique_checkin without consent", () => {
  assert(imageConsentError({ kind: "physique_checkin" }) !== null);
  assert(
    imageConsentError({
      kind: "physique_checkin",
      privacyConsent: { granted: false, version: consent.version },
    }) !== null,
  );
  assert(
    imageConsentError({
      kind: "physique_checkin",
      privacyConsent: { granted: true, version: "old" },
    }) !== null,
  );
});

Deno.test("imageConsentError accepts valid consent and ignores other kinds", () => {
  assertEquals(
    imageConsentError({ kind: "physique_checkin", privacyConsent: consent }),
    null,
  );
  assertEquals(imageConsentError({ kind: "food_photo" }), null);
  assertEquals(imageConsentError({ kind: "program_brief" }), null);
  assertEquals(
    imageConsentError({ kind: "dream_physique" }),
    "Confirm the current Dream Physique photo privacy notice before uploading images.",
  );
});

Deno.test("normalizePhysiqueCheckinResult whitelists keys and clamps the band", () => {
  const out = normalizePhysiqueCheckinResult({
    directionBand: { low: 1.8, high: -0.4 },
    confidence: "high",
    reason: "Looks leaner.",
    limitations: ["a", "b", "c", "d"],
    percent: 12,
    probability: 0.9,
    experienceLevel: "advanced",
  });
  assertEquals(Object.keys(out).sort(), [
    "confidence",
    "directionBand",
    "limitations",
    "reason",
  ]);
  assertEquals(out.directionBand, { low: -0.4, high: 1 });
  assertEquals((out.limitations as string[]).length, 3);
});

Deno.test("normalizePhysiqueCheckinResult strips percentages and fails closed", () => {
  const out = normalizePhysiqueCheckinResult({
    directionBand: { low: 0, high: 0.5 },
    confidence: "certain",
    reason: "about 12% leaner, roughly 5 percent less bloat",
    limitations: ["lighting differs 100%", 5],
  });
  assertEquals(out.reason, "about leaner, roughly less bloat");
  assertEquals(out.confidence, "low");
  assertEquals(out.limitations, ["lighting differs"]);
  assertEquals(
    normalizePhysiqueCheckinResult({
      directionBand: { low: 0, high: 0 },
      reason: "ok",
      limitations: "nope",
    }).limitations,
    [],
  );
});

Deno.test("normalizePhysiqueCheckinResult throws on bad input", () => {
  assertThrows(() =>
    normalizePhysiqueCheckinResult({ reason: "x", confidence: "low" })
  );
  assertThrows(() =>
    normalizePhysiqueCheckinResult({
      directionBand: { low: "a", high: 1 },
      reason: "x",
    })
  );
  assertThrows(() =>
    normalizePhysiqueCheckinResult({
      directionBand: { low: 0, high: 1 },
      reason: "50%",
    })
  );
});

const dreamBase = {
  estimatedMonths: 8,
  timeframeRange: "6 - 9 months",
  weightChangeKg: -2,
  leanMuscleGainKg: 3,
  fatLossKg: 5,
  targetBfPercent: 11,
  currentEstimatedBf: 17,
  musclePriorities: [{ group: "Chest", priority: "high", focus: "volume" }],
  nutritionStrategy: "n",
  trainingAdvice: "t",
  overallAssessment: "o",
  targetAestheticStyle: "s",
};

Deno.test("normalizeDreamPhysiqueResult passes valid BF range and confidence", () => {
  const out = normalizeDreamPhysiqueResult({
    ...dreamBase,
    currentBfRangeMin: 15,
    currentBfRangeMax: 20,
    assessmentConfidence: "low",
  });
  assertEquals(out.currentBfRangeMin, 15);
  assertEquals(out.currentBfRangeMax, 20);
  assertEquals(out.assessmentConfidence, "low");
});

Deno.test("normalizeDreamPhysiqueResult omits invalid or absent confidence fields", () => {
  for (
    const extra of [
      {},
      { currentBfRangeMin: 20, currentBfRangeMax: 15 },
      { currentBfRangeMin: 1, currentBfRangeMax: 15 },
      { currentBfRangeMin: 15, currentBfRangeMax: 90 },
      { currentBfRangeMin: 15 },
      { assessmentConfidence: "sure" },
    ]
  ) {
    const out = normalizeDreamPhysiqueResult({ ...dreamBase, ...extra });
    assertEquals("currentBfRangeMin" in out, false);
    assertEquals("currentBfRangeMax" in out, false);
    assertEquals("assessmentConfidence" in out, false);
  }
});
