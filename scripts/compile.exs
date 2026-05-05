#!/usr/bin/env elixir
# Helper: compile a WPL-AI source file and print JSON to stdout.
# Usage: mix run scripts/compile.exs <path/to/source.wpl>
#
# The output is compact JSON. Pipe through `jq .` for pretty-printing:
#   mix run scripts/compile.exs source.wpl | jq .

path = case System.argv() do
  [p | _] -> p
  [] ->
    IO.puts(:stderr, "Usage: mix run scripts/compile.exs <path/to/source.wpl>")
    System.halt(1)
end

src = File.read!(path)

case WplAi.to_wpl(src) do
  {:ok, json} ->
    IO.puts(:elixir_json.encode(json))
  {:error, errors} ->
    IO.puts(:stderr, "Compilation failed:")
    IO.puts(:stderr, inspect(errors))
    System.halt(1)
end
