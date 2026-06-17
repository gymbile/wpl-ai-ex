defmodule WplAi.ConformanceTest do
  @moduledoc """
  Compile-conformance test runner.

  Walks the shared compile-conformance corpus and compiles each fixture's
  `source.wpl` against the Elixir compiler, then deep-equals the normalized
  output against `expected.json`.

  Also walks the invalid/parser/ corpus and asserts that WplAi.Parser.parse/1
  returns {:error, errors} with at least one error whose type matches the
  expected `type` field and whose message matches the expected `message` field.

  Corpus resolution strategy:
    1. If the `WPL_CORPUS_DIR` environment variable is set, use that path.
    2. Otherwise, resolve relative to this file:
       `../../wpl/conformance/compile/fixtures/`
       (assumes `wpl/` is a sibling repo of `wpl-ai-ex/` on disk)

  If the corpus directory is not reachable, one skipped test is emitted with
  a clear message.  Exit code remains 0.
  """

  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Normalization
  # ---------------------------------------------------------------------------

  @auto_id_re ~r/^[a-z0-9_]+_\d+$|^[a-z0-9_]+_block$/
  @uuid_re ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

  @doc """
  Recursively normalizes a parsed JSON value before comparison.

  Rules (mirrors the TS runner and README normalization spec):
    1. Map keys sorted alphabetically.
    2. ID strings matching auto-numbered pattern → "<AUTO_ID>".
    3. UUID-format ID strings → "<UUID>".
    4. metadata.created_at / updated_at → removed (runtime timestamps).
    5. Whole-number floats → integers (1.0 → 1).

  Note: `metadata.language` and activity `name` fields are no longer stripped.
  Both compilers now emit these identically (TS parity as of wpl-ai-ex v1.6.1).
  """
  def normalize_value(value, parent_key \\ nil)

  def normalize_value(map, parent_key) when is_map(map) do
    map
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      # 4. Strip metadata runtime timestamp fields only
      if parent_key == "metadata" and k in ["created_at", "updated_at"] do
        acc
      else
        Map.put(acc, k, normalize_value(v, k))
      end
    end)
  end

  def normalize_value(list, _parent_key) when is_list(list) do
    Enum.map(list, &normalize_value(&1, nil))
  end

  def normalize_value(value, "id") when is_binary(value) do
    cond do
      Regex.match?(@auto_id_re, value) -> "<AUTO_ID>"
      Regex.match?(@uuid_re, value) -> "<UUID>"
      true -> value
    end
  end

  # 5. Coerce whole-number floats to integers
  def normalize_value(value, _parent_key) when is_float(value) do
    truncated = trunc(value)
    if value == truncated * 1.0, do: truncated, else: value
  end

  def normalize_value(value, _parent_key), do: value

  # ---------------------------------------------------------------------------
  # Per-fixture test registration
  # ---------------------------------------------------------------------------

  fixtures =
    Path.expand("../../wpl/conformance/compile/fixtures", __DIR__)
    |> then(fn dir ->
      case System.get_env("WPL_CORPUS_DIR") do
        nil -> dir
        env_dir -> env_dir
      end
    end)

  all_fixtures =
    if File.dir?(fixtures) do
      fixtures
      |> File.ls!()
      |> Enum.sort()
      |> Enum.flat_map(fn category ->
        category_dir = Path.join(fixtures, category)

        if File.dir?(category_dir) do
          category_dir
          |> File.ls!()
          |> Enum.sort()
          |> Enum.flat_map(fn name ->
            fixture_dir = Path.join(category_dir, name)
            source_file = Path.join(fixture_dir, "source.wpl")
            expected_file = Path.join(fixture_dir, "expected.json")

            if File.dir?(fixture_dir) and File.exists?(source_file) and
                 File.exists?(expected_file) do
              [{category <> "/" <> name, source_file, expected_file}]
            else
              []
            end
          end)
        else
          []
        end
      end)
    else
      []
    end

  if all_fixtures == [] do
    corpus_path = Path.expand("../../wpl/conformance/compile/fixtures", __DIR__)
    @corpus_path corpus_path
    @tag :skip
    test "corpus not found" do
      IO.puts(
        "\n[conformance] compile-conformance corpus not found at #{@corpus_path}; " <>
          "skipped (set WPL_CORPUS_DIR to enable)"
      )
    end
  else
    for {label, source_file, expected_file} <- all_fixtures do
      @label label
      @source_file source_file
      @expected_file expected_file

      test "compile-conformance: #{@label}" do
        source = File.read!(@source_file)
        expected_raw = @expected_file |> File.read!() |> :elixir_json.decode()

        assert {:ok, compiled, _repairs} = WplAi.to_wpl(source),
               "[conformance/#{@label}] compilation failed"

        got = normalize_value(compiled)
        want = normalize_value(expected_raw)

        assert got == want,
               "[conformance/#{@label}] output mismatch.\n" <>
                 "Got:  #{inspect(got, pretty: true)}\n\n" <>
                 "Want: #{inspect(want, pretty: true)}"

        # Pass-1 schema + pass-2 semantic validation must produce zero errors.
        vr = WPL.Validator.validate(compiled)
        error_findings = Enum.filter(vr.errors, &(&1.severity == :error))

        if error_findings != [] do
          formatted =
            Enum.map_join(error_findings, "\n", fn e ->
              "  #{e.code} #{e.path}: #{e.message}"
            end)

          flunk("[conformance/#{@label}] compiled output failed validation:\n#{formatted}")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Invalid-parser conformance: invalid/parser/* fixtures
  # ---------------------------------------------------------------------------

  invalid_parser_fixtures_dir =
    Path.expand("../../wpl/conformance/invalid/parser", __DIR__)

  invalid_parser_fixtures =
    if File.dir?(invalid_parser_fixtures_dir) do
      invalid_parser_fixtures_dir
      |> File.ls!()
      |> Enum.sort()
      |> Enum.flat_map(fn name ->
        fixture_dir = Path.join(invalid_parser_fixtures_dir, name)
        source_file = Path.join(fixture_dir, "source.wpl")
        expected_file = Path.join(fixture_dir, "expected.json")

        if File.dir?(fixture_dir) and File.exists?(source_file) and File.exists?(expected_file) do
          [{name, source_file, expected_file}]
        else
          []
        end
      end)
    else
      []
    end

  for {label, source_file, expected_file} <- invalid_parser_fixtures do
    @label label
    @source_file source_file
    @expected_file expected_file

    test "invalid-parser-conformance: #{@label}" do
      source = File.read!(@source_file)
      expected_errors = @expected_file |> File.read!() |> :elixir_json.decode()

      assert {:error, errors} = WplAi.Parser.parse(source),
             "[conformance/invalid/parser/#{@label}] expected parse to fail but it succeeded"

      for expected <- expected_errors do
        expected_type = Map.get(expected, "type")
        expected_message = Map.get(expected, "message")
        expected_kind = Map.get(expected, "kind", "parse")

        # Verify at least one error matches the expected type and message.
        match =
          Enum.any?(errors, fn error ->
            type_ok =
              is_nil(expected_type) or to_string(error.type) == expected_type

            message_ok =
              is_nil(expected_message) or error.message == expected_message

            kind_ok =
              expected_kind == "parse"

            type_ok and message_ok and kind_ok
          end)

        unless match do
          got_messages = Enum.map_join(errors, "\n  ", &"#{&1.type}: #{&1.message}")

          flunk(
            "[conformance/invalid/parser/#{@label}] no error matched expected:\n" <>
              "  type: #{expected_type}, message: #{expected_message}\n" <>
              "Got errors:\n  #{got_messages}"
          )
        end
      end
    end
  end
end
