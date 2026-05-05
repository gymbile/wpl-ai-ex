# Changelog

All notable changes to `:wpl_ai`.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
