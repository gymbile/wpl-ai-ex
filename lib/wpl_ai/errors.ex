defmodule WplAi.Errors do
  @moduledoc """
  Error types for WPL-AI lexer and parser.

  Provides structured errors with line/column information for
  helpful feedback to LLMs and humans.
  """

  defmodule Location do
    @moduledoc "Source location (line and column)"
    defstruct [:line, :column, :length]

    @type t :: %__MODULE__{
            line: pos_integer(),
            column: pos_integer(),
            length: non_neg_integer() | nil
          }

    def new(line, column, length \\ nil) do
      %__MODULE__{line: line, column: column, length: length}
    end
  end

  defmodule LexerError do
    @moduledoc "Error during lexical analysis"
    defstruct [:type, :message, :location, :context]

    @type error_type ::
            :invalid_character
            | :unterminated_string
            | :invalid_number
            | :invalid_date
            | :invalid_time
            | :inconsistent_indentation
            | :tab_character
            | :unexpected_dedent

    @type t :: %__MODULE__{
            type: error_type(),
            message: String.t(),
            location: Location.t(),
            context: String.t() | nil
          }

    def new(type, message, location, context \\ nil) do
      %__MODULE__{type: type, message: message, location: location, context: context}
    end

    def invalid_character(char, location) do
      new(
        :invalid_character,
        "Invalid character '#{char}'",
        location,
        "Only ASCII letters, digits, and standard punctuation are allowed"
      )
    end

    def unterminated_string(location) do
      new(
        :unterminated_string,
        "Unterminated string literal",
        location,
        "String must be closed with a double quote"
      )
    end

    def invalid_number(text, location) do
      new(
        :invalid_number,
        "Invalid number format '#{text}'",
        location,
        "Numbers must be integers or decimals (e.g., 42, 3.14, -5)"
      )
    end

    def invalid_date(text, location) do
      new(
        :invalid_date,
        "Invalid date format '#{text}'",
        location,
        "Dates must be in ISO format: YYYY-MM-DD"
      )
    end

    def invalid_time(text, location) do
      new(
        :invalid_time,
        "Invalid time format '#{text}'",
        location,
        "Times must be in 24-hour format: HH:MM"
      )
    end

    def inconsistent_indentation(expected, got, location) do
      new(
        :inconsistent_indentation,
        "Inconsistent indentation: expected #{expected} spaces, got #{got}",
        location,
        "Use consistent indentation (2 or 4 spaces) throughout the document"
      )
    end

    def tab_character(location) do
      new(
        :tab_character,
        "Tab character not allowed",
        location,
        "Use spaces for indentation, not tabs"
      )
    end

    def unexpected_dedent(location) do
      new(
        :unexpected_dedent,
        "Unexpected dedent",
        location,
        "Indentation decreased to an invalid level"
      )
    end
  end

  defmodule ParseError do
    @moduledoc "Error during parsing"
    defstruct [:type, :message, :location, :expected, :got, :suggestions, :repair_hint]

    @type error_type ::
            :unexpected_token
            | :unexpected_eof
            | :missing_required
            | :invalid_value
            | :invalid_keyword
            | :duplicate_section
            | :invalid_structure
            | :unknown_exercise_ref
            | :week_has_no_valid_days

    @type repair_hint :: %{
            optional(:action) => atom(),
            optional(:target_path) => String.t(),
            optional(:parent_name) => String.t() | nil,
            optional(:missing) => [String.t() | non_neg_integer()] | nil,
            optional(:expected_count) => non_neg_integer() | nil,
            optional(:actual_count) => non_neg_integer() | nil,
            optional(:allowed_values) => [String.t()] | nil,
            optional(:expected_shape) => String.t() | nil,
            optional(:context_dsl_example) => String.t() | nil
          }

    @type t :: %__MODULE__{
            type: error_type(),
            message: String.t(),
            location: Location.t() | nil,
            expected: [String.t()] | nil,
            got: String.t() | nil,
            suggestions: [String.t()] | nil,
            repair_hint: repair_hint() | nil
          }

    def new(type, message, opts \\ []) do
      %__MODULE__{
        type: type,
        message: message,
        location: Keyword.get(opts, :location),
        expected: Keyword.get(opts, :expected),
        got: Keyword.get(opts, :got),
        suggestions: Keyword.get(opts, :suggestions),
        repair_hint: Keyword.get(opts, :repair_hint)
      }
    end

    def unexpected_token(expected, got, location) do
      expected_str =
        case expected do
          [single] -> "'#{single}'"
          multiple -> "one of: #{Enum.map_join(multiple, ", ", &"'#{&1}'")}"
        end

      new(
        :unexpected_token,
        "Unexpected token: expected #{expected_str}, got '#{got}'",
        location: location,
        expected: expected,
        got: got
      )
    end

    def unexpected_eof(expected) do
      expected_str =
        case expected do
          [single] -> "'#{single}'"
          multiple -> "one of: #{Enum.map_join(multiple, ", ", &"'#{&1}'")}"
        end

      new(
        :unexpected_eof,
        "Unexpected end of file: expected #{expected_str}",
        expected: expected
      )
    end

    def missing_required(field, section, location) do
      new(
        :missing_required,
        "Missing required field '#{field}' in #{section}",
        location: location,
        expected: [field]
      )
    end

    def invalid_value(field, value, valid_values, location) do
      suggestions =
        if is_list(valid_values) do
          Enum.map(valid_values, &to_string/1)
        else
          nil
        end

      new(
        :invalid_value,
        "Invalid value '#{value}' for #{field}",
        location: location,
        got: to_string(value),
        suggestions: suggestions
      )
    end

    def invalid_keyword(keyword, context, location, valid_keywords) do
      new(
        :invalid_keyword,
        "Unknown keyword '#{keyword}' in #{context}",
        location: location,
        got: keyword,
        suggestions: valid_keywords
      )
    end

    def duplicate_section(section, location) do
      new(
        :duplicate_section,
        "Duplicate section '#{section}'",
        location: location,
        got: section
      )
    end

    def invalid_structure(message, location) do
      new(
        :invalid_structure,
        message,
        location: location
      )
    end

    @day_block_dsl_example """
          DAY Monday training 45m "Session name":
            warmup:
              cycling 5m zone2
            main straight_sets:
              <exercise_name> 3x8..12 rpe 7 rest 90 seconds
            cooldown:
              <stretch_name> 30s\
    """

    @doc """
    Emitted when a `WEEK N:` block contains content that is not a valid
    `DAY` block (e.g. the LLM wrote `Monday: walk/run` as an inline summary
    instead of `DAY Monday training 45m "..."`). Without this error the
    parser silently discarded the malformed week body, the compiler
    produced a week with empty days, and only the downstream
    `:phase_duration_mismatch` validator caught the gap.

    Mirrors the TypeScript factory `weekHasNoValidDays` in
    `@gymbile/wpl-ai` 1.11.0.
    """
    def week_has_no_valid_days(week_number, got_token, location)
        when is_integer(week_number) do
      week_label = "WEEK #{week_number}"

      repair_hint = %{
        action: :add_days,
        target_path: "/plan/weeks/#{week_number}/days",
        parent_name: "Week #{week_number}",
        expected_shape:
          "DAY <name> training <duration> \"<label>\": (with warmup/main/cooldown body)",
        context_dsl_example: @day_block_dsl_example
      }

      new(
        :week_has_no_valid_days,
        "#{week_label} block has no valid DAY children (found '#{got_token}'). " <>
          "Use 'DAY <name> training Nm \"...\":' syntax — inline 'Monday: ...' " <>
          "summaries are not valid WPL-AI.",
        location: location,
        expected: ["DAY"],
        got: got_token,
        repair_hint: repair_hint
      )
    end

    def unknown_exercise_ref(ref, location, suggestions \\ []) do
      new(
        :unknown_exercise_ref,
        "Unknown exercise reference '#{ref}'",
        location: location,
        got: ref,
        suggestions: suggestions
      )
    end
  end

  defmodule CompileError do
    @moduledoc "Error during compilation to WPL JSON"
    defstruct [:type, :message, :path, :details]

    @type error_type ::
            :missing_section
            | :invalid_reference
            | :duration_mismatch
            | :constraint_violation

    @type t :: %__MODULE__{
            type: error_type(),
            message: String.t(),
            path: [String.t()] | nil,
            details: map() | nil
          }

    def new(type, message, opts \\ []) do
      %__MODULE__{
        type: type,
        message: message,
        path: Keyword.get(opts, :path),
        details: Keyword.get(opts, :details)
      }
    end

    def missing_section(section, plan_type) do
      new(
        :missing_section,
        "Plan type '#{plan_type}' requires section '#{section}'",
        details: %{section: section, plan_type: plan_type}
      )
    end

    def invalid_reference(ref_type, ref_value, path) do
      new(
        :invalid_reference,
        "Invalid #{ref_type} reference '#{ref_value}'",
        path: path,
        details: %{ref_type: ref_type, ref_value: ref_value}
      )
    end

    def duration_mismatch(header_duration, computed_duration) do
      new(
        :duration_mismatch,
        "Header duration (#{header_duration}) doesn't match computed duration (#{computed_duration})",
        details: %{header: header_duration, computed: computed_duration}
      )
    end
  end

  # =============================================================================
  # Error Formatting
  # =============================================================================

  @doc """
  Format an error for display, including source context if available.
  """
  def format_error(error, source \\ nil)

  def format_error(%LexerError{} = error, source) do
    base = "[Lexer Error] #{error.message}"
    location = format_location(error.location)
    context = if error.context, do: "\n  Hint: #{error.context}", else: ""
    source_line = if source, do: "\n" <> format_source_line(source, error.location), else: ""

    "#{base} at #{location}#{context}#{source_line}"
  end

  def format_error(%ParseError{} = error, source) do
    base = "[Parse Error] #{error.message}"
    location = if error.location, do: " at #{format_location(error.location)}", else: ""

    suggestions =
      if error.suggestions && error.suggestions != [] do
        "\n  Did you mean: #{Enum.join(error.suggestions, ", ")}?"
      else
        ""
      end

    source_line =
      if source && error.location do
        "\n" <> format_source_line(source, error.location)
      else
        ""
      end

    "#{base}#{location}#{suggestions}#{source_line}"
  end

  def format_error(%CompileError{} = error, _source) do
    base = "[Compile Error] #{error.message}"
    path = if error.path, do: "\n  At: #{Enum.join(error.path, " > ")}", else: ""

    "#{base}#{path}"
  end

  defp format_location(%Location{line: line, column: column}) do
    "line #{line}, column #{column}"
  end

  defp format_location(nil), do: "unknown location"

  defp format_source_line(source, %Location{line: line, column: column}) do
    lines = String.split(source, "\n")

    if line <= length(lines) do
      source_line = Enum.at(lines, line - 1)
      pointer = String.duplicate(" ", max(column - 1, 0)) <> "^"
      "  #{line} | #{source_line}\n      #{pointer}"
    else
      ""
    end
  end

  @doc """
  Format multiple errors for display.
  """
  def format_errors(errors, source \\ nil) when is_list(errors) do
    errors
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {error, index} ->
      "#{index}. #{format_error(error, source)}"
    end)
  end

  @doc """
  Create a result tuple from errors.
  """
  def error_result(errors) when is_list(errors) do
    {:error, errors}
  end

  def error_result(error) do
    {:error, [error]}
  end

  # =============================================================================
  # LLM-Friendly Error Formatting (for retry mechanism)
  # =============================================================================

  @doc """
  Format errors for LLM retry - structured feedback that helps the LLM fix issues.

  This format is optimized for sending back to the LLM to help it self-correct.
  It includes:
  - Clear error descriptions with line numbers
  - Specific suggestions for fixes
  - The problematic source line
  - Context about what was expected

  ## Examples

      iex> format_for_llm([error], source)
      \"\"\"
      Your WPL-AI output has errors. Please fix and regenerate:

      ERROR 1: [Line 5] Unknown exercise reference 'pushup'
        → Did you mean: push_up
        → Source: pushup 3x10 rpe 7

      Remember:
      - Exercise names use snake_case: push_up, pull_up, bench_press
      - Use exactly 2 spaces for indentation
      \"\"\"

  """
  def format_for_llm(errors, source) when is_list(errors) do
    error_text =
      errors
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {error, index} ->
        format_error_for_llm(error, source, index)
      end)

    reminders = build_reminders(errors)

    """
    Your WPL-AI output has errors. Please fix and regenerate:

    #{error_text}

    #{reminders}
    Output ONLY the corrected WPL-AI text, no explanations.
    """
  end

  defp format_error_for_llm(%LexerError{} = error, source, index) do
    location = format_location_compact(error.location)
    source_line = get_source_line(source, error.location)
    hint = if error.context, do: "\n  → Hint: #{error.context}", else: ""

    """
    ERROR #{index}: [#{location}] #{error.message}#{hint}
      → Source: #{source_line}
    """
    |> String.trim()
  end

  defp format_error_for_llm(%ParseError{} = error, source, index) do
    location =
      if error.location do
        "[#{format_location_compact(error.location)}] "
      else
        ""
      end

    source_line =
      if error.location do
        "\n  → Source: #{get_source_line(source, error.location)}"
      else
        ""
      end

    suggestions =
      if error.suggestions && error.suggestions != [] do
        "\n  → Did you mean: #{Enum.join(error.suggestions, ", ")}"
      else
        ""
      end

    expected =
      if error.expected && error.expected != [] do
        "\n  → Expected: #{Enum.join(error.expected, " or ")}"
      else
        ""
      end

    """
    ERROR #{index}: #{location}#{error.message}#{suggestions}#{expected}#{source_line}
    """
    |> String.trim()
  end

  defp format_error_for_llm(%CompileError{} = error, _source, index) do
    path =
      if error.path do
        " at #{Enum.join(error.path, " → ")}"
      else
        ""
      end

    "ERROR #{index}: #{error.message}#{path}"
  end

  defp format_location_compact(%Location{line: line, column: col}) do
    "Line #{line}, Col #{col}"
  end

  defp format_location_compact(nil), do: ""

  defp get_source_line(source, %Location{line: line}) when is_binary(source) do
    lines = String.split(source, "\n")

    if line > 0 && line <= length(lines) do
      Enum.at(lines, line - 1) |> String.trim()
    else
      "(source not available)"
    end
  end

  defp get_source_line(_, _), do: "(source not available)"

  # Build context-aware reminders based on error types
  defp build_reminders(errors) do
    error_types = Enum.map(errors, &get_error_type/1) |> Enum.uniq()

    reminders =
      error_types
      |> Enum.flat_map(&reminders_for_type/1)
      |> Enum.uniq()
      |> Enum.take(4)

    if reminders != [] do
      "Remember:\n" <> Enum.map_join(reminders, "\n", &("- " <> &1))
    else
      ""
    end
  end

  defp get_error_type(%LexerError{type: type}), do: type
  defp get_error_type(%ParseError{type: type}), do: type
  defp get_error_type(%CompileError{type: type}), do: type
  defp get_error_type(_), do: :unknown

  defp reminders_for_type(:unknown_exercise_ref) do
    [
      "Exercise names use snake_case: push_up, pull_up, bench_press",
      "Check the exercise library in the system prompt"
    ]
  end

  defp reminders_for_type(:inconsistent_indentation) do
    [
      "Use exactly 2 spaces for each indentation level",
      "Do not use tabs, only spaces"
    ]
  end

  defp reminders_for_type(:tab_character) do
    [
      "Use spaces for indentation, not tabs",
      "Each level should have exactly 2 spaces"
    ]
  end

  defp reminders_for_type(:unexpected_token) do
    [
      "Check that keywords are spelled correctly (PLAN, TYPE, PHASES, etc.)",
      "Ensure proper structure: PLAN → TYPE → PHASES → PHASE → WEEK → DAY"
    ]
  end

  defp reminders_for_type(:missing_required) do
    [
      "Required fields: PLAN name, TYPE, at least one PHASE",
      "Each DAY needs warmup, main, and cooldown blocks"
    ]
  end

  defp reminders_for_type(:invalid_value) do
    [
      "Valid TYPEs: workout, nutrition, meditation, recovery, hybrid",
      "Valid DIFFICULTYs: beginner, intermediate, advanced"
    ]
  end

  defp reminders_for_type(_), do: []

  @doc """
  Format WPL validation errors for LLM retry.

  Takes string-based validation errors (from WPL.validate/1) and the original
  WPL-AI source text, returning structured feedback to help the LLM self-correct.

  Includes context-aware reminders based on error keywords.

  ## Examples

      iex> format_validation_errors_for_llm(["Goal 1: missing required field 'name'"], source)
      \"\"\"
      Your plan compiled to JSON but failed WPL validation. Fix these issues:

      1. Goal 1: missing required field 'name'

      Remember:
      - Every GOAL must have `name "..."` as a quoted string
      ...
      \"\"\"

  """
  def format_validation_errors_for_llm(errors, _source) when is_list(errors) do
    error_text =
      errors
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {error, index} ->
        "#{index}. #{error}"
      end)

    reminders = build_validation_reminders(errors)

    """
    Your plan compiled to JSON but failed WPL validation. Fix these issues:

    #{error_text}

    #{reminders}
    Output ONLY the corrected WPL-AI text, no explanations.
    """
  end

  # Build context-aware reminders based on validation error keywords
  defp build_validation_reminders(errors) do
    error_text = Enum.join(errors, " ")
    lowered = String.downcase(error_text)

    reminders =
      []
      |> maybe_add_reminder(
        lowered,
        "goal",
        "Every GOAL must have `name \"...\"` as a quoted string"
      )
      |> maybe_add_reminder(lowered, "name", "Goal names are required: `name \"Build Strength\"`")
      |> maybe_add_reminder(
        lowered,
        "phase",
        "Workout/nutrition/hybrid plans need PHASE with WEEK and DAY"
      )
      |> maybe_add_reminder(
        lowered,
        "type",
        "Valid TYPEs: workout, nutrition, meditation, recovery, hybrid"
      )
      |> maybe_add_reminder(
        lowered,
        "difficulty",
        "Valid DIFFICULTYs: beginner, intermediate, advanced"
      )
      |> maybe_add_reminder(
        lowered,
        "activity",
        "Activities use format: `exercise_name sets_x_reps` or `nutrition meal|snack:`"
      )
      |> maybe_add_reminder(lowered, "week", "Each PHASE must contain at least one WEEK")
      |> maybe_add_reminder(lowered, "day", "Each WEEK must contain at least one DAY")
      |> Enum.uniq()
      |> Enum.take(4)

    if reminders != [] do
      "Remember:\n" <> Enum.map_join(reminders, "\n", &("- " <> &1))
    else
      ""
    end
  end

  defp maybe_add_reminder(reminders, text, keyword, reminder) do
    if String.contains?(text, keyword), do: [reminder | reminders], else: reminders
  end

  @doc """
  Extract error summary for quick display (one line per error).
  """
  def error_summary(errors) when is_list(errors) do
    errors
    |> Enum.map(&error_one_line/1)
    |> Enum.join("; ")
  end

  defp error_one_line(%LexerError{message: msg, location: loc}) do
    "Line #{loc.line}: #{msg}"
  end

  defp error_one_line(%ParseError{message: msg, location: loc}) when not is_nil(loc) do
    "Line #{loc.line}: #{msg}"
  end

  defp error_one_line(%ParseError{message: msg}) do
    msg
  end

  defp error_one_line(%CompileError{message: msg}) do
    msg
  end
end
