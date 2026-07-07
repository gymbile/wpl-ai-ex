# Changelog

All notable changes to `:wpl_ai`.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.2] — 2026-07-07

### Added
- `recovery` recognized as a goal category (WPL 1.9.1) — no longer warns.

## [2.1.1] — 2026-07-07

### Added

- **Goal-category soft-validation**: `Validator.validate_semantics/1` now checks each
  `GOAL` category against the canonical WPL 1.9.0 vocabulary
  (`weight_loss`, `muscle_gain`, `endurance`, `strength`, `flexibility`,
  `mental_wellness`, `nutrition`, `habit`, `general_fitness`, `custom`).
  Unknown categories emit a `:warning` with fuzzy "Did you mean" suggestions.
  Parity with the TypeScript `wpl-ai` lib. Plans with unknown categories still compile.

## [2.1.0] — 2026-06-18

### Added

- **Canonical exercise catalog SSOT**: `WplAi.ExercisesData` is generated from a vendored
  `wpl/data/exercises.json`; `ExerciseMatcher` sources its catalog from it; adds drift-check.
  Public API unchanged.

## [2.0.0] — 2026-06-17

### BREAKING

- **`WplAi.to_wpl/1` now returns a 3-tuple `{:ok, json, repairs}`**. Callers
  matching `{:ok, json} = WplAi.to_wpl(src)` will receive a `MatchError`. Update
  call sites to `{:ok, json, _repairs} = WplAi.to_wpl(src)` or use the new
  `WplAi.to_wpl!/1` bang form which strips the repairs.
- **Unknown safety-adjacent ALL-CAPS sections are now hard parse errors.**
  Sections whose name matches `REQUIRE*`, `CONTRA*`, `SAFETY*`, `PRECAUTION*`,
  `MEDICAL*`, or `CLEARANCE*` are rejected with a `ParseError` rather than
  silently skipped. Previously a typo like `REQUIREMENTS:` (instead of `REQUIRES:`)
  erased all contraindications with no trace.
- **Unknown contraindication `severity` or `action` values are now hard parse
  errors.** Previously an unknown severity was dropped to nil and an unknown action
  defaulted to `:exclude`; both silent-tolerance paths are removed. Valid severity
  values: `low`, `moderate`, `high`. Valid action values: `exclude`, `warn`,
  `require_clearance`.

### Added

- **`repairs` ledger on success path** — `WplAi.to_wpl/1` and
  `WplAi.Parser.parse/1` both return a `repairs: [repair()]` list alongside the
  compiled JSON. Every tolerant normalisation (skipped unknown sections, fuzzy
  exercise substitutions, unknown-exercise-kept, lenient-default fabrications,
  discarded modifiers) is recorded as a repair map with a `:type` atom. Callers
  that do not need repairs can ignore the third element.
- **Unknown-exercise semantic warning** — `WplAi.Validator.validate_semantics/1`
  emits a `:warning` for exercise refs absent from the canonical `ALL_EXERCISES`
  catalog. This is a warning, not a hard error; compilation still succeeds.
- **End-to-end safety-invariant test** — compiles a plan via `WplAi.to_wpl/1`
  then asserts that a contraindicated exercise (including the plural variant
  `push_ups`) cannot survive a call to `WPL.Enforce.enforce/4`. Ensures the
  compiler → validator → enforce pipeline preserves the safety contract end to end.
- **Test-only dep on `wpl_validator`** — added as a local path dep
  `{:wpl_validator, path: "../wpl-validator-ex", only: :test}` for development
  work on this branch.

### Notes

- `WplAi.parse!/1`, `WplAi.to_wpl!/1`, `WplAi.validate/1`, and
  `WplAi.round_trip/1` are updated internally to handle the new 3-tuple return
  without exposing repairs to callers who do not need them.
- **Before `mix hex.publish`**: the `:wpl_validator` dep in `mix.exs` is currently
  a **local PATH dep** (`path: "../wpl-validator-ex"`). This MUST be changed back
  to the Hex version `{:wpl_validator, "~> 1.8", only: :test}` before publishing.
  The CI publish pipeline (`publish.yml`) cannot resolve a path dep and will fail
  if left as-is. `wpl_validator 1.8.0` must be published to Hex first.

## [1.13.0] — 2026-05-13

