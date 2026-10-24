import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { GenerationBudget, GeminiFailure, requestGemini } from "./gemini_transport.ts";
import { generate, validateRequestImages } from "./index.ts";

const ok = () => new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: "ok" }] } }] }), { status: 200 });
const config = { primaryModel: "primary", fallbackModel: "backup", apiKey: "test",
  bodyForModel: () => "{}", wait: async (_ms: number) => {} };

for (const status of [408, 429, 500, 502, 503, 504]) {
  Deno.test(`temporary HTTP ${status} uses one bounded backup attempt`, async () => {
    const urls: string[] = [];
    const budget = new GenerationBudget("test");
    const fetcher = ((url: string | URL | Request) => {
      urls.push(String(url));
      return Promise.resolve(urls.length === 1 ? new Response("busy", { status }) : ok());
    }) as typeof fetch;
    const result = await requestGemini({ ...config, budget, fetcher });
    assertEquals(urls.length, 2);
    assertEquals(result.modelVersion, "backup");
    assertEquals(budget.attempts, 2);
  });
}

Deno.test("timeouts and network failures can fall back without a third call", async () => {
  for (const error of [new DOMException("expired", "TimeoutError"), new TypeError("network")]) {
    let calls = 0;
    const result = await requestGemini({ ...config, fetcher: (() => {
      if (++calls === 1) return Promise.reject(error);
      return Promise.resolve(ok());
    }) as typeof fetch });
    assertEquals(calls, 2);
    assertEquals(result.modelVersion, "backup");
  }
});

Deno.test("bad configuration and invalid input do not repeat a provider call", async () => {
  for (const status of [400, 401, 403, 404]) {
    let calls = 0;
    await assertRejects(() => requestGemini({ ...config, fetcher: (() => {
      calls++;
      return Promise.resolve(new Response("error", { status }));
    }) as typeof fetch }), GeminiFailure);
    assertEquals(calls, 1);
  }
});

Deno.test("an exhausted shared deadline prevents another generation", async () => {
  let time = 0;
  let calls = 0;
  const budget = new GenerationBudget("test", "request", () => time);
  await assertRejects(() => requestGemini({ ...config, budget, fetcher: (() => {
    calls++; time = 71_000;
    return Promise.reject(new DOMException("expired", "TimeoutError"));
  }) as typeof fetch }), GeminiFailure);
  assertEquals(calls, 1);
});

Deno.test("grounding fallback and transport fallback share the two-attempt cap", async () => {
  const budget = new GenerationBudget("barcode");
  let calls = 0;
  const fetcher = (() => { calls++; return Promise.resolve(ok()); }) as typeof fetch;
  await requestGemini({ ...config, budget, fetcher });
  await requestGemini({ ...config, budget, fetcher });
  await assertRejects(() => requestGemini({ ...config, budget, fetcher }), GeminiFailure);
  assertEquals(calls, 2);
});

Deno.test("Retry-After is honoured and two failures are terminal", async () => {
  const delays: number[] = [];
  let calls = 0;
  await assertRejects(() => requestGemini({ ...config,
    wait: async (ms) => { delays.push(ms); }, fetcher: (() => {
      calls++; return Promise.resolve(new Response("busy", { status: 503, headers: { "Retry-After": "2" } }));
    }) as typeof fetch }), GeminiFailure);
  assertEquals(delays, [2000]);
  assertEquals(calls, 2);
});

Deno.test("check-in accepts three distinct poses on both sides and preserves legacy single-photo requests", () => {
  const image = { mimeType: "image/jpeg", data: "AQID" };
  const photos = ["front", "side", "back"].map((pose) => ({ ...image, pose }));
  assertEquals(validateRequestImages({ kind: "physique_checkin", baselineImages: photos, currentImages: photos }), null);
  assertEquals(validateRequestImages({ kind: "physique_checkin", baselineImages: [image], currentImages: [image] }), null);
  assertEquals(typeof validateRequestImages({ kind: "physique_checkin", baselineImages: photos, currentImages: [...photos, image] }), "string");
  assertEquals(typeof validateRequestImages({ kind: "physique_checkin", baselineImages: photos, currentImages: [photos[0], photos[0]] }), "string");
});

Deno.test("a thinking part cannot replace the actual answer", async () => {
  const original = globalThis.fetch;
  try {
    globalThis.fetch = (() => Promise.resolve(new Response(JSON.stringify({ candidates: [{ content: { parts: [
      { text: "internal", thought: true }, { text: "answer" },
    ] } }] }), { status: 200 }))) as typeof fetch;
    const result = await generate({ images: [], promptText: "test", temperature: 0.2 });
    assertEquals(result.text, "answer");
  } finally { globalThis.fetch = original; }
});

Deno.test("provider quota is distinct from a member's daily AI quota", async () => {
  let calls = 0;
  try {
    await requestGemini({primaryModel: "primary", fallbackModel: "fallback", apiKey: "test",
      bodyForModel: () => "{}", wait: async () => {},
      fetcher: (() => {calls++; return Promise.resolve(new Response("{}", {status: 429}));}) as typeof fetch});
    throw new Error("Expected provider limit");
  } catch (error) {
    if (!(error instanceof GeminiFailure) || error.code !== "provider_quota" || error.status !== 503) throw error;
    if (calls !== 2) throw new Error("Expected exactly two attempts");
  }
});
