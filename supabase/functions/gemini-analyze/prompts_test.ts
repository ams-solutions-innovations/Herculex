import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  barcodeProductPrompt,
  dreamPhysiquePrompt,
  foodPhotoPrompt,
  nutritionLabelPrompt,
} from "./prompts.ts";

Deno.test("dream physique prompt carries the programming and privacy contract", () => {
  const prompt = dreamPhysiquePrompt(
    {},
    "Prioritize symmetry",
  );

  assert(prompt.includes('"schemaVersion": 1'));
  assert(prompt.includes('"muscleId": "chest"'));
  assert(prompt.includes("maintenance"));
  assert(prompt.includes("Never infer or return training experience"));
  assert(prompt.includes("Do not include an experienceLevel field anywhere"));
  assert(prompt.includes("Do not choose a final exercise list"));
  assert(prompt.includes('"targetAestheticStyle"'));
  assert(prompt.includes("All human-readable descriptions"));
  assert(prompt.includes("Athletic, defined V-taper physique"));
  assertEquals(prompt.includes('"experienceLevel":'), false);
});

Deno.test("food prompts require a practical, physically grounded portion", () => {
  const photo = foodPhotoPrompt();
  const label = nutritionLabelPrompt("Serving size: 30 g");
  const barcode = barcodeProductPrompt("4006381333931");

  for (const prompt of [photo, label, barcode]) {
    assert(prompt.includes('"portionAmount"'));
    assert(prompt.includes('"portionUnit"'));
  }
  assert(photo.includes("Never use ml for meat"));
  assert(label.includes("Do not use ml for solid foods"));
  assert(photo.includes('"brand": "Herculex AI"'));
});
