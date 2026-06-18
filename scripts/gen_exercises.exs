# GENERATOR for lib/wpl_ai/exercises_data.ex — reads the vendored canonical
# catalog and (re)writes the generated Elixir data module. Deterministic:
# preserves the category + name ordering from the JSON.
# Run: MIX_ENV=test mix run scripts/gen_exercises.exs

root = File.cwd!()
json_path = Path.join(root, "priv/data/exercises.json")
data = json_path |> File.read!() |> Jason.decode!()

version = data["version"]
categories = data["categories"]

# Preserve JSON key order deterministically.
order = ~w(upper_body lower_body core cardio_warmup stretching full_body rehab_mobility)
ordered = Enum.map(order, fn cat -> {cat, Map.fetch!(categories, cat)} end)

fmt_list_block = fn names, indent ->
  inner = names |> Enum.map_join(",\n#{indent}  ", &inspect/1)
  "[#{inner}]"
end

by_cat =
  ordered
  |> Enum.map(fn {cat, names} ->
    "    #{cat}: #{fmt_list_block.(names, "    ")}"
  end)
  |> Enum.join(",\n")

all_names =
  ordered
  |> Enum.flat_map(fn {_cat, names} -> names end)
  |> Enum.map_join(",\n    ", &inspect/1)

module = """
defmodule WplAi.ExercisesData do
  @moduledoc \"\"\"
  GENERATED — do not edit. Run `MIX_ENV=test mix run scripts/gen_exercises.exs`.
  Source of truth: wpl/data/exercises.json (vendored at priv/data/exercises.json).
  Catalog version: #{version}
  \"\"\"

  @all [
    #{all_names}
  ]

  @by_category %{
#{by_cat}
  }

  @doc "Flat list of all canonical exercise names (category order, then JSON order)."
  def all, do: @all

  @doc "Exercises grouped by category."
  def by_category, do: @by_category
end
"""

out_path = Path.join(root, "lib/wpl_ai/exercises_data.ex")
File.write!(out_path, module)

# Run mix format on the generated file so it is formatter-compliant from the start.
{_, 0} = System.cmd("mix", ["format", out_path], cd: root, stderr_to_stdout: true)

IO.puts("wrote lib/wpl_ai/exercises_data.ex (#{version})")
