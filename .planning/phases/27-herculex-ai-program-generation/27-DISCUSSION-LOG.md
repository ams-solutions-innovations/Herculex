# Phase 27: Herculex AI Program Generation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-29
**Phase:** 27-herculex-ai-program-generation
**Areas discussed:** Shema musclePriorities, Oblika toka v builderju, Obseg izločitve guardrailov, Shranjevanje AI briefa

---

## Shema musclePriorities

| Option | Description | Selected |
|--------|-------------|----------|
| Ponovi dream_physique shemo (priporočeno) | Isti kanonični muscleId seznam (19 vrednosti), confidence 0-1, rationale, uncertainties[]. Plug-and-play v obstoječ `_applyDreamPhysiqueTuning()`/`weeklySetCaps`. | ✓ |
| Nova preprosta oblika iz amandma dokumenta | `{muscle, priority, why}` s prostim besedilom imena mišice. | |
| Ponovi shemo, a brez confidence/uncertainties | Skrajšana varianta reuse-a. | |

**User's choice:** Ponovi dream_physique shemo (priporočeno)
**Notes:** Plugs directly into existing tuning mechanism, no new apply logic needed.

| Option | Description | Selected |
|--------|-------------|----------|
| Zavrni cel brief (priporočeno) | Skladno z AIP-03 in učbenikovim VALIDATE-PLAN-01. Pade nazaj na deterministično priporočilo. | ✓ |
| Izloči samo tisti vnos | Ostale veljavne prioritete obdrži, neveljaven vnos tiho izpusti. | |

**User's choice:** Zavrni cel brief (priporočeno)
**Notes:** Consistent strict-reject policy applied uniformly across all enum fields.

---

## Oblika toka v builderju

| Option | Description | Selected |
|--------|-------------|----------|
| Izpolni obstoječe zaslone (priporočeno) | Brief predizpolni split/periodizacijo/vloge dni/musclePriorities na istih zaslonih kot Smart/Guided; uporabnik lahko še ročno popravi. | ✓ |
| En-shot: naravnost v pregled | Brief gre mimo builder zaslonov naravnost v povzetek + ProgramReviewView. | |

**User's choice:** Izpolni obstoječe zaslone (priporočeno)
**Notes:** Mirrors how dream-physique priorities pre-fill Smart mode today.

| Option | Description | Selected |
|--------|-------------|----------|
| Gumb 'Generiraj' (priporočeno) | Eksplicitna akcija, jasno šteta poraba kvote na klic. | ✓ |
| Samodejno ob izbiri načina | Klic se proži takoj ob izbiri načina, brez gumba. | |

**User's choice:** Gumb 'Generiraj' (priporočeno)
**Notes:** Prevents accidental quota consumption from exploratory mode-selection clicks.

| Option | Description | Selected |
|--------|-------------|----------|
| Vidna razlaga + preklop na Smart/Guided (priporočeno) | Sporočilo pojasni kaj je bilo zavrnjeno, builder samodejno preklopi na obstoječi Smart/Guided rezultat. | ✓ |
| En avtomatski ponovni poskus, nato preklop | Tih dodaten poskus s strožjo zahtevo pred prikazom razlage. | |

**User's choice:** Vidna razlaga + preklop na Smart/Guided (priporočeno)
**Notes:** No silent automatic retry — one call, one visible outcome, consistent with AIP-05's "never silent degradation."

---

## Obseg izločitve guardrailov

| Option | Description | Selected |
|--------|-------------|----------|
| Skupni validator za vse načine (priporočeno) | Izloči v ProgramGuardrails, _create() za manual/smart/guided ga začne klicati namesto inline preverjanj. | ✓ |
| Samo za AI pot | Nova funkcija samo za AI validacijski korak; obstoječi inline preverjanji ostaneta nedotaknjeni. | |

**User's choice:** Skupni validator za vse načine (priporočeno)
**Notes:** Removes duplication end-to-end; requires regression tests for existing manual/smart/guided flows.

| Option | Description | Selected |
|--------|-------------|----------|
| Nova metoda v ProgramGuardrails (priporočeno) | En razred za vse programske guardraile ne glede na fazo življenjskega cikla (pred- ali po-materializacijsko). | ✓ |
| Nov ločen razred (npr. ProgramConfigGuardrails) | Ločena meja odgovornosti med pred- in po-materializacijskim preverjanjem. | |

**User's choice:** Nova metoda v ProgramGuardrails (priporočeno)
**Notes:** Single source of truth for all program safety guardrails.

---

## Shranjevanje AI briefa

| Option | Description | Selected |
|--------|-------------|----------|
| Nova majhna tabela (priporočeno) | Po vzoru PhysiqueProgrammingProfiles: prioritiesJson/rationale, source, modelVersion, knowledgeVersion, confirmedAt. Polna 5-opravilna schema bump. | ✓ |
| Brez perzistence, samo v Programs.description | Rationale se stisne v obstoječ niz, brez novega bump-a. | |

**User's choice:** Nova majhna tabela (priporočeno)
**Notes:** Keeps the brief accessible for later review/audit beyond initial creation.

| Option | Description | Selected |
|--------|-------------|----------|
| Ločen rationale na dan (priporočeno) | Vsak dayRoles[] vnos dobi svoj kratek 'zakaj'. Neposredno izpolni AIP-04. | ✓ |
| En skupen rationale za cel program | En odstavek za celotno zasnovo, prikazan enkrat. | |

**User's choice:** Ločen rationale na dan (priporočeno)
**Notes:** Takes AIP-04's "rationale per day" literally — diverges from the amendment doc's single-rationale-string sketch (Claude's Discretion territory, decided here).

---

## Claude's Discretion

- Exact `knowledgeVersion`/`modelVersion` field placement and column naming in the new table.
- Exact wording of rejection messages and "Generate"/"Regenerate" button copy.
- Exact retry/backoff behavior for network-level Gemini call failures (distinct from validation rejection).
- Whether `ProgramGuardrails`'s new configuration method takes raw builder state or an intermediate value object.
- Exact per-kind quota number for `program_brief` within Phase 26's already-decided tiering shape.

## Deferred Ideas

- Real content for `knowledge_base.ts`'s `programming` segment (sourced from the delivered textbook) — independent deploy, not blocked by or blocking this phase.
- Mapping the textbook's 5-tier experience model and training-style concepts (Arnold/Heavy-Duty/evidence-first) onto the app — explicitly out of scope (no new enum values this phase).
- Any regenerate cap beyond quota itself — not raised during discussion.
