# wpl-ai-ex ↔ @gymbile/wpl-ai@1.10.0 Parity Plan

**Goal:** Bring the Elixir `wpl_ai` package up to functional parity with `@gymbile/wpl-ai@1.10.0` (TypeScript). Elixir 1.0.0 was a clean extract from gymbile_backend; this plan walks it up through 4 minor releases adding the schema 1.3 → 1.6 surfaces.

**Reference TS paths (read-only, source of truth):**
- Grammar: `/Users/alex/Projects/my/gymbile.com/wpl-ai/src/grammar.ts`
- Parser: `/Users/alex/Projects/my/gymbile.com/wpl-ai/src/parser.ts`
- Compiler: `/Users/alex/Projects/my/gymbile.com/wpl-ai/src/compiler.ts`
- Vocabulary: `/Users/alex/Projects/my/gymbile.com/wpl-ai/src/vocabularies.ts`
- Tests for 1.6 (DSL surfaces): `/Users/alex/Projects/my/gymbile.com/wpl-ai/__tests__/dsl-v16-features.test.ts`, `__tests__/dsl-v16-grammar.test.ts`
- Schema: `/Users/alex/Projects/my/gymbile.com/wpl/schema/v1.schema.json`

**Working dir:** `/Users/alex/Projects/my/gymbile.com/wpl-ai-ex/` — branch `main`, no feature branches.

**Process per release tier:** TDD each feature → commit → run full `mix test` (must stay green) → bump `mix.exs` version → CHANGELOG entry → final commit `chore(release): N.N.0` → tag `vN.N.0` → push commits + tag (CI publishes to hex).

**Required GitHub secret:** `HEX_API_KEY` on `gymbile/wpl-ai-ex` (user must set this once before the first tag push).

---

## Tier A — 1.0.1 baseline fix

Single small commit: change emitted `$schema` to canonical `https://wpl.dev/schemas/wpl/v1.schema.json` (currently `https://gymbile.com/schemas/wpl/v1`). Keeps `version` at "1.0.0".

Tag `v1.0.1`.

## Tier B — 1.3.0 features

Mirrors TS wpl-ai 1.3:

1. **MuscleGroup + MovementPattern enums** — DSL: `<exercise> NxR muscles primary <m1>, <m2> secondary <m3> pattern <p>`. Compiler emits `primary_muscles`, `secondary_muscles`, `movement_pattern` on `ExerciseActivity`.
2. **Cardio zone_model** — DSL: `cardio running continuous: zone N model <zone_model>` and intensity types `power | bpm`. Compiler emits `intensity.zone_model` and the new types.
3. **Plan-level ATHLETE_THRESHOLDS** — DSL: top-level `ATHLETE_THRESHOLDS` block with fields `hr_max N bpm`, `lthr N bpm`, `resting_hr N bpm`, `ftp N watts`, `vo2max N`, `critical_pace N`, `body_weight N kg`, `one_rm <exercise> N kg`. Compiler emits `plan.athlete_thresholds`.

Bump to **1.3.0**, tag `v1.3.0`. (Skip 1.1/1.2 — there were no compiler-visible changes there per CHANGELOG audit.)

## Tier C — 1.4.0 features

1. **Per-kg macros / per-kg cals / TDEE multiplier** — DSL accepts `protein 1.6 .. 2.2 g_per_kg`, `carbs … g_per_kg`, `fat … g_per_kg`, `calories N .. M kcal_per_kg` and `multiplier_of_tdee`. Compiler emits the unit verbatim into `MacroRange.unit` / `Calories.unit`.
2. **Weight `percentage_bodyweight`** — DSL: `weight 50% bw` or `weight 50% bodyweight`. Compiler emits `Weight.type: "percentage_bodyweight"`.

Contraindication prefix vocabulary and personalization source prefixes are documentation-only — no code changes.

Bump to **1.4.0**, tag `v1.4.0`.

## Tier D — 1.5.0 features

1. **Phase.type enum** — DSL: `PHASE "Cycle 1" intensification (4 weeks):` (one of `accumulation | intensification | realization | deload | base | build | peak | recovery | transition` after the phase name). Compiler emits `phase.type`.
2. **Week.is_deload** — DSL: `WEEK 4 deload "Deload":`. Compiler emits `week.is_deload: true`.
3. **SubPlanActivity** — DSL: `sub_plan <plan-id>` activity variant. Compiler emits `{ type: "sub_plan", sub_plan_ref }`.

Bump to **1.5.0**, tag `v1.5.0`.

## Tier E — 1.6.0 features (mirror TS 1.10.0 DSL pass)

1. **Contraindication.severity + require_clearance action** — DSL: `contraindication <name> severity <low|moderate|high> action require_clearance`.
2. **Reps.amrap** — DSL: `<exercise> NxAMRAP …` or `<exercise> Nx amrap …`. Compiler emits `reps.amrap: true`.
3. **ExercisePrescription.to_failure** — DSL: `to_failure` modifier. Compiler emits `prescription.to_failure: true`.
4. **Weight.metric** — DSL: `weight 90% rm metric <1rm|e1rm|training_max|daily_max>`.
5. **RecoveryExercise extensions** — DSL: `<name> <hold>s x<reps> [sides …] [modality <enum>] [intensity <1-10>] [body <token>]` + `pnf <Ns> contract <Ns> relax <int> contractions`.
6. **Checkpoint typed MeasurementSpec** — DSL: bare `<MeasurementMetric>` tokens in `measure:` lists; `<metric> questionnaire <q> [note "..."]` for full spec.
7. **Cardio intensity.target.min_bpm/max_bpm** — DSL: `intensity bpm 150..170`. Compiler emits target object with `min_bpm`/`max_bpm`.

Also bump emitted `version` to `"1.6.0"` in this tier.

Bump to **1.6.0**, tag `v1.6.0`.

---

## Test discipline

- After each feature: `mix test` must be green; `mix compile --warnings-as-errors` must be clean.
- Add at least one Elixir test per feature. Use the TS DSL test files as fixtures — port the DSL snippets verbatim where possible, then assert the same JSON shape comes out.

## Out of scope

- Validating the emitted JSON against the schema (that's `wpl_validator`'s job; keep this package focused on parse/compile).
- Decompiling 1.6 features back to DSL — only required if `decompiler.ex` already had a "round-trip" test for that feature; otherwise defer.
- Switching gymbile_backend over to depend on `:wpl_ai` (separate task).
