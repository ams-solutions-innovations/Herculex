import { assertEquals } from "jsr:@std/assert@1";
import { buildSystemInstruction, generate } from "./index.ts";

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const geminiModel = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.7-flash";
const geminiFallbackModel = Deno.env.get("GEMINI_FALLBACK_MODEL") ??
  "gemini-3.5-flash-lite";

Deno.test("buildSystemInstruction returns undefined for empty text and the wrapped shape otherwise", () => {
  assertEquals(buildSystemInstruction(undefined), undefined);
  assertEquals(buildSystemInstruction(""), undefined);
  assertEquals(buildSystemInstruction("x"), { parts: [{ text: "x" }] });
});

Deno.test("generate() reports the primary model when the first call succeeds", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = (() => {
      return Promise.resolve(
        jsonResponse(200, {
          candidates: [{ content: { parts: [{ text: "ok" }] } }],
        }),
      );
    }) as typeof fetch;

    const result = await generate({
      images: [],
      promptText: "hello",
      temperature: 0.1,
    });

    assertEquals(result.modelVersion, geminiModel);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("generate() falls back to the fallback model on a 503 and reports it", async () => {
  const originalFetch = globalThis.fetch;
  try {
    let callCount = 0;
    globalThis.fetch = (() => {
      callCount += 1;
      if (callCount === 1) {
        return Promise.resolve(jsonResponse(503, { error: { message: "overloaded" } }));
      }
      return Promise.resolve(
        jsonResponse(200, {
          candidates: [{ content: { parts: [{ text: "ok" }] } }],
        }),
      );
    }) as typeof fetch;

    const result = await generate({
      images: [],
      promptText: "hello",
      temperature: 0.1,
    });

    assertEquals(result.modelVersion, geminiFallbackModel);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
