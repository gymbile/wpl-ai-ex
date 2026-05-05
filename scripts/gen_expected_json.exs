#!/usr/bin/env elixir
# Generates expected.json for conformance fixtures that have source.wpl but no expected.json.
# Usage: mix run scripts/gen_expected_json.exs

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

  def pretty_json(map) do
    json_str = map |> normalize() |> :elixir_json.encode()
    tmp = Path.join(System.tmp_dir!(), "fixture_tmp_#{:erlang.unique_integer([:positive])}.json")

    try do
      File.write!(tmp, json_str)
      {result, 0} = System.cmd("python3", ["-c",
        "import sys,json; f=open(sys.argv[1]); print(json.dumps(json.load(f), indent=2, sort_keys=False))", tmp])
      result
    after
      File.rm(tmp)
    end
  end

  def generate_for_fixture(fixture_dir) do
    source_file = Path.join(fixture_dir, "source.wpl")
    expected_file = Path.join(fixture_dir, "expected.json")

    if File.exists?(source_file) and not File.exists?(expected_file) do
      source = File.read!(source_file)

      case WplAi.to_wpl(source) do
        {:ok, result} ->
          json = pretty_json(result)
          File.write!(expected_file, json)
          IO.puts("  Generated: #{Path.basename(expected_file)}")

        {:error, errors} ->
          IO.puts("  ERROR compiling #{source_file}:")
          Enum.each(errors, &IO.puts("    #{inspect(&1)}"))
      end
    end
  end

  def run(corpus_dir) do
    IO.puts("Generating expected.json for fixtures missing it...")

    corpus_dir
    |> File.ls!()
    |> Enum.sort()
    |> Enum.each(fn category ->
      category_dir = Path.join(corpus_dir, category)

      if File.dir?(category_dir) do
        IO.puts("\n#{category}/")

        category_dir
        |> File.ls!()
        |> Enum.sort()
        |> Enum.each(fn name ->
          fixture_dir = Path.join(category_dir, name)

          if File.dir?(fixture_dir) do
            expected_file = Path.join(fixture_dir, "expected.json")

            if File.exists?(expected_file) do
              IO.puts("  #{name}: skip (exists)")
            else
              IO.write("  #{name}: ")
              generate_for_fixture(fixture_dir)
            end
          end
        end)
      end
    end)

    IO.puts("\nDone.")
  end
end

corpus_dir = Path.expand("../../wpl/conformance/compile/fixtures", __DIR__)

if File.dir?(corpus_dir) do
  FixtureGen.run(corpus_dir)
else
  IO.puts("Corpus directory not found: #{corpus_dir}")
end
