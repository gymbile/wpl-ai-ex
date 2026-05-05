#!/usr/bin/env elixir
# Helper script to generate normalized expected.json fixture content.
# Usage: mix run scripts/gen_fixtures.exs

defmodule FixtureGen do
  @auto_id_re ~r/^[a-z0-9_]+_\d+$|^[a-z0-9_]+_block$/
  @uuid_re ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

  def normalize(map, parent_key \\ nil)

  def normalize(map, parent_key) when is_map(map) do
    map
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      if parent_key == "metadata" and k in ["created_at", "updated_at"] do
        acc
      else
        Map.put(acc, k, normalize(v, k))
      end
    end)
  end

  def normalize(list, _parent_key) when is_list(list) do
    Enum.map(list, &normalize(&1, nil))
  end

  def normalize(value, "id") when is_binary(value) do
    cond do
      Regex.match?(@auto_id_re, value) -> "<AUTO_ID>"
      Regex.match?(@uuid_re, value) -> "<UUID>"
      true -> value
    end
  end

  def normalize(value, _parent_key) when is_float(value) do
    truncated = trunc(value)
    if value == truncated * 1.0, do: truncated, else: value
  end

  def normalize(value, _parent_key), do: value

  def generate(source) do
    {:ok, result} = WplAi.to_wpl(source)
    normalized = normalize(result)
    :elixir_json.encode(normalized)
  end
end

# Test it
source = ~S"""
PLAN "Sets With Tempo"
TYPE workout
VISIBILITY public

GOALS

PHASES
  PHASE "Strength" (1 weeks):
    WEEK 1:
      DAY Monday training "Bench Day":
        main straight_sets:
          bench_press 3x8 tempo 3 - 1 - 1 - 0 rest 90 seconds weight 60 kg
"""

IO.puts(FixtureGen.generate(source))
