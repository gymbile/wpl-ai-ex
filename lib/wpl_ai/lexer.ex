defmodule WplAi.Lexer do
  @moduledoc """
  Lexer for WPL-AI language.

  Handles tokenization including Python-style significant indentation,
  producing INDENT and DEDENT tokens for the parser.

  ## Features

  - Significant indentation (2 or 4 spaces, must be consistent)
  - Keywords, identifiers, strings, numbers
  - Dates (YYYY-MM-DD) and times (HH:MM)
  - Comments starting with #
  - Operators and punctuation
  """

  alias WplAi.Errors.{LexerError, Location}

  # Token types
  # Structure
  @type token_type ::
          :indent
          | :dedent
          | :newline
          | :eof
          # Keywords
          | :keyword
          # Literals
          | :string
          | :number
          | :date
          | :time
          | :datetime
          # Identifiers
          | :ident
          | :bare_word
          # Operators
          | :arrow
          | :range
          | :colon
          | :comma
          | :lparen
          | :rparen
          | :eq
          | :neq
          | :gte
          | :lte
          | :gt
          | :lt
          | :plus
          | :minus
          | :percent
          | :slash
          | :times

  @type token :: {token_type(), any(), Location.t()}

  @keywords ~w(
    PLAN TYPE VISIBILITY DIFFICULTY DURATION TAGS LANGUAGE MIN_APP_VERSION SCHEMA
    GOALS GOAL REQUIRES PERSONALIZATION INPUTS RULES WHEN
    PHASES PHASE WEEK DAY
    PROGRESS NOTIFICATIONS RENDERING
    primary secondary
    workout nutrition meditation recovery hybrid
    private public template
    beginner intermediate advanced adaptive
    training rest active_recovery assessment
    warmup main cooldown education
    circuit straight_sets superset emom amrap tabata
    cardio habit
    morning afternoon evening any strict flexible
    age fitness equipment contraindication time
    required optional alternatives
    target deadline milestone reward badge at
    name description
    enabled disabled
    checkpoints points achievements streaks
    checkpoint trigger measure ask
    achievement condition
    total zone intensity duration guided audio
    timing suggestions protein carbs fat calories
    frequency reminders
    rounds rest_between_rounds
    schedule notes
    HABITS HABIT FREQUENCY TRIGGER DESCRIPTION
    AND OR
    contains not_contains
    reduce modify add replace exclude remove increase
    scope
    activity block day week phase plan
    rpe rir tempo rest weight
    before after in
    seconds minutes hours days weeks
    kg lbs percentage_1rm
    meters km miles
    heart_rate_zone bpm pace
    bodyweight
    absolute relative percentage
    true false
    sides both left right
    rules types
    work
    x
    muscles model power
    chest upper_back lats traps front_delts side_delts rear_delts
    biceps triceps forearms abs obliques lower_back spinal_erectors
    glutes quadriceps hamstrings calves hip_adductors hip_abductors hip_flexors neck
    squat hinge lunge push_horizontal push_vertical pull_horizontal pull_vertical
    carry rotate anti_rotate gait jump isolation
    hr_3_zone_seiler hr_5_zone hr_7_zone power_coggan_7_zone pace_critical_speed rpe_borg_10 rpe_borg_20
    ATHLETE_THRESHOLDS
    hr_max lthr resting_hr ftp vo2max critical_pace body_weight one_rm
    watts
    pattern
  )a

  @doc """
  Tokenize WPL-AI source text.

  Returns `{:ok, tokens}` or `{:error, [LexerError.t()]}`.
  """
  @spec tokenize(String.t()) :: {:ok, [token()]} | {:error, [LexerError.t()]}
  def tokenize(source) do
    # Normalize line endings
    source = String.replace(source, "\r\n", "\n")

    state = %{
      source: source,
      pos: 0,
      line: 1,
      column: 1,
      indent_stack: [0],
      indent_unit: nil,
      tokens: [],
      errors: []
    }

    case do_tokenize(state) do
      %{errors: []} = final_state ->
        tokens = finalize_tokens(final_state)
        {:ok, tokens}

      %{errors: errors} ->
        {:error, Enum.reverse(errors)}
    end
  end

  # Main tokenization loop
  defp do_tokenize(%{pos: pos, source: source} = state) when pos >= byte_size(source) do
    # End of file - emit any remaining dedents
    emit_eof(state)
  end

  defp do_tokenize(state) do
    state
    |> skip_blank_lines_and_comments()
    |> tokenize_line()
    |> do_tokenize()
  end

  # Skip blank lines and comments at the start of logical lines
  defp skip_blank_lines_and_comments(state) do
    case peek(state) do
      "\n" ->
        state
        |> advance()
        |> increment_line()
        |> skip_blank_lines_and_comments()

      "#" ->
        state
        |> skip_comment()
        |> skip_blank_lines_and_comments()

      _ when state.column == 1 ->
        # At start of a non-blank line, check for leading whitespace before comment
        case peek_line_start(state) do
          {:comment, spaces} ->
            state
            |> advance_by(spaces)
            |> skip_comment()
            |> skip_blank_lines_and_comments()

          _ ->
            state
        end

      _ ->
        state
    end
  end

  defp peek_line_start(state) do
    rest = binary_part(state.source, state.pos, byte_size(state.source) - state.pos)

    case Regex.run(~r/^([ ]*)#/, rest) do
      [_, spaces] -> {:comment, byte_size(spaces)}
      _ -> nil
    end
  end

  # Tokenize a single logical line
  defp tokenize_line(%{pos: pos, source: source} = state) when pos >= byte_size(source) do
    state
  end

  defp tokenize_line(state) do
    # Handle indentation at start of line
    state =
      if state.column == 1 do
        handle_indentation(state)
      else
        state
      end

    # Tokenize the rest of the line
    tokenize_line_content(state)
  end

  defp tokenize_line_content(%{pos: pos, source: source} = state) when pos >= byte_size(source) do
    state
  end

  defp tokenize_line_content(state) do
    case peek(state) do
      # End of line
      "\n" ->
        state
        |> emit_token(:newline, nil)
        |> advance()
        |> increment_line()

      # Whitespace within line - skip
      " " ->
        state
        |> advance()
        |> tokenize_line_content()

      # Tab - error
      "\t" ->
        loc = current_location(state)

        state
        |> add_error(LexerError.tab_character(loc))
        |> advance()
        |> tokenize_line_content()

      # Comment - skip to end of line
      "#" ->
        skip_comment(state)

      # String literal
      "\"" ->
        tokenize_string(state)

      # Operators and punctuation
      ":" ->
        state |> emit_token(:colon, ":") |> advance() |> tokenize_line_content()

      "," ->
        state |> emit_token(:comma, ",") |> advance() |> tokenize_line_content()

      "(" ->
        state |> emit_token(:lparen, "(") |> advance() |> tokenize_line_content()

      ")" ->
        state |> emit_token(:rparen, ")") |> advance() |> tokenize_line_content()

      "/" ->
        state |> emit_token(:slash, "/") |> advance() |> tokenize_line_content()

      "%" ->
        state |> emit_token(:percent, "%") |> advance() |> tokenize_line_content()

      "+" ->
        state |> emit_token(:plus, "+") |> advance() |> tokenize_line_content()

      "*" ->
        state |> emit_token(:times, "*") |> advance() |> tokenize_line_content()

      "-" ->
        tokenize_minus_or_arrow(state)

      "." ->
        tokenize_dots(state)

      "=" ->
        tokenize_equals(state)

      "!" ->
        tokenize_not_equals(state)

      ">" ->
        tokenize_greater(state)

      "<" ->
        tokenize_less(state)

      c when c in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] ->
        tokenize_number(state)

      c when (c >= "A" and c <= "Z") or (c >= "a" and c <= "z") or c == "_" ->
        tokenize_identifier(state)

      other ->
        loc = current_location(state)

        state
        |> add_error(LexerError.invalid_character(other, loc))
        |> advance()
        |> tokenize_line_content()
    end
  end

  # Handle indentation at the start of a line
  defp handle_indentation(state) do
    {spaces, state} = count_leading_spaces(state)
    current_indent = hd(state.indent_stack)

    cond do
      spaces > current_indent ->
        handle_indent(state, spaces)

      spaces < current_indent ->
        handle_dedent(state, spaces)

      true ->
        # Same indentation level
        state
    end
  end

  defp count_leading_spaces(state, count \\ 0) do
    case peek(state) do
      " " ->
        count_leading_spaces(advance(state), count + 1)

      "\t" ->
        loc = current_location(state)
        state = add_error(state, LexerError.tab_character(loc))
        count_leading_spaces(advance(state), count + 4)

      _ ->
        {count, state}
    end
  end

  defp handle_indent(state, spaces) do
    current_indent = hd(state.indent_stack)
    diff = spaces - current_indent

    # Determine or validate indent unit
    state =
      case state.indent_unit do
        nil ->
          # First indentation - set the unit (2 or 4 spaces)
          if diff in [2, 4] do
            %{state | indent_unit: diff}
          else
            loc = current_location(state)

            add_error(
              state,
              LexerError.inconsistent_indentation("2 or 4", diff, loc)
            )
          end

        unit when diff == unit ->
          state

        unit ->
          loc = current_location(state)
          add_error(state, LexerError.inconsistent_indentation(unit, diff, loc))
      end

    state
    |> emit_token(:indent, spaces)
    |> Map.update!(:indent_stack, &[spaces | &1])
  end

  defp handle_dedent(state, spaces) do
    do_handle_dedent(state, spaces)
  end

  defp do_handle_dedent(state, target_spaces) do
    [current | rest] = state.indent_stack

    cond do
      current == target_spaces ->
        state

      rest == [] ->
        # Can't dedent below 0
        loc = current_location(state)
        add_error(state, LexerError.unexpected_dedent(loc))

      hd(rest) >= target_spaces ->
        state
        |> emit_token(:dedent, hd(rest))
        |> Map.put(:indent_stack, rest)
        |> do_handle_dedent(target_spaces)

      true ->
        # Target spaces doesn't match any indent level
        loc = current_location(state)
        add_error(state, LexerError.unexpected_dedent(loc))
    end
  end

  # Tokenize string literal
  defp tokenize_string(state) do
    start_loc = current_location(state)
    state = advance(state)
    tokenize_string_content(state, start_loc, [])
  end

  defp tokenize_string_content(state, start_loc, acc) do
    case peek(state) do
      nil ->
        add_error(state, LexerError.unterminated_string(start_loc))

      "\n" ->
        add_error(state, LexerError.unterminated_string(start_loc))

      "\"" ->
        value = acc |> Enum.reverse() |> IO.iodata_to_binary()

        state
        |> advance()
        |> emit_token_at(:string, value, start_loc)
        |> tokenize_line_content()

      "\\" ->
        state = advance(state)

        case peek(state) do
          "\"" ->
            tokenize_string_content(advance(state), start_loc, ["\"" | acc])

          "\\" ->
            tokenize_string_content(advance(state), start_loc, ["\\" | acc])

          "n" ->
            tokenize_string_content(advance(state), start_loc, ["\n" | acc])

          "t" ->
            tokenize_string_content(advance(state), start_loc, ["\t" | acc])

          other ->
            tokenize_string_content(advance(state), start_loc, [other | acc])
        end

      c ->
        tokenize_string_content(advance(state), start_loc, [c | acc])
    end
  end

  # Tokenize minus or arrow
  defp tokenize_minus_or_arrow(state) do
    case peek(state, 1) do
      ">" ->
        state
        |> emit_token(:arrow, "->")
        |> advance_by(2)
        |> tokenize_line_content()

      c when c in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] ->
        tokenize_number(state)

      _ ->
        state
        |> emit_token(:minus, "-")
        |> advance()
        |> tokenize_line_content()
    end
  end

  # Tokenize dots (range operator)
  defp tokenize_dots(state) do
    case peek(state, 1) do
      "." ->
        state
        |> emit_token(:range, "..")
        |> advance_by(2)
        |> tokenize_line_content()

      _ ->
        # Single dot - part of identifier or slug
        tokenize_identifier(state)
    end
  end

  # Tokenize equals or comparison
  defp tokenize_equals(state) do
    case peek(state, 1) do
      "=" ->
        state
        |> emit_token(:eq, "==")
        |> advance_by(2)
        |> tokenize_line_content()

      _ ->
        state
        |> emit_token(:eq, "=")
        |> advance()
        |> tokenize_line_content()
    end
  end

  # Tokenize not equals
  defp tokenize_not_equals(state) do
    case peek(state, 1) do
      "=" ->
        state
        |> emit_token(:neq, "!=")
        |> advance_by(2)
        |> tokenize_line_content()

      _ ->
        loc = current_location(state)

        state
        |> add_error(LexerError.invalid_character("!", loc))
        |> advance()
        |> tokenize_line_content()
    end
  end

  # Tokenize greater than
  defp tokenize_greater(state) do
    case peek(state, 1) do
      "=" ->
        state
        |> emit_token(:gte, ">=")
        |> advance_by(2)
        |> tokenize_line_content()

      _ ->
        state
        |> emit_token(:gt, ">")
        |> advance()
        |> tokenize_line_content()
    end
  end

  # Tokenize less than
  defp tokenize_less(state) do
    case peek(state, 1) do
      "=" ->
        state
        |> emit_token(:lte, "<=")
        |> advance_by(2)
        |> tokenize_line_content()

      _ ->
        state
        |> emit_token(:lt, "<")
        |> advance()
        |> tokenize_line_content()
    end
  end

  # Tokenize number (integer, decimal, date, time, or datetime)
  defp tokenize_number(state) do
    start_loc = current_location(state)
    {text, state} = consume_number_like(state)

    cond do
      # DateTime: 2024-01-15T10:30 or 2024-01-15T10:30:00Z
      String.match?(text, ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?Z?$/) ->
        state
        |> emit_token_at(:datetime, text, start_loc)
        |> tokenize_line_content()

      # Date: YYYY-MM-DD
      String.match?(text, ~r/^\d{4}-\d{2}-\d{2}$/) ->
        case Date.from_iso8601(text) do
          {:ok, date} ->
            state
            |> emit_token_at(:date, date, start_loc)
            |> tokenize_line_content()

          {:error, _} ->
            state
            |> add_error(LexerError.invalid_date(text, start_loc))
            |> tokenize_line_content()
        end

      # Time: HH:MM
      String.match?(text, ~r/^\d{2}:\d{2}$/) ->
        case Time.from_iso8601(text <> ":00") do
          {:ok, time} ->
            state
            |> emit_token_at(:time, time, start_loc)
            |> tokenize_line_content()

          {:error, _} ->
            state
            |> add_error(LexerError.invalid_time(text, start_loc))
            |> tokenize_line_content()
        end

      # Number with unit suffix (e.g., 60s, 2m, 45m)
      String.match?(text, ~r/^-?\d+(\.\d+)?[smhd]$/) ->
        {num_str, unit} = String.split_at(text, -1)

        case parse_number(num_str) do
          {:ok, num} ->
            state
            |> emit_token_at(:number, num, start_loc)
            |> emit_token(:bare_word, unit)
            |> tokenize_line_content()

          :error ->
            state
            |> add_error(LexerError.invalid_number(text, start_loc))
            |> tokenize_line_content()
        end

      # Plain number
      true ->
        case parse_number(text) do
          {:ok, num} ->
            state
            |> emit_token_at(:number, num, start_loc)
            |> tokenize_line_content()

          :error ->
            state
            |> add_error(LexerError.invalid_number(text, start_loc))
            |> tokenize_line_content()
        end
    end
  end

  defp consume_number_like(state, acc \\ []) do
    case peek(state) do
      # Colon is only valid in date/time patterns (after 4 digits for time, or after date for datetime)
      ":" ->
        # Check if this looks like a time pattern (digits before AND after colon).
        # The after-colon check matters: without it, "WEEK 10:" would be consumed
        # as a 3-char token `10:` because `10` matches the HH prefix — but since
        # no MM digits follow, it then fails `parse_number` with
        # "Invalid number format '10:'". "WEEK 1:" doesn't hit this because `1`
        # fails the `\d{2}` prefix check and the colon boundary stops consumption.
        acc_str = acc |> Enum.reverse() |> IO.iodata_to_binary()
        next_char = peek(state, 1)
        next_is_digit = is_binary(next_char) and next_char >= "0" and next_char <= "9"

        time_prefix? =
          String.match?(acc_str, ~r/^\d{4}-\d{2}-\d{2}T\d{2}$/) or
            String.match?(acc_str, ~r/^\d{2}$/)

        if time_prefix? and next_is_digit do
          # Valid time or datetime pattern - continue
          consume_number_like(advance(state), [":" | acc])
        else
          # Not a time pattern - stop here (this is likely "10:" in "WEEK 10:"
          # or "1:" in "WEEK 1:"). Let the caller emit a bare number + colon.
          {acc |> Enum.reverse() |> IO.iodata_to_binary(), state}
        end

      # Handle dots carefully - single dot for decimals, but ".." is range operator
      "." ->
        if peek(state, 1) == "." do
          # This is ".." range operator - stop here
          {acc |> Enum.reverse() |> IO.iodata_to_binary(), state}
        else
          # Single dot - part of decimal number
          consume_number_like(advance(state), ["." | acc])
        end

      c when c in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "T", "Z"] ->
        consume_number_like(advance(state), [c | acc])

      # `-` inside a number-like token is only valid when it's a leading
      # negative sign (acc empty) or an ISO date separator (`2025-01-15`).
      # Greedily consuming `-` otherwise breaks on natural text the LLM
      # emits — `7-day rolling`, `RPE 6-7`, `age 45-60` — where parse_number
      # then rejects `7-` / `6-7` / `45-60` and aborts lexing.
      "-" ->
        acc_str = acc |> Enum.reverse() |> IO.iodata_to_binary()
        next_char = peek(state, 1)
        next_is_digit = is_binary(next_char) and next_char >= "0" and next_char <= "9"

        leading_negative? = acc == [] and next_is_digit

        iso_date_prefix? =
          next_is_digit and
            (String.match?(acc_str, ~r/^-?\d{4}$/) or
               String.match?(acc_str, ~r/^-?\d{4}-\d{2}$/))

        if leading_negative? or iso_date_prefix? do
          consume_number_like(advance(state), ["-" | acc])
        else
          {acc_str, state}
        end

      # Allow trailing unit letters
      c when c in ["s", "m", "h", "d"] and acc != [] ->
        # Check if next char would continue an identifier
        case peek(state, 1) do
          next when next >= "a" and next <= "z" ->
            # It's an identifier, stop here
            {acc |> Enum.reverse() |> IO.iodata_to_binary(), state}

          _ ->
            num_text = acc |> Enum.reverse() |> IO.iodata_to_binary()
            {num_text <> c, advance(state)}
        end

      _ ->
        {acc |> Enum.reverse() |> IO.iodata_to_binary(), state}
    end
  end

  defp parse_number(text) do
    cond do
      String.contains?(text, ".") ->
        case Float.parse(text) do
          {num, ""} -> {:ok, num}
          _ -> :error
        end

      true ->
        case Integer.parse(text) do
          {num, ""} -> {:ok, num}
          _ -> :error
        end
    end
  end

  # Tokenize identifier or keyword
  defp tokenize_identifier(state) do
    start_loc = current_location(state)
    {text, state} = consume_identifier(state)

    # Check if it's a keyword
    token_type =
      cond do
        String.to_atom(text) in @keywords -> :keyword
        String.match?(text, ~r/^[A-Z]/) -> :keyword
        true -> :bare_word
      end

    state
    |> emit_token_at(token_type, text, start_loc)
    |> tokenize_line_content()
  end

  defp consume_identifier(state, acc \\ []) do
    case peek(state) do
      # Special case: "x" followed by digit is a separator in exercise patterns (e.g., "3x10")
      # Stop consuming if we have just "x" and next char is a digit
      c when c >= "0" and c <= "9" ->
        acc_str = acc |> Enum.reverse() |> IO.iodata_to_binary()

        if acc_str == "x" do
          # Don't consume the digit - let "x" be its own token
          {acc_str, state}
        else
          consume_identifier(advance(state), [c | acc])
        end

      c
      when (c >= "A" and c <= "Z") or (c >= "a" and c <= "z") or c in ["_", "-", "."] ->
        consume_identifier(advance(state), [c | acc])

      _ ->
        {acc |> Enum.reverse() |> IO.iodata_to_binary(), state}
    end
  end

  # Skip comment to end of line
  defp skip_comment(state) do
    case peek(state) do
      "\n" ->
        state
        |> emit_token(:newline, nil)
        |> advance()
        |> increment_line()

      nil ->
        state

      _ ->
        skip_comment(advance(state))
    end
  end

  # Emit remaining dedents and EOF
  defp emit_eof(state) do
    state = emit_remaining_dedents(state)

    state
    |> emit_token(:eof, nil)
  end

  defp emit_remaining_dedents(state) do
    case state.indent_stack do
      [0] ->
        state

      [_ | rest] ->
        state
        |> emit_token(:dedent, if(rest == [], do: 0, else: hd(rest)))
        |> Map.put(:indent_stack, rest)
        |> emit_remaining_dedents()
    end
  end

  # Finalize token list
  defp finalize_tokens(state) do
    state.tokens
    |> Enum.reverse()
    |> remove_redundant_newlines()
  end

  defp remove_redundant_newlines(tokens) do
    tokens
    |> Enum.reduce({[], nil}, fn
      {:newline, _, _}, {acc, :newline} ->
        # Skip consecutive newlines
        {acc, :newline}

      {:newline, _, _} = tok, {acc, _} ->
        {[tok | acc], :newline}

      tok, {acc, _} ->
        {[tok | acc], elem(tok, 0)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # Helper functions

  defp peek(%{pos: pos, source: source}, offset \\ 0) do
    target = pos + offset

    if target < byte_size(source) do
      binary_part(source, target, 1)
    else
      nil
    end
  end

  defp advance(state) do
    %{state | pos: state.pos + 1, column: state.column + 1}
  end

  defp advance_by(state, n) do
    %{state | pos: state.pos + n, column: state.column + n}
  end

  defp increment_line(state) do
    %{state | line: state.line + 1, column: 1}
  end

  defp current_location(state) do
    Location.new(state.line, state.column)
  end

  defp emit_token(state, type, value) do
    loc = current_location(state)
    token = {type, value, loc}
    %{state | tokens: [token | state.tokens]}
  end

  defp emit_token_at(state, type, value, location) do
    token = {type, value, location}
    %{state | tokens: [token | state.tokens]}
  end

  defp add_error(state, error) do
    %{state | errors: [error | state.errors]}
  end
end
