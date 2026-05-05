# Changelog

All notable changes to `:wpl_ai`.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.6.1] — 2026-05-04

### Fixed
- **`metadata.language` default** — compiler now always emits `metadata.language: "en"` when the DSL does not specify a language, matching TS compiler behaviour (TS parity).
- **Auto-derived activity display `name`** — compiler now derives `name` from the exercise_ref / modality / category token for Exercise, Cardio, Nutrition, Meditation, Recovery, and Habit activities, matching the TS `humanise()` helper exactly. Acronyms (HIIT, AMRAP, EMOM, RPE, RIR, 1RM) are uppercased; all other words are title-cased. Explicit `name` set in the DSL is preserved as-is (TS parity).

## [1.6.0] — 2026-05-05

### Added
- **`Contraindication.severity + require_clearance`** (schema v1.6.0) — extends the
  contraindication DSL to `contraindication <name> [severity <low|moderate|high>] [action <action>]`
  where action now includes `require_clearance`. The old arrow form (`contraindication <name> -> <action>`)
  is preserved for back-compat. Compiler emits `severity` only when present.
- **`Reps.amrap`** (schema v1.6.0) — DSL: `<exercise> NxAMRAP` (compact) or `Nx amrap` (space-separated,
  case-insensitive). Compiler emits `prescription.reps: { amrap: true }`. Sets count is preserved from N.
- **`ExercisePrescription.to_failure`** (schema v1.6.0) — optional modifier `to_failure` in the
  exercise modifier chain. Compiler emits `prescription.to_failure: true` when present; field omitted otherwise.
- **`Weight.metric`** qualifier (schema v1.6.0) — optional `metric <1rm|e1rm|training_max|daily_max>`
  after a `weight N% rm` spec. Compiler emits `weight.metric: "<canonical>"` (e.g. `"1RM"`, `"e1RM"`,
  `"training_max"`, `"daily_max"`). Omitted when not specified (back-compat).
- **`RecoveryExercise` extensions** (schema v1.6.0) — optional modifiers on recovery exercise lines:
  `modality <enum>` (7 values: `static_stretch | dynamic_stretch | pnf | smr_foam_roll | smr_ball | breathwork | mobility_drill`),
  `intensity <1-10>` → emits `intensity_rpe`, `body <token>` → emits `body_part`.
  Optional indented `pnf <Ns> contract <Ns> relax <int> contractions` continuation line emits
  `{ contraction_seconds, relax_seconds, contractions }`. Recovery exercises now compiled under
  `prescription.exercises` to match TS schema.
- **Checkpoint typed `MeasurementSpec`** (schema v1.6.0) — `measure:` lists now accept bare metric
  tokens (emitting `{ metric: "<value>" }`) and `<metric> questionnaire <enum> [note "text"]`
  (emitting full typed spec). Quoted strings preserved as plain strings (back-compat). Added support
  for TS-style inline `CHECKPOINT "Name":` blocks with `at N weeks` trigger form.
- **Cardio `intensity.target.min_bpm/max_bpm`** (schema v1.6.0) — `intensity bpm N..M` now compiles
  to `prescription.intensity: { type: "bpm", target: { min_bpm: N, max_bpm: M } }`.
- **Emitted `version` bumped to `"1.6.0"`** — compiler now emits `"version": "1.6.0"` in all compiled plans.

## [1.5.0] — 2026-05-04

### Added
- **`Phase.type` enum** (schema v1.5.0) — DSL: `PHASE "Name" <type> (N weeks):` where `<type>` is
  one of `accumulation | intensification | realization | deload | base | build | peak | recovery | transition`.
  Compiler emits `phase.type: "<value>"`. When omitted, no `type` key is emitted on the phase object.
- **`Week.is_deload`** (schema v1.5.0) — DSL: `WEEK N deload` (optional token immediately after the
  week number, before the optional name string). Compiler emits `week.is_deload: true`. When absent,
  the field is omitted (not emitted as `false`).
- **`SubPlanActivity`** (schema v1.5.0) — new activity variant `subplan <plan-id>` (optionally
  followed by a quoted name string) inside any block. Compiler emits
  `{ type: "sub_plan", id: "sub_plan_N", sub_plan_ref: "<plan-id>", name?: "<optional>" }`.

