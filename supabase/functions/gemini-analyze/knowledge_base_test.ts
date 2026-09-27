import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  core,
  KNOWLEDGE_VERSION,
  nutrition,
  programming,
  recovery,
} from "./knowledge_base.ts";

Deno.test("each coaching-mentality segment is a substantive, non-empty string", () => {
  for (const segment of [core, programming, nutrition, recovery]) {
    assert(typeof segment === "string");
    assert(segment.length > 40);
  }
});

Deno.test("KNOWLEDGE_VERSION follows the kb-YYYY.MM-N format", () => {
  assert(/^kb-\d{4}\.\d{2}-\d+$/.test(KNOWLEDGE_VERSION));
});

Deno.test("no segment contains language that lets user input override calorie/training data", () => {
  for (const segment of [core, programming, nutrition, recovery]) {
    assertEquals(segment.toLowerCase().includes("always trust user"), false);
  }
});