### Added — vocabulary expansion (TS parity with @gymbile/wpl-ai@1.13.0)

Mirrors the corpus-driven additions in the TypeScript reference.
Every entry below appeared as an unknown_exercise_ref in the
wpl-eval v0.2.0 audit and is a genuine (non-typo) emission observed
in at least one trial:

- **@upper_body**: `inverted_row`, `hangboard`
- **@rehab_mobility** (new module attribute):
  - Rotator-cuff / shoulder rehab: `scapular_retraction`,
    `external_rotation`, `internal_rotation`, `prone_T`, `prone_Y`,
    `prone_W`
  - Pelvic floor / postpartum / pregnancy: `pelvic_tilt`,
    `diaphragmatic_breathing`

`exercises_by_category/0` returns the new `:rehab_mobility` key
alongside the existing six.

### Internal
- All 521 tests pass (1 added for v1.13 vocabulary additions).

## [1.12.0] — 2026-05-13

### Version jump 1.8.0 → 1.12.0 to restore TS/Elixir parity

The Elixir port's version number has been brought into alignment with
the TypeScript reference `@gymbile/wpl-ai`. Versions 1.9.0, 1.10.0,
and 1.11.0 are deliberately skipped — there is no Elixir release at
those tags. Going forward both implementations will release under
matching version numbers so a `wpl_ai 1.x.y` Hex package and a
`@gymbile/wpl-ai@1.x.y` npm package always implement the same
behavioural surface.

1.12.0 is identical in content to 1.8.0 (released 30 minutes earlier).
No functional changes; this release exists solely to realign the
version stream.

## [1.8.0] — 2026-05-13

### Fixed — 8 silent-truncation / tolerance bugs (TS parity with @gymbile/wpl-ai@1.12.0)

Compound effect: Lane B served rate moved from 37/80 to 77/80 in the wpl-eval
v0.2.0 corpus with no LLM re-calls. The 0/80 safety claim is unchanged.

- **#1 — rpe/rir range modifiers (`rpe 7..8`, `rir 1..2`)**: `parse_exercise_modifiers`
  and `parse_intensity` now accept range syntax in addition to scalar values.
  Produces `rpe_min`/`rpe_max` (resp. `rir_min`/`rir_max`) on `%AST.Exercise{}`;
  compiler emits `target_rpe_min`/`target_rpe_max` accordingly. Previously the
  range token leaked into downstream parsing and silently truncated subsequent
  WEEK blocks.

- **#2 — reps time-unit suffix before modifier keyword (`3x30s rpe 6`)**: 
  `parse_reps_spec` now consumes a trailing `s`/`m`/`seconds`/`minutes`/`hours`
  suffix when the next token is a modifier keyword (`rpe`, `rir`, `rest`, `tempo`,
  `weight`, `name`, `to_failure`, `bodyweight`). Applied to both single-number and
  range (`3x20..30s`) reps branches via shared `@reps_modifier_follow` constant
  and `maybe_consume_reps_unit_suffix/1` helper.

- **#3 — long-form duration units in simple activity (`cycling 10 minutes`)**: 
  `parse_exercise_or_simple_activity` accepts keyword units (`seconds`, `minutes`,
  `hours`, `days`) in the simple-activity branch in addition to short bare-word
  forms (`s`, `m`, `h`).

- **#4 — simple activity trailing modifiers leak (`cycling 20m rpe 6 rest 30s`)**:
  New `consume_simple_activity_modifiers/1` helper walks and discards any trailing
  `rpe`/`rir`/`rest`/`tempo`/`weight`/`name`/`to_failure`/`bodyweight`/`heart_rate_zone`/
  `bpm`/`pace` tokens after a simple activity. Values are intentionally dropped
  (SimpleActivity has no carrier fields); the goal is to prevent leakage.

- **#5 — lexer: en/em-dash normalised, typographic punctuation silently skipped, N-M as range**:
  - En-dash (U+2013) and em-dash (U+2014) → ASCII hyphen via pre-scan normalisation.
  - `;`, `&`, `~`, `@`, ASCII apostrophe (`'`), smart quotes (' ' " "), ellipsis (…),
    ≤, ≥, middle-dot, bullet → dropped silently.
  - `N-M` between two numbers emits a `:range` token (equivalent to `..`) when the
    prior emitted token was a `:number`. `parse_tempo` updated to accept `:range` as
    a separator alongside `:minus` between tempo segments.
  - Elixir structural note: implemented as a `normalize_typographic_chars/1` pre-scan
    pass (source string normalisation) rather than the TS in-place byte mutation
    approach — idiomatic for Elixir's immutable binary model.

