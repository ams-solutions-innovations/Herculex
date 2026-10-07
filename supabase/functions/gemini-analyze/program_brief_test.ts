import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { normalizeProgramBriefResult } from "./index.ts";

// Deep-clonable valid fixture — every test mutates its own copy so cases
// never leak state into each other (mirrors usage_test.ts's per-test setup).
function validRaw(): Record<string, unknown> {
  return {
    splitType: "upper_lower",
    periodizationModel: "linear",
    dayRoles: [
      {
        dayIndex: 0,
        role: "intensity",
        focus: "Upper body",
        rationale: "Heaviest compound work happens while the lifter is freshest.",
      },
      {
        dayIndex: 1,
        role: "volume",
        focus: "Lower body",
        rationale: "Accumulates quality volume for the posterior chain.",
      },
    ],
    musclePriorities: [
      {
        muscleId: "chest",
        priority: "high",
        confidence: 0.8,
        rationale: "Target photo shows more chest development than current.",
        uncertainties: ["Lighting limits confidence."],
      },
    ],
    phaseIntent: "Build a strength base before a hypertrophy-focused block.",
  };
}

Deno.test("normalizeProgramBriefResult returns a normalized object for a fully valid raw object", () => {
  const result = normalizeProgramBriefResult(validRaw());

  assertEquals(result, {
    splitType: "upper_lower",
    periodizationModel: "linear",
    dayRoles: [
      {
        dayIndex: 0,
        role: "intensity",
        focus: "Upper body",
        rationale: "Heaviest compound work happens while the lifter is freshest.",
      },
      {
        dayIndex: 1,
        role: "volume",
        focus: "Lower body",
        rationale: "Accumulates quality volume for the posterior chain.",
      },
    ],
    musclePriorities: [
      {
        muscleId: "chest",
        priority: "high",
        confidence: 0.8,
        rationale: "Target photo shows more chest development than current.",
        uncertainties: ["Lighting limits confidence."],
      },
    ],
    phaseIntent: "Build a strength base before a hypertrophy-focused block.",
  });
});

Deno.test("normalizeProgramBriefResult throws — never returns — on an unknown splitType", () => {
  const raw = validRaw();
  raw.splitType = "made_up_split";

  assertThrows(
    () => normalizeProgramBriefResult(raw),
    Error,
    "Unknown splitType",
  );
});

Deno.test("normalizeProgramBriefResult throws on a dayRoles[] entry with an unknown role", () => {
  const raw = validRaw();
  (raw.dayRoles as Record<string, unknown>[])[0].role = "peak";

  assertThrows(
    () => normalizeProgramBriefResult(raw),
    Error,
    "Unknown dayRoles[].role",
  );
});

Deno.test("normalizeProgramBriefResult throws on a musclePriorities[] entry with an unknown muscleId", () => {
  const raw = validRaw();
  (raw.musclePriorities as Record<string, unknown>[])[0].muscleId = "forearm";

  assertThrows(
    () => normalizeProgramBriefResult(raw),
    Error,
    "Unknown canonical muscle id",
  );
});

Deno.test("normalizeProgramBriefResult throws when dayRoles is missing entirely", () => {
  const raw = validRaw();
  delete raw.dayRoles;

  assertThrows(
    () => normalizeProgramBriefResult(raw),
    Error,
    "Program brief has no dayRoles",
  );
});

Deno.test("normalizeProgramBriefResult throws when musclePriorities is missing entirely", () => {
  const raw = validRaw();
  delete raw.musclePriorities;

  assertThrows(
    () => normalizeProgramBriefResult(raw),
    Error,
    "Program brief has no musclePriorities",
  );
});
