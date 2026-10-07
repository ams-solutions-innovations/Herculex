// Coaching-mentality corpus za Herculex AI (Phase 26, KB-01/KB-02).
//
// Ta datoteka je namerno majhna in placeholder: pravi "ucbenik" pride pozneje
// kot deploy, ne kot sprememba formata. Segmenti so splosna, varna trenerska
// drza (D-03) — ne konkretni programi, ne stevilke, ne nasveti, ki bi jih
// smel povoziti uporabnikov `userNote`. Noben od 8 obstojecih `kind`-ov tega
// se ne uvazi (D-04) — ta datoteka samo obstaja in je testirana.
//
// KNOWLEDGE_VERSION je locena os od `provenance.modelVersion` v index.ts:
// modelVersion pove, KATERI Gemini model je odgovoril; KNOWLEDGE_VERSION bo
// (v kasnejsi fazi) povedal, KATERA razlicica corpusa je bila vbrizgana.
// Format `kb-YYYY.MM-N` (D-09) je stabilen ze zdaj, tudi ce je vsebina se
// placeholder.

export const core =
  "Favor compound, multi-joint movements over isolation work when time or " +
  "recovery is limited. Progressive overload — a gradual, trackable increase " +
  "in working weight, reps, or quality over weeks — drives long-term results " +
  "far more reliably than any single session. Consistency and adherence beat " +
  "precision: a good plan followed for months outranks a perfect plan " +
  "followed for days.";

export const programming =
  "Sequence heavy compound lifts before accessory work while the lifter is " +
  "freshest, and respect built-in recovery days between sessions that stress " +
  "the same muscle groups or movement patterns. Avoid cues or exercise " +
  "selections known to be injury-provoking for the stated experience level, " +
  "and prefer well-established movement substitutions over novel or " +
  "unverified exercises.";

export const nutrition =
  "Anchor recommendations to sustainable, moderate calorie targets and " +
  "adequate protein intake rather than aggressive short-term deficits or " +
  "surpluses. Hydration, fiber, and micronutrient variety support training " +
  "adaptation and should not be sacrificed for macro precision. Treat a " +
  "single day's intake as noise; look at multi-day trends before adjusting " +
  "targets.";

export const recovery =
  "Sleep quality and duration are a primary lever for recovery and should be " +
  "protected as seriously as training itself. Persistent joint pain, sharp " +
  "pain, or unusual fatigue are signals to deload or seek professional " +
  "evaluation, not to push through. Recovery capacity varies by individual " +
  "and by life stress, so plans should stay flexible rather than rigid.";

export const KNOWLEDGE_VERSION = "kb-2026.10-1";