- **#6 — trailing-dot number typos (`12.`, `7.`)**:
  `consume_number_like` stops before consuming a `.` that has no digit after it;
  the clean integer is emitted and `tokenize_dots` skips the dangling dot silently.

- **#7 — stray top-level ALL-CAPS sections (`NUTRITION:`, `SUMMARY:`, `NOTES:`)**:
  `parse_sections` detects an ALL-CAPS keyword followed by `:` and skips the entire
  indented body using `skip_until_matching_dedent/2`. No error is emitted; compile
  reports `ok: true` and the PHASES section parses normally.

- **#8 — two-tier exercise-ref resolution**:
  - Unknown TYPE values (e.g. `TYPE summary`) silently fall back to `:workout` instead
    of `String.to_atom`-ing arbitrary values.
  - Cardio modalities (`running`, `walking`, `cycling`, `rowing`, `elliptical`,
    `swimming`, `jump_rope`, `hiking`) accepted as exercise refs in sets×reps form.
  - `resolve_exercise_ref/1` replaces ad-hoc validation: tier 1 auto-corrects
    high-confidence typos (Jaro-Winkler ≥ 0.85, e.g. `pushup` → `push_up`); tier 2
    accepts unknown refs as-is so compile succeeds with the model's literal name
    preserved in `exercise_ref`.

### Added

- `%AST.Exercise{}` gains fields: `rpe_min`, `rpe_max`, `rir_min`, `rir_max`.
- `WplAi.Parser` (private): `resolve_exercise_ref/1`, `maybe_consume_reps_unit_suffix/1`,
  `consume_simple_activity_modifiers/1`, `expect_minus_or_range/1`, `@reps_modifier_follow`,
  `@simple_activity_modifier_keywords`, `@cardio_modality_set`.
- `WplAi.Lexer` (private): `normalize_typographic_chars/1`, `@dash_replacements`,
  `@silent_skip_replacements`, `last_emitted_token_is_number?/1`.
- 49 new regression tests in `test/wpl_ai/v1_12_fixes_test.exs`.

## [1.6.7] — 2026-05-04

### Fixed — parser bug: dash-prefixed typed MeasurementSpec (TS parity with @gymbile/wpl-ai@1.10.5)

- **#G — dash-prefixed typed `MeasurementSpec` parsing**: `parse_typed_measurement_list/2` now correctly handles `- questionnaire_score questionnaire psqi note "text"` as a single `%AST.MeasurementSpec{}` node (with `metric`, `questionnaire`, and `note` fields) rather than emitting a bare spec with only `metric` set and discarding the remaining qualifiers.

## [1.6.6] — 2026-05-05

### Fixed — 7 silent-failure parser/lexer bugs (TS parity with @gymbile/wpl-ai@1.10.4)

- **Bug 1 — digit-leading TAGS value (`531`)**: `TAGS 531, strength` now produces `tags: ["531", "strength"]` instead of `tags: []`; `parse_tag_list` accepts number tokens.
- **Bug 2 — digit-leading identifier in TAGS list (`1rm_estimate`)**: `TAGS strength_test, 1rm_estimate, powerlifting` no longer truncates after the digit-leading item; the `number + bare_word` token sequence is glued into a single tag string.
- **Bug 3 — colon-qualified contraindication name (`acsm:cardiac_rehab_phase_2`)**: the parser now accepts `prefix:suffix` form in the contraindication-name slot; glues the colon token into a single qualified identifier string.
- **Bug 4 — unknown REQUIRES directive silently terminates block**: any unrecognised keyword or bare_word inside a REQUIRES block now produces a `ParseError` with type `invalid_structure`: "Unknown REQUIRES directive: '...'. Recognized: contraindication, fitness, equipment, age, time_commitment."
- **Bug 5 — `trigger completion` (no-arg) swallows subsequent sections**: `parse_trigger` now emits a `ParseError` with type `invalid_structure`: "Unsupported checkpoint trigger 'completion' — use 'at N weeks' or 'at N days'."
- **Bug 6 — unknown phase type silently drops the phase**: `parse_phase` detects non-recognized type keywords and emits a `ParseError` with type `invalid_structure`: "Unknown phase type '<x>'. Allowed: accumulation, intensification, realization, deload, base, build, peak, recovery, transition."
- **Bug 7 — `jogging 10m` in cooldown produces malformed recovery_exercise + phantom `m` orphan**: the cooldown block parser now routes `<bare_word> <number> <time_unit> EOL` to an inline `CardioActivity` with `modality`, `cardio_type: :continuous`, and `total_duration` populated correctly.

