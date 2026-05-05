# wpl_ai

[![Hex.pm](https://img.shields.io/hexpm/v/wpl_ai.svg)](https://hex.pm/packages/wpl_ai)
[![CI](https://github.com/gymbile/wpl-ai-ex/actions/workflows/ci.yml/badge.svg)](https://github.com/gymbile/wpl-ai-ex/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache_2.0-blue.svg)](LICENSE)

Reference Elixir compiler for [WPL-AI](https://wpl.dev), the human and AI-friendly
authoring language for wellness plans. Parses WPL-AI DSL source into canonical WPL JSON.

## Installation

```elixir
def deps do
  [
    {:wpl_ai, "~> 1.0"}
  ]
end
```

## Usage

```elixir
source = """
PLAN "Upper Body Beginner"
TYPE workout
DIFFICULTY beginner

PHASES
  PHASE "Foundation" (4 weeks):
    WEEK 1:
      DAY Monday training 45m:
        main straight_sets:
          push_up 3x8..12 target 10 rpe 7
"""

{:ok, json} = WplAi.compile(source)
# json["plan"]["name"]  => "Upper Body Beginner"
# json["version"]       => "1.0.0"
```

You can also access the pipeline steps individually:

```elixir
{:ok, ast}  = WplAi.parse(source)     # WPL-AI text → AST
{:ok, json} = WplAi.compile(ast)      # AST → WPL JSON map
{:ok, text} = WplAi.decompile(json)   # WPL JSON → WPL-AI text (round-trip)
```

## Conformance

The compile-conformance corpus lives in the sibling [`gymbile/wpl`](https://github.com/gymbile/wpl) repo at `conformance/compile/fixtures/`. The runner at `test/conformance_test.exs` discovers it automatically via a relative path (`../../wpl/conformance/compile/fixtures/`) — check out `wpl/` next to `wpl-ai-ex/` on disk and it works with no configuration. Set `WPL_CORPUS_DIR` to override the path (useful for CI that checks out repos at arbitrary locations). Run with `mix test test/conformance_test.exs`. When the corpus is absent, one skipped test is emitted and exit code remains 0.

## Status

Version 1.0.0 — initial extract from `gymbile_backend`. The compiler emits WPL
schema 1.0.0. Phase 2 will bring it to 1.6.0 parity with `@gymbile/wpl-ai`.

## License

[Apache-2.0](LICENSE).

"WPL" and "Wellness Plan Language" are trademarks of Gymbile.