## [1.4.0] — 2026-05-04

### Added
- **Per-kg macros + per-kg cals + TDEE multiplier** (schema v1.4.0) — DSL accepts unit suffixes
  `g_per_kg` on `protein`, `carbs`, `fat` lines and `kcal_per_kg` / `multiplier_of_tdee` on
  `calories` lines. Compiler emits the unit verbatim into `MacroRange.unit` / `Calories.unit`.
  Default units remain `"g"` and `"kcal"` when no suffix is given.
- **`Weight.percentage_bodyweight`** (schema v1.4.0) — DSL: `weight N% bw` or
  `weight N% bodyweight`. Compiler emits `Weight` with `type: "percentage_bodyweight"`,
  `value: N`, `unit: "%"`. Existing `weight N kg` (absolute) and `weight N% rm`
  (percentage_1rm) forms are unchanged.

## [1.3.0] — 2026-05-04

### Fixed
- Compiler now emits the canonical `$schema` URL `https://wpl.dev/schemas/wpl/v1.schema.json`
  (previously emitted `https://gymbile.com/schemas/wpl/v1`).

### Added
- **MuscleGroup + MovementPattern enums** — DSL: `<exercise> NxR muscles primary <m1>, <m2> secondary <m3> pattern <p>`.
  Compiler emits `primary_muscles`, `secondary_muscles`, and `movement_pattern` on `ExerciseActivity`.
  Supports all 22 `MuscleGroup` values and all 13 `MovementPattern` values from schema v1.3.0.
- **Cardio `zone_model`** — DSL: `zone N model <zone_model>` qualifier inside a `cardio` block.
  Compiler emits `intensity.zone_model` (7 values: `hr_3_zone_seiler`, `hr_5_zone`, `hr_7_zone`,
  `power_coggan_7_zone`, `pace_critical_speed`, `rpe_borg_10`, `rpe_borg_20`).
  New intensity type `intensity power N` emits `intensity.type: "power"`.
- **Plan-level `ATHLETE_THRESHOLDS` block** — top-level DSL section (parallel to `PHASES`).
  Accepts `hr_max N bpm`, `lthr N bpm`, `resting_hr N bpm`, `ftp N watts`, `vo2max N`,
  `critical_pace N`, `body_weight N kg`, `one_rm <exercise> N kg`.
  Compiler emits `plan.athlete_thresholds` with field-name suffixes matching schema v1.3.0
  (`hr_max_bpm`, `lthr_bpm`, `resting_hr_bpm`, `ftp_watts`, `vo2max_ml_kg_min`,
  `critical_pace_seconds_per_km`, `body_weight_kg`, `one_rm: [{ exercise_ref, value, unit }]`).

## [1.0.0] — 2026-05-04

### Added
- Initial extract from `gymbile_backend`. Compiler emits WPL schema 1.0.0.
- `WplAi.parse/1` — WPL-AI DSL text → `WplAi.AST.Document` struct.
- `WplAi.compile/1` — AST → WPL JSON map (string keys, `"version": "1.0.0"`).
- `WplAi.to_wpl/1` — parse + compile in one step.
- `WplAi.decompile/1` — WPL JSON → WPL-AI text (round-trip).
- `WplAi.tokenize/1` — exposes the lexer for tooling / syntax highlighting.
- `WplAi.validate/1` — fast validity check without full compilation.
- `WplAi.ExerciseMatcher` — Jaro-Winkler fuzzy matching for exercise references.
- `WplAi.Errors` — structured error types (`LexerError`, `ParseError`, `CompileError`)
  with LLM-optimised formatting helpers.
- Significant-indentation lexer (Python-style `INDENT`/`DEDENT`).
- Recursive-descent parser covering: header, goals, requirements, personalization,
  phases/weeks/days/blocks, exercise / cardio / nutrition / meditation / recovery /
  habit / simple activities, progress checkpoints, top-level `HABITS` section.

### Notes
Phase 2 will update the emitted schema version and bring the compiler to parity
with `@gymbile/wpl-ai` v1.6.0. Every plan valid under schema 1.0.0 will continue
to compile correctly.