### Added

- **Invalid-parser conformance runner**: `conformance_test.exs` now also iterates `wpl/conformance/invalid/parser/` fixtures, verifying that `WplAi.Parser.parse/1` returns `{:error, ...}` with errors matching the expected `type` and `message` fields.

## [1.6.5] — 2026-05-05

### Fixed

- **compiler: emit `progress.points_system` instead of `progress.points`** — matches schema field name. Previous `"points"` key produced SCHEMA_VIOLATION when validated.
- **compiler: day-scoped activity ID counter** — auto-IDs were previously per-block; same activity kind in two blocks of the same day collided (DUPLICATE_ID). Now monotonic across all blocks in a day.

## [1.6.4] — 2026-05-04

### Added

- **`WplAi.Validator` module** — new semantic validator that walks the AST and emits vocabulary warnings (not errors). Mirrors the TypeScript `validateSemantics` step in `wpl-ai`.
- **`WplAi.validate_semantics/1`** — public API entry point delegating to `WplAi.Validator.validate_semantics/1`.

### Fixed

- **validator: refresh MeasurementMetric + Questionnaire vocabulary to schema 1.6.0**: `WplAi.Validator` knows the canonical 24-value `MeasurementMetric` enum and the 8-value `Questionnaire` enum; legacy string items are checked against the combined (legacy + enum) set; typed `MeasurementSpec` items have `metric` checked against the enum set, and `questionnaire` (when `metric == "questionnaire_score"`) checked against the questionnaire set.

## [1.6.3] — 2026-05-04

### Changed

- test: per-module unit tests (lexer, parser, vocabularies, exercise_matcher) — 93 new tests.

## [1.6.2] — 2026-05-05

### Fixed

- **Bug 1 — Structured `tempo` emit** — `tempo 3 - 1 - 1 - 0` (and `3-0-X-1` forms) now emits the structured object `{eccentric, pause_bottom, concentric, pause_top}` instead of a raw string. `X` in the concentric position sets `explosive_concentric: true` (TS parity).
- **Bug 2 — `weight N% bw` unit field** — `percentage_bodyweight` weight spec now emits `unit: "bw"` instead of `unit: "%"` (TS parity).
- **Bug 3 — Calories `kcal` unit omitted** — when calorie unit is `"kcal"` (the schema default), the `unit` field is now omitted from the compiled output. Only `kcal_per_kg` and `multiplier_of_tdee` are emitted (TS parity).
- **Bug 4 — Nutrition timing `at_time` maps to `type: "absolute"`** — `timing at 07:30` now emits `{type: "absolute", time: "07:30"}` (with no seconds, no offset field). Previously emitted `{type: "at_time", time: "07:30:00"}` (TS parity).
- **Bug 5 — Nutrition timing `before_workout`/`after_workout` drops body content** — `before_workout` and `after_workout` were not in the keywords list, causing them to be tokenized as bare words and break the timing parser. Adding them to the lexer keyword list restores full body parsing after a timing directive (TS parity).
- **Bug 6 — Habit `prescription` nesting** — habit activities now nest `target`, `frequency`, and `reminder_times` under a `prescription` key instead of emitting them flat on the activity. Also fixed a parser bug where parsing `frequency` in a habit body called `parse_plan_habit_body` instead of `parse_habit_body`, silently dropping `reminders` (TS parity).
- **Bug 7 — `bodyweight` keyword as exercise modifier** — bare `bodyweight` after reps/sets (e.g., `pull_up 3x8 bodyweight`) now attaches as `weight: {type: "bodyweight"}` on the exercise prescription instead of generating a phantom `SimpleActivity` (TS parity).

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
