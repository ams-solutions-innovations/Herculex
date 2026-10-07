import { assertEquals } from "jsr:@std/assert@1";
import { bumpUsage, limitForKind } from "./index.ts";

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// `bumpUsage()` reads SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY fresh on every
// call (not as module-load-time constants) specifically so a test can set
// them here, at test-run time, and have them take effect.
Deno.env.set("SUPABASE_URL", "https://example.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key");

const dailyLimit = Number(Deno.env.get("GEMINI_DAILY_LIMIT") ?? "50");
const dreamPhysiqueLimit = Number(
  Deno.env.get("GEMINI_LIMIT_DREAM_PHYSIQUE") ?? "10",
);

Deno.test("bumpUsage returns the RPC's disallowed result verbatim on a 200 response", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = (() => {
      return Promise.resolve(
        jsonResponse(200, { allowed: false, used: 30, limit: 30 }),
      );
    }) as typeof fetch;

    const result = await bumpUsage("user-1", "food_photo", 30);

    assertEquals(result, { allowed: false, used: 30, limit: 30 });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("bumpUsage fails closed with a Herculex-branded error after exactly one retry", async () => {
  const originalFetch = globalThis.fetch;
  try {
    let callCount = 0;
    globalThis.fetch = (() => {
      callCount += 1;
      return Promise.resolve(jsonResponse(500, { error: "boom" }));
    }) as typeof fetch;

    const result = await bumpUsage("user-1", "food_photo", 30);

    assertEquals(result, {
      error: "Herculex AI usage tracking is unavailable. Please try again shortly.",
    });
    assertEquals(callCount, 2);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("limitForKind returns the per-kind tiered limit, falling back to dailyLimit for an unknown kind", () => {
  assertEquals(limitForKind("dream_physique"), dreamPhysiqueLimit);
  assertEquals(
    limitForKind("physique_checkin"),
    Number(Deno.env.get("GEMINI_LIMIT_PHYSIQUE_CHECKIN") ?? "5"),
  );
  assertEquals(limitForKind("not_a_real_kind"), dailyLimit);
  assertEquals(limitForKind(undefined), dailyLimit);
});

Deno.test("limitForKind('weekly_report') uses its own env-overridable default of 5", () => {
  assertEquals(
    limitForKind("weekly_report"),
    Number(Deno.env.get("GEMINI_LIMIT_WEEKLY_REPORT") ?? "5"),
  );
  // Regression guard: an unknown kind must still fall back to the daily limit.
  assertEquals(limitForKind("weekly_reports"), dailyLimit);
});
