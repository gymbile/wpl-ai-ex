# Changelog

All notable changes to `:wpl_ai`.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
