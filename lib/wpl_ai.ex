defmodule WplAi do
  @moduledoc """
  WPL-AI: Human and AI-friendly authoring language for wellness plans.

  This module provides the public API for parsing, validating, and
  working with WPL-AI documents.

  ## Overview

  WPL-AI is a linear, indentation-based language designed to be easily
  written by both humans and LLMs. It compiles to canonical WPL JSON.

  ## Architecture

  ```
  LLM / Human
       ↓
    WPL-AI text
       ↓
  [Parser] → AST
       ↓
  [Compiler] → WPL JSON
       ↓
  Validation • Personalization • Rendering
  ```

  ## Example

      iex> source = \"""
      ...> PLAN "Upper Body Beginner"
      ...> TYPE workout
      ...> DIFFICULTY beginner
      ...>
      ...> PHASES
      ...>   PHASE "Foundation" (2 weeks):
      ...>     WEEK 1:
      ...>       DAY Monday training 45m "Upper Body":
      ...>         warmup:
      ...>           jumping_jacks 2m
      ...>         main straight_sets:
      ...>           push_up 3x8..12 target 10 rpe 7
      ...> \"""
      iex> {:ok, ast} = WplAi.parse(source)
      iex> ast.header.name
      "Upper Body Beginner"

  """

  alias WplAi.{AST, Compiler, Decompiler, Errors, Lexer, Parser}

  @doc """
  Parse WPL-AI source text into an AST.

  Returns `{:ok, AST.Document.t()}` on success, or `{:error, errors}` on failure.

  ## Examples

      iex> WplAi.parse("PLAN \\"Test\\"\\nTYPE workout")
      {:ok, %WplAi.AST.Document{header: %WplAi.AST.Header{name: "Test", type: :workout}}}

  """
  @spec parse(String.t()) :: {:ok, AST.Document.t()} | {:error, list()}
  def parse(source) when is_binary(source) do
    Parser.parse(source)
  end

  @doc """
  Parse WPL-AI source text into an AST, raising on error.

  ## Examples

      iex> WplAi.parse!("PLAN \\"Test\\"\\nTYPE workout")
      %WplAi.AST.Document{header: %WplAi.AST.Header{name: "Test", type: :workout}}

  """
  @spec parse!(String.t()) :: AST.Document.t()
  def parse!(source) when is_binary(source) do
    case parse(source) do
      {:ok, document} -> document
      {:error, errors} -> raise "WPL-AI parse error: #{Errors.format_errors(errors, source)}"
    end
  end

  @doc """
  Compile a WPL-AI AST document to WPL JSON format.

  Returns `{:ok, json_map}` on success, or `{:error, errors}` on failure.

  ## Examples

      iex> {:ok, ast} = WplAi.parse("PLAN \\"Test\\"\\nTYPE workout")
      iex> {:ok, json} = WplAi.compile(ast)
      iex> json["plan"]["name"]
      "Test"

  """
  @spec compile(AST.Document.t()) :: {:ok, map()} | {:error, list()}
  def compile(%AST.Document{} = doc) do
    Compiler.compile(doc)
  end

  @doc """
  Compile a WPL-AI AST document to WPL JSON format, raising on error.
  """
  @spec compile!(AST.Document.t()) :: map()
  def compile!(%AST.Document{} = doc) do
    Compiler.compile!(doc)
  end

  @doc """
  Parse and compile WPL-AI source text to WPL JSON in one step.

  Returns `{:ok, json_map}` on success, or `{:error, errors}` on failure.

  ## Examples

      iex> {:ok, json} = WplAi.to_wpl("PLAN \\"Test\\"\\nTYPE workout")
      iex> json["plan"]["name"]
      "Test"

  """
  @spec to_wpl(String.t()) :: {:ok, map()} | {:error, list()}
  def to_wpl(source) when is_binary(source) do
    with {:ok, doc} <- parse(source),
         {:ok, json} <- compile(doc) do
      {:ok, json}
    end
  end

  @doc """
  Parse and compile WPL-AI source text to WPL JSON, raising on error.
  """
  @spec to_wpl!(String.t()) :: map()
  def to_wpl!(source) when is_binary(source) do
    source
    |> parse!()
    |> compile!()
  end

  @doc """
  Decompile WPL JSON to WPL-AI text.

  This enables editing existing plans in the LLM-friendly format
  and round-trip transformation.

  Returns `{:ok, text}` on success, or `{:error, reason}` on failure.

  ## Examples

      iex> {:ok, text} = WplAi.decompile(json)
      iex> String.starts_with?(text, "PLAN")
      true

  """
  @spec decompile(map()) :: {:ok, String.t()} | {:error, term()}
  def decompile(json) when is_map(json) do
    Decompiler.decompile(json)
  end

  @doc """
  Decompile WPL JSON to WPL-AI text, raising on error.
  """
  @spec decompile!(map()) :: String.t()
  def decompile!(json) when is_map(json) do
    Decompiler.decompile!(json)
  end

  @doc """
  Convert WPL-AI text to WPL JSON and back to WPL-AI (round-trip).

  Useful for normalizing WPL-AI text or testing round-trip correctness.

  ## Examples

      iex> {:ok, normalized} = WplAi.round_trip(source)

  """
  @spec round_trip(String.t()) :: {:ok, String.t()} | {:error, term()}
  def round_trip(source) when is_binary(source) do
    with {:ok, json} <- to_wpl(source),
         {:ok, text} <- decompile(json) do
      {:ok, text}
    end
  end

  @doc """
  Tokenize WPL-AI source text.

  Returns `{:ok, tokens}` on success, or `{:error, errors}` on failure.
  Useful for debugging or building syntax highlighters.

  ## Examples

      iex> {:ok, tokens} = WplAi.tokenize("PLAN \\"Test\\"")
      iex> length(tokens)
      3  # PLAN keyword, string, EOF

  """
  @spec tokenize(String.t()) :: {:ok, [Lexer.token()]} | {:error, list()}
  def tokenize(source) when is_binary(source) do
    Lexer.tokenize(source)
  end

  @doc """
  Validate WPL-AI source text without fully parsing.

  Returns `:ok` if valid, or `{:error, errors}` if invalid.
  This is faster than full parsing when you only need validation.

  ## Examples

      iex> WplAi.validate("PLAN \\"Test\\"\\nTYPE workout")
      :ok

      iex> WplAi.validate("INVALID")
      {:error, _}

  """
  @spec validate(String.t()) :: :ok | {:error, list()}
  def validate(source) when is_binary(source) do
    case parse(source) do
      {:ok, _} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end

  @doc """
  Format parse errors for display.

  ## Examples

      iex> {:error, errors} = WplAi.parse("INVALID")
      iex> WplAi.format_errors(errors)
      "1. [Parse Error] ..."

  """
  @spec format_errors(list(), String.t() | nil) :: String.t()
  def format_errors(errors, source \\ nil) do
    Errors.format_errors(errors, source)
  end

  @doc """
  Get the WPL-AI language version.
  """
  @spec version() :: String.t()
  def version, do: "0.1"

  # =============================================================================
  # AST Inspection Helpers
  # =============================================================================

  @doc """
  Get all exercise references from a parsed document.

  Useful for validating that all exercises exist in the library.

  ## Examples

      iex> {:ok, doc} = WplAi.parse(source)
      iex> WplAi.exercise_refs(doc)
      ["push_up", "squat", "plank"]

  """
  @spec exercise_refs(AST.Document.t()) :: [String.t()]
  def exercise_refs(%AST.Document{} = doc) do
    doc.phases
    |> Enum.flat_map(fn phase ->
      phase.weeks
      |> Enum.flat_map(fn week ->
        week.days
        |> Enum.flat_map(fn day ->
          day.blocks
          |> Enum.flat_map(fn block ->
            block.activities
            |> Enum.flat_map(&extract_exercise_ref/1)
          end)
        end)
      end)
    end)
    |> Enum.uniq()
  end

  defp extract_exercise_ref(%AST.Exercise{exercise_ref: ref}), do: [ref]
  defp extract_exercise_ref(_), do: []

  @doc """
  Get all activity types used in a parsed document.

  ## Examples

      iex> {:ok, doc} = WplAi.parse(source)
      iex> WplAi.activity_types(doc)
      [:exercise, :cardio, :meditation]

  """
  @spec activity_types(AST.Document.t()) :: [atom()]
  def activity_types(%AST.Document{} = doc) do
    doc.phases
    |> Enum.flat_map(fn phase ->
      phase.weeks
      |> Enum.flat_map(fn week ->
        week.days
        |> Enum.flat_map(fn day ->
          day.blocks
          |> Enum.flat_map(fn block ->
            Enum.map(block.activities, &activity_type/1)
          end)
        end)
      end)
    end)
    |> Enum.uniq()
  end

  defp activity_type(%AST.Exercise{}), do: :exercise
  defp activity_type(%AST.Cardio{}), do: :cardio
  defp activity_type(%AST.Nutrition{}), do: :nutrition
  defp activity_type(%AST.Meditation{}), do: :meditation
  defp activity_type(%AST.Recovery{}), do: :recovery
  defp activity_type(%AST.RecoveryExercise{}), do: :recovery_exercise
  defp activity_type(%AST.Habit{}), do: :habit
  defp activity_type(%AST.SimpleActivity{}), do: :simple

  @doc """
  Calculate total duration from phases in a parsed document.

  Returns duration in days.
  """
  @spec total_duration_days(AST.Document.t()) :: integer()
  def total_duration_days(%AST.Document{} = doc) do
    doc.phases
    |> Enum.map(fn phase ->
      case phase.duration do
        %AST.Duration{value: v, unit: :weeks} -> trunc(v * 7)
        %AST.Duration{value: v, unit: :days} -> trunc(v)
        _ -> 0
      end
    end)
    |> Enum.sum()
  end

  @doc """
  Count activities by type in a parsed document.

  ## Examples

      iex> {:ok, doc} = WplAi.parse(source)
      iex> WplAi.activity_counts(doc)
      %{exercise: 15, cardio: 3, meditation: 2}

  """
  @spec activity_counts(AST.Document.t()) :: map()
  def activity_counts(%AST.Document{} = doc) do
    doc.phases
    |> Enum.flat_map(fn phase ->
      phase.weeks
      |> Enum.flat_map(fn week ->
        week.days
        |> Enum.flat_map(fn day ->
          day.blocks
          |> Enum.flat_map(fn block ->
            block.activities
          end)
        end)
      end)
    end)
    |> Enum.reduce(%{}, fn activity, acc ->
      type = activity_type(activity)
      Map.update(acc, type, 1, &(&1 + 1))
    end)
  end
end
