defmodule WplAi.Parser do
  @moduledoc """
  Parser for WPL-AI language.

  Builds an AST from tokens produced by the Lexer.
  Uses recursive descent parsing.
  """

  alias WplAi.AST
  alias WplAi.ExerciseMatcher
  alias WplAi.Lexer
  alias WplAi.Errors.{ParseError, Location}

  @type repair :: %{:type => atom(), :message => String.t(), optional(atom()) => any()}

  @type parse_state :: %{
          tokens: [Lexer.token()],
          pos: non_neg_integer(),
          errors: [ParseError.t()],
          repairs: [repair()]
        }

  @doc """
  Parse WPL-AI source text into an AST.

  Returns `{:ok, AST.Document.t(), [repair()]}` on success, or `{:error, errors}` on failure.
  """
  @spec parse(String.t()) :: {:ok, AST.Document.t(), [repair()]} | {:error, list()}
  def parse(source) do
    case Lexer.tokenize(source) do
      {:ok, tokens} ->
        parse_tokens(tokens)

      {:error, lexer_errors} ->
        {:error, lexer_errors}
    end
  end

  @doc """
  Parse tokens into an AST (for testing with pre-tokenized input).
  """
  @spec parse_tokens([Lexer.token()]) :: {:ok, AST.Document.t(), [repair()]} | {:error, list()}
  def parse_tokens(tokens) do
    state = %{
      tokens: tokens,
      pos: 0,
      errors: [],
      repairs: []
    }

    case parse_document(state) do
      {:ok, document, %{errors: [], repairs: repairs}} ->
        {:ok, document, Enum.reverse(repairs)}

      {:ok, _document, %{errors: errors}} ->
        {:error, Enum.reverse(errors)}

      {:error, errors} ->
        {:error, errors}
    end
  end

  # =============================================================================
  # Repair Helpers
  # =============================================================================

  defp add_repair(state, repair) when is_map(repair) do
    %{state | repairs: [repair | state.repairs]}
  end

  # =============================================================================
  # Document Parsing
  # =============================================================================

  defp parse_document(state) do
    state = skip_newlines(state)

    with {:ok, header, state} <- parse_header(state),
         state <- skip_newlines(state),
         {:ok, sections, state} <- parse_sections(state) do
      document = %AST.Document{
        header: header,
        goals: sections[:goals],
        requirements: sections[:requirements],
        personalization: sections[:personalization],
        phases: sections[:phases] || [],
        habits: sections[:habits],
        progress: sections[:progress],
        notifications: sections[:notifications],
        rendering: sections[:rendering],
        athlete_thresholds: sections[:athlete_thresholds]
      }

      {:ok, document, state}
    end
  end

  # =============================================================================
  # Header Parsing
  # =============================================================================

  defp parse_header(state) do
    with {:ok, name, state} <- expect_plan_name(state),
         state <- skip_newlines(state),
         {:ok, attrs, state} <- parse_header_attributes(state, %{}) do
      header = %AST.Header{
        name: name,
        type: Map.get(attrs, :type),
        visibility: Map.get(attrs, :visibility),
        difficulty: Map.get(attrs, :difficulty),
        duration: Map.get(attrs, :duration),
        tags: Map.get(attrs, :tags),
        language: Map.get(attrs, :language),
        min_app_version: Map.get(attrs, :min_app_version),
        schema: Map.get(attrs, :schema)
      }

      if is_nil(header.type) do
        {:error, [ParseError.missing_required("TYPE", "header", current_location(state))]}
      else
        {:ok, header, state}
      end
    end
  end

  defp expect_plan_name(state) do
    case current_token(state) do
      {:keyword, "PLAN", _loc} ->
        state = advance(state)

        case current_token(state) do
          {:string, name, _} ->
            {:ok, name, advance(state)}

          {type, value, loc} ->
            {:error, [ParseError.unexpected_token(["string"], "#{type}:#{value}", loc)]}
        end

      {type, value, loc} ->
        {:error, [ParseError.unexpected_token(["PLAN"], "#{type}:#{value}", loc)]}
    end
  end

  defp parse_header_attributes(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "TYPE", _} ->
        state = advance(state)
        {:ok, value, state} = expect_bare_word(state)
        type = parse_plan_type(value)
        parse_header_attributes(state, Map.put(attrs, :type, type))

      {:keyword, "VISIBILITY", _} ->
        state = advance(state)
        {:ok, value, state} = expect_bare_word(state)
        visibility = parse_visibility(value)
        parse_header_attributes(state, Map.put(attrs, :visibility, visibility))

      {:keyword, "DIFFICULTY", _} ->
        state = advance(state)
        {:ok, value, state} = expect_bare_word(state)
        difficulty = parse_difficulty(value)
        parse_header_attributes(state, Map.put(attrs, :difficulty, difficulty))

      {:keyword, "DURATION", _} ->
        state = advance(state)
        {:ok, duration, state} = parse_duration(state)
        parse_header_attributes(state, Map.put(attrs, :duration, duration))

      {:keyword, "TAGS", _} ->
        state = advance(state)
        {:ok, tags, state} = parse_tag_list(state)
        parse_header_attributes(state, Map.put(attrs, :tags, tags))

      {:keyword, "LANGUAGE", _} ->
        state = advance(state)
        {:ok, value, state} = expect_bare_word(state)
        parse_header_attributes(state, Map.put(attrs, :language, value))

      {:keyword, "MIN_APP_VERSION", _} ->
        state = advance(state)
        {:ok, value, state} = expect_string(state)
        parse_header_attributes(state, Map.put(attrs, :min_app_version, value))

      {:keyword, "SCHEMA", _} ->
        state = advance(state)
        {:ok, value, state} = expect_string(state)
        parse_header_attributes(state, Map.put(attrs, :schema, value))

      _ ->
        {:ok, attrs, state}
    end
  end

  defp parse_plan_type(value) do
    case value do
      "workout" -> :workout
      "nutrition" -> :nutrition
      "meditation" -> :meditation
      "recovery" -> :recovery
      "hybrid" -> :hybrid
      # Models occasionally emit non-canonical TYPE values (e.g. `summary`,
      # `program`) for prose-y plan headers. The downstream safety contract
      # doesn't depend on plan_type — it gates exercise validity inside the
      # plan, not the plan-type label. Silently fall back to the canonical
      # default rather than blocking the entire compile.
      _ -> :workout
    end
  end

  defp parse_visibility(value) do
    case value do
      "private" -> :private
      "public" -> :public
      "template" -> :template
      _ -> :private
    end
  end

  defp parse_difficulty(value) do
    case value do
      "beginner" -> :beginner
      "intermediate" -> :intermediate
      "advanced" -> :advanced
      "adaptive" -> :adaptive
      _ -> String.to_atom(value)
    end
  end

  # =============================================================================
  # Sections Parsing
  # =============================================================================

  defp parse_sections(state, sections \\ %{}) do
    state = skip_newlines(state)
    state = skip_dedents(state)

    case current_token(state) do
      {:keyword, "GOALS", _} ->
        {:ok, goals, state} = parse_goals_section(state)
        parse_sections(state, Map.put(sections, :goals, goals))

      {:keyword, "REQUIRES", _} ->
        {:ok, requirements, state} = parse_requires_section(state)
        parse_sections(state, Map.put(sections, :requirements, requirements))

      {:keyword, "PERSONALIZATION", _} ->
        {:ok, personalization, state} = parse_personalization_section(state)
        parse_sections(state, Map.put(sections, :personalization, personalization))

      {:keyword, "PHASES", _} ->
        {:ok, phases, state} = parse_phases_section(state)
        parse_sections(state, Map.put(sections, :phases, phases))

      {:keyword, "PROGRESS", _} ->
        {:ok, progress, state} = parse_progress_section(state)
        parse_sections(state, Map.put(sections, :progress, progress))

      {:keyword, "NOTIFICATIONS", _} ->
        {:ok, notifications, state} = parse_notifications_section(state)
        parse_sections(state, Map.put(sections, :notifications, notifications))

      {:keyword, "RENDERING", _} ->
        {:ok, rendering, state} = parse_rendering_section(state)
        parse_sections(state, Map.put(sections, :rendering, rendering))

      {:keyword, "HABITS", _} ->
        {:ok, habits, state} = parse_habits_section(state)
        parse_sections(state, Map.put(sections, :habits, habits))

      {:keyword, "ATHLETE_THRESHOLDS", _} ->
        {:ok, thresholds, state} = parse_athlete_thresholds_section(state)
        parse_sections(state, Map.put(sections, :athlete_thresholds, thresholds))

      {:eof, _, _} ->
        {:ok, sections, state}

      # Models commonly emit free-form ALL-CAPS top-level blocks like
      # `NUTRITION:`, `SUMMARY:`, `NOTES:` after the canonical PHASES section.
      # These aren't part of the grammar, but they don't change the safety
      # contract — they're prose annotations. Skip the whole sub-block
      # (keyword + colon + indented body) silently so the compile succeeds.
      {:keyword, caps_kw, loc} ->
        if Regex.match?(~r/^[A-Z_]+$/, caps_kw) and
             match?({:colon, _, _}, current_token(advance(state))) do
          # Fail-closed: safety-adjacent section names (REQUIRE*, CONTRA*,
          # SAFETY*, PRECAUTION*, MEDICAL*, CLEARANCE*) are hard parse errors.
          # A typo here would silently erase contraindications with no trace.
          if Regex.match?(~r/^(REQUIRE|CONTRA|SAFETY|PRECAUTION|MEDICAL|CLEARANCE)/, caps_kw) do
            error =
              ParseError.invalid_structure(
                "Safety-adjacent section '#{caps_kw}:' is not a recognised WPL-AI keyword. " <>
                  "A typo here would silently erase contraindications. " <>
                  "Did you mean REQUIRES?",
                loc
              )

            state = %{state | errors: [error | state.errors]}
            {:error, Enum.reverse(state.errors)}
          else
            # Non-safety unknown section: record repair and skip body.
            state = advance(state)
            # skip keyword
            state = advance(state)
            # skip ":"
            state = skip_newlines(state)

            state =
              case current_token(state) do
                {:indent, _, _} ->
                  state = advance(state)
                  skip_until_matching_dedent(state, 1)

                _ ->
                  state
              end

            state =
              add_repair(state, %{
                type: :skipped_section,
                section: caps_kw,
                message: "Unknown top-level section \"#{caps_kw}\" skipped"
              })

            parse_sections(state, sections)
          end
        else
          # Not an ALL-CAPS block header — skip one token and keep looking.
          parse_sections(advance(state), sections)
        end

      # Tolerant fallback: subagent-generated sections sometimes leave an
      # unexpected token in the stream when their body grammar drifts from
      # what the parser expects (e.g. uppercase AGE/FITNESS in REQUIRES,
      # inline RULE in PERSONALIZATION, MEAL/PROTEIN in a nutrition day).
      # If we simply returned here, PHASES (and every other later section)
      # would silently disappear. Skip the offending token and keep looking.
      _ ->
        parse_sections(advance(state), sections)
    end
  end

  defp skip_until_matching_dedent(state, 0), do: state

  defp skip_until_matching_dedent(state, depth) do
    case current_token(state) do
      {:indent, _, _} ->
        skip_until_matching_dedent(advance(state), depth + 1)

      {:dedent, _, _} ->
        skip_until_matching_dedent(advance(state), depth - 1)

      {:eof, _, _} ->
        state

      _ ->
        skip_until_matching_dedent(advance(state), depth)
    end
  end

  # =============================================================================
  # Goals Section
  # =============================================================================

  defp parse_goals_section(state) do
    state = advance(state)
    state = skip_newlines(state)

    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        {:ok, goals, state} = parse_goals(state, [])
        {:ok, goals, state}

      _ ->
        {:ok, [], state}
    end
  end

  defp parse_goals(state, goals) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "GOAL", _} ->
        {:ok, goal, state} = parse_goal(state)
        parse_goals(state, [goal | goals])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(goals), state}

      _ ->
        {:ok, Enum.reverse(goals), state}
    end
  end

  defp parse_goal(state) do
    state = advance(state)

    {:ok, priority, state} = expect_bare_word(state)
    {:ok, category, state} = expect_bare_word(state)

    state = expect_colon(state)

    # Accept optional inline string target on the same line, e.g.
    # `GOAL primary strength: "squat 1x bodyweight for 5 reps"`. Without this
    # branch the string token leaks past parse_goal and silently kills every
    # subsequent top-level section in parse_sections.
    {inline_description, state} =
      case current_token(state) do
        {:string, s, _} -> {s, advance(state)}
        _ -> {nil, state}
      end

    state = skip_newlines(state)

    {goal_attrs, state} =
      case current_token(state) do
        {:indent, _, _} ->
          state = advance(state)
          parse_goal_body(state, %{})

        _ ->
          {%{}, state}
      end

    goal = %AST.Goal{
      priority: parse_priority(priority),
      category: category,
      name: goal_attrs[:name],
      description: goal_attrs[:description] || inline_description,
      target: goal_attrs[:target],
      deadline: goal_attrs[:deadline],
      milestones: goal_attrs[:milestones]
    }

    {:ok, goal, state}
  end

  defp parse_goal_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "name", _} ->
        state = advance(state)
        {:ok, value, state} = expect_string(state)
        parse_goal_body(state, Map.put(attrs, :name, value))

      {:keyword, "description", _} ->
        state = advance(state)
        {:ok, value, state} = expect_string(state)
        parse_goal_body(state, Map.put(attrs, :description, value))

      {:keyword, "target", _} ->
        state = advance(state)
        {:ok, target, state} = parse_target(state)
        parse_goal_body(state, Map.put(attrs, :target, target))

      {:keyword, "deadline", _} ->
        state = advance(state)
        {:ok, date, state} = expect_date(state)
        parse_goal_body(state, Map.put(attrs, :deadline, date))

      {:keyword, "milestone", _} ->
        {:ok, milestone, state} = parse_milestone(state)
        milestones = Map.get(attrs, :milestones, [])
        parse_goal_body(state, Map.put(attrs, :milestones, milestones ++ [milestone]))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  defp parse_target(state) do
    {:ok, metric, state} = expect_bare_word(state)
    {:ok, value, state} = expect_number(state)
    {:ok, unit, state} = expect_bare_word(state)

    {measurement_type, state} =
      case current_token(state) do
        {:keyword, mt, _} when mt in ["absolute", "relative", "percentage"] ->
          {String.to_atom(mt), advance(state)}

        _ ->
          {:absolute, state}
      end

    target = %AST.Target{
      metric: metric,
      value: value,
      unit: unit,
      measurement_type: measurement_type
    }

    {:ok, target, state}
  end

  defp parse_milestone(state) do
    state = advance(state)
    {:ok, name, state} = expect_string(state)
    state = expect_colon(state)
    state = skip_newlines(state)

    state =
      case current_token(state) do
        {:indent, _, _} -> advance(state)
        _ -> state
      end

    {attrs, state} = parse_milestone_body(state, %{})

    milestone = %AST.Milestone{
      name: name,
      at_value: attrs[:at_value],
      at_unit: attrs[:at_unit],
      reward_points: attrs[:reward_points],
      badge: attrs[:badge]
    }

    {:ok, milestone, state}
  end

  defp parse_milestone_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "at", _} ->
        state = advance(state)
        {:ok, value, state} = expect_number(state)
        {:ok, unit, state} = expect_bare_word(state)
        parse_milestone_body(state, Map.merge(attrs, %{at_value: value, at_unit: unit}))

      {:keyword, "reward", _} ->
        state = advance(state)
        {:ok, points, state} = expect_number(state)
        state = expect_keyword(state, "points")
        parse_milestone_body(state, Map.put(attrs, :reward_points, trunc(points)))

      {:keyword, "badge", _} ->
        state = advance(state)
        {:ok, badge, state} = expect_bare_word(state)
        parse_milestone_body(state, Map.put(attrs, :badge, badge))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  defp parse_priority(value) do
    case value do
      "primary" -> :primary
      "secondary" -> :secondary
      _ -> :primary
    end
  end

  # =============================================================================
  # Requirements Section
  # =============================================================================

  defp parse_requires_section(state) do
    state = advance(state)
    state = skip_newlines(state)

    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        {attrs, state} = parse_requires_body(state, %{})

        requirements = %AST.Requirements{
          age_range: attrs[:age_range],
          fitness_levels: attrs[:fitness_levels],
          equipment: attrs[:equipment],
          contraindications: attrs[:contraindications],
          time_commitment: attrs[:time_commitment]
        }

        {:ok, requirements, state}

      _ ->
        {:ok, %AST.Requirements{}, state}
    end
  end

  defp parse_requires_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "age", _} ->
        state = advance(state)
        {:ok, min_age, state} = expect_number(state)
        state = expect_range(state)
        {:ok, max_age, state} = expect_number(state)
        parse_requires_body(state, Map.put(attrs, :age_range, {trunc(min_age), trunc(max_age)}))

      {:keyword, "fitness", _} ->
        state = advance(state)
        {:ok, levels, state} = parse_enum_list(state)
        parse_requires_body(state, Map.put(attrs, :fitness_levels, levels))

      {:keyword, "equipment", _} ->
        state = advance(state)
        state = expect_colon(state)
        state = skip_newlines(state)
        state = expect_indent(state)
        {:ok, equipment, state} = parse_equipment_list(state, [])
        parse_requires_body(state, Map.put(attrs, :equipment, equipment))

      {:keyword, "contraindication", _} ->
        {:ok, contra, state} = parse_contraindication(state)
        contras = Map.get(attrs, :contraindications, [])
        parse_requires_body(state, Map.put(attrs, :contraindications, contras ++ [contra]))

      {:keyword, "time", _} ->
        state = advance(state)
        state = expect_colon(state)
        state = skip_newlines(state)
        state = expect_indent(state)
        {:ok, time_commitment, state} = parse_time_commitment(state)
        parse_requires_body(state, Map.put(attrs, :time_commitment, time_commitment))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      # Bug 4 fix: emit an explicit parse error for unknown REQUIRES directives.
      # Collect all tokens up to the next newline/dedent as the "line text",
      # emit an invalid_structure error, and continue parsing the block.
      _ ->
        {line_text, state} = collect_line_tokens(state)
        loc = current_location(state)

        error =
          ParseError.invalid_structure(
            "Unknown REQUIRES directive: '#{line_text}'. " <>
              "Recognized: contraindication, fitness, equipment, age, time_commitment.",
            loc
          )

        state = %{state | errors: [error | state.errors]}
        parse_requires_body(state, attrs)
    end
  end

  # Collect tokens on the current line into a text string (for error messages).
  defp collect_line_tokens(state, acc \\ []) do
    case current_token(state) do
      {:newline, _, _} ->
        {acc |> Enum.reverse() |> Enum.join(" "), state}

      {:dedent, _, _} ->
        {acc |> Enum.reverse() |> Enum.join(" "), state}

      {:eof, _, _} ->
        {acc |> Enum.reverse() |> Enum.join(" "), state}

      {_type, value, _} when is_binary(value) ->
        collect_line_tokens(advance(state), [value | acc])

      {_type, value, _} ->
        collect_line_tokens(advance(state), [to_string(value) | acc])
    end
  end

  defp parse_equipment_list(state, equipment) do
    state = skip_newlines(state)

    case current_token(state) do
      # Equipment names may collide with reserved keywords (e.g. "bodyweight"),
      # which the lexer tokenizes as :keyword. Accept both so those names parse.
      {tok, name, _} when tok in [:bare_word, :keyword] ->
        state = advance(state)
        {:ok, flags, state} = parse_equipment_flags(state)

        equip = %AST.Equipment{
          name: name,
          required: flags[:required] || false,
          alternatives: flags[:alternatives]
        }

        parse_equipment_list(state, [equip | equipment])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(equipment), state}

      _ ->
        {:ok, Enum.reverse(equipment), state}
    end
  end

  defp parse_equipment_flags(state) do
    case current_token(state) do
      {:lparen, _, _} ->
        state = advance(state)
        {:ok, flags, state} = parse_equipment_flags_content(state, %{})
        state = expect_rparen(state)
        {:ok, flags, state}

      _ ->
        {:ok, %{}, state}
    end
  end

  defp parse_equipment_flags_content(state, flags) do
    case current_token(state) do
      {:keyword, "required", _} ->
        state = advance(state)
        parse_equipment_flags_content(maybe_skip_comma(state), Map.put(flags, :required, true))

      {:keyword, "optional", _} ->
        state = advance(state)
        parse_equipment_flags_content(maybe_skip_comma(state), Map.put(flags, :required, false))

      {:keyword, "alternatives", _} ->
        state = advance(state)
        state = expect_colon(state)
        {:ok, alts, state} = parse_enum_list(state)

        parse_equipment_flags_content(
          maybe_skip_comma(state),
          Map.put(flags, :alternatives, alts)
        )

      {:rparen, _, _} ->
        {:ok, flags, state}

      _ ->
        {:ok, flags, state}
    end
  end

  # Bug 3 fix: accept colon-qualified contraindication names (acsm:cardiac_rehab_phase_2).
  # The lexer produces bare_word("acsm"), colon, bare_word("cardiac_rehab_phase_2").
  # Glue them into the single string "acsm:cardiac_rehab_phase_2".
  defp expect_contraindication_name(state) do
    {:ok, prefix, state} = expect_bare_word(state)

    case current_token(state) do
      {:colon, _, _} ->
        state = advance(state)
        {:ok, suffix, state} = expect_bare_word(state)
        {:ok, prefix <> ":" <> suffix, state}

      _ ->
        {:ok, prefix, state}
    end
  end

  defp parse_contraindication(state) do
    state = advance(state)
    {:ok, condition, state} = expect_contraindication_name(state)

    # Two forms:
    #   Old: contraindication <name> -> <action> [indented affects block]
    #   New: contraindication <name> [severity <low|moderate|high>] [action <action>]
    case current_token(state) do
      {:arrow, _, _} ->
        # Old arrow form
        state = advance(state)
        action_loc = current_location(state)
        {:ok, action_str, state} = expect_bare_word(state)

        {action, state} =
          if action_str in ["exclude", "modify", "require_clearance"] do
            {parse_contraindication_action(action_str), state}
          else
            error =
              ParseError.invalid_structure(
                "Unknown contraindication action '#{action_str}'. Expected: exclude, modify, require_clearance.",
                action_loc
              )

            state = %{state | errors: [error | state.errors]}
            {:exclude, state}
          end

        {affects_list, state} = parse_contraindication_affects(state)

        contra = %AST.Contraindication{
          condition: condition,
          action: action,
          severity: nil,
          affects: affects_list
        }

        {:ok, contra, state}

      _ ->
        # New keyword form: optional severity, optional action
        {severity, state} =
          case current_token(state) do
            {:keyword, "severity", _} ->
              state = advance(state)

              case current_token(state) do
                {tag, level, _}
                when tag in [:keyword, :bare_word] and level in ["low", "moderate", "high"] ->
                  {String.to_atom(level), advance(state)}

                {_tag, bad_level, loc} ->
                  error =
                    ParseError.invalid_structure(
                      "Unknown contraindication severity '#{bad_level}'. Expected: low, moderate, high.",
                      loc
                    )

                  state = %{state | errors: [error | state.errors]}
                  {nil, advance(state)}
              end

            _ ->
              {nil, state}
          end

        {action, state} =
          case current_token(state) do
            {tag, "action", _} when tag in [:keyword, :bare_word] ->
              state = advance(state)

              case current_token(state) do
                {tag2, action_str, _}
                when tag2 in [:keyword, :bare_word] and
                       action_str in ["exclude", "modify", "require_clearance"] ->
                  {parse_contraindication_action(action_str), advance(state)}

                {_tag2, bad_action, loc} ->
                  error =
                    ParseError.invalid_structure(
                      "Unknown contraindication action '#{bad_action}'. Expected: exclude, modify, require_clearance.",
                      loc
                    )

                  state = %{state | errors: [error | state.errors]}
                  {:exclude, advance(state)}
              end

            _ ->
              {:exclude, state}
          end

        # Optional affects list in parentheses: action modify (squat, lunge)
        {affects_list, state} = parse_contraindication_paren_affects(state)

        contra = %AST.Contraindication{
          condition: condition,
          action: action,
          severity: severity,
          affects: affects_list
        }

        {:ok, contra, state}
    end
  end

  defp parse_contraindication_action(str) do
    case str do
      "exclude" ->
        :exclude

      "modify" ->
        :modify

      "require_clearance" ->
        :require_clearance

      other ->
        raise ArgumentError,
              "parse_contraindication_action/1 called with unvalidated action: #{inspect(other)}"
    end
  end

  defp parse_contraindication_affects(state) do
    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        state = skip_newlines(state)

        case current_token(state) do
          {:keyword, "affects", _} ->
            state = advance(state)
            {:ok, list, state} = parse_enum_list(state)

            state =
              case current_token(state) do
                {:dedent, _, _} -> advance(state)
                _ -> state
              end

            {list, state}

          {:dedent, _, _} ->
            {nil, advance(state)}

          _ ->
            {nil, state}
        end

      _ ->
        {nil, state}
    end
  end

  defp parse_contraindication_paren_affects(state) do
    case current_token(state) do
      {:lparen, _, _} ->
        state = advance(state)
        {:ok, list, state} = parse_enum_list(state)

        state =
          case current_token(state) do
            {:rparen, _, _} -> advance(state)
            _ -> state
          end

        {list, state}

      _ ->
        {nil, state}
    end
  end

  defp parse_time_commitment(state) do
    state = skip_newlines(state)
    {attrs, state} = parse_time_commitment_body(state, %{})

    time = %AST.TimeCommitment{
      days_per_week: attrs[:days_per_week],
      minutes_per_day: attrs[:minutes_per_day]
    }

    {:ok, time, state}
  end

  defp parse_time_commitment_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "days_per_week", _} ->
        state = advance(state)
        {:ok, min, state} = expect_number(state)
        state = expect_range(state)
        {:ok, max, state} = expect_number(state)

        parse_time_commitment_body(
          state,
          Map.put(attrs, :days_per_week, {trunc(min), trunc(max)})
        )

      {:keyword, "minutes_per_day", _} ->
        state = advance(state)
        {:ok, min, state} = expect_number(state)
        state = expect_range(state)
        {:ok, max, state} = expect_number(state)

        parse_time_commitment_body(
          state,
          Map.put(attrs, :minutes_per_day, {trunc(min), trunc(max)})
        )

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  # =============================================================================
  # Personalization Section
  # =============================================================================

  # =============================================================================
  # Habits Section (plan-level)
  # =============================================================================

  defp parse_habits_section(state) do
    state = advance(state)
    state = skip_newlines(state)

    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        {:ok, habits, state} = parse_habits(state, [])
        {:ok, habits, state}

      _ ->
        {:ok, [], state}
    end
  end

  defp parse_habits(state, habits) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "HABIT", _} ->
        {:ok, habit, state} = parse_plan_habit(state)
        parse_habits(state, [habit | habits])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(habits), state}

      _ ->
        {:ok, Enum.reverse(habits), state}
    end
  end

  # `HABIT name: <newline> indented body of DESCRIPTION/FREQUENCY/TRIGGER`.
  defp parse_plan_habit(state) do
    state = advance(state)
    {:ok, name, state} = expect_bare_word_or_keyword(state)
    state = expect_colon(state)
    state = skip_newlines(state)

    {attrs, state} =
      case current_token(state) do
        {:indent, _, _} ->
          state = advance(state)
          parse_plan_habit_body(state, %{})

        _ ->
          {%{}, state}
      end

    habit = %AST.PlanHabit{
      name: name,
      description: attrs[:description],
      frequency: attrs[:frequency],
      trigger: attrs[:trigger]
    }

    {:ok, habit, state}
  end

  defp parse_plan_habit_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {kind, "DESCRIPTION", _} when kind in [:keyword, :bare_word] ->
        state = advance(state)
        {:ok, desc, state} = expect_string(state)
        parse_plan_habit_body(state, Map.put(attrs, :description, desc))

      {kind, "description", _} when kind in [:keyword, :bare_word] ->
        state = advance(state)
        {:ok, desc, state} = expect_string(state)
        parse_plan_habit_body(state, Map.put(attrs, :description, desc))

      {kind, "FREQUENCY", _} when kind in [:keyword, :bare_word] ->
        state = advance(state)
        {:ok, freq, state} = expect_bare_word_or_keyword(state)
        parse_plan_habit_body(state, Map.put(attrs, :frequency, freq))

      {kind, "frequency", _} when kind in [:keyword, :bare_word] ->
        state = advance(state)
        {:ok, freq, state} = expect_bare_word_or_keyword(state)
        parse_plan_habit_body(state, Map.put(attrs, :frequency, freq))

      {kind, "TRIGGER", _} when kind in [:keyword, :bare_word] ->
        state = advance(state)
        {:ok, trig, state} = expect_string(state)
        parse_plan_habit_body(state, Map.put(attrs, :trigger, trig))

      {kind, "trigger", _} when kind in [:keyword, :bare_word] ->
        state = advance(state)
        {:ok, trig, state} = expect_string(state)
        parse_plan_habit_body(state, Map.put(attrs, :trigger, trig))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  # =============================================================================
  # Athlete Thresholds Section (schema v1.3.0+)
  # =============================================================================

  defp parse_athlete_thresholds_section(state) do
    state = advance(state)
    state = skip_newlines(state)

    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        {out, one_rm, state} = parse_athlete_thresholds_body(state, %{}, [])

        thresholds = %AST.AthleteThresholds{
          hr_max_bpm: out[:hr_max_bpm],
          lthr_bpm: out[:lthr_bpm],
          resting_hr_bpm: out[:resting_hr_bpm],
          ftp_watts: out[:ftp_watts],
          vo2max_ml_kg_min: out[:vo2max_ml_kg_min],
          critical_pace_seconds_per_km: out[:critical_pace_seconds_per_km],
          body_weight_kg: out[:body_weight_kg],
          one_rm: if(one_rm == [], do: nil, else: one_rm)
        }

        {:ok, thresholds, state}

      _ ->
        {:ok, %AST.AthleteThresholds{}, state}
    end
  end

  defp parse_athlete_thresholds_body(state, out, one_rm) do
    state = skip_newlines(state)

    case current_token(state) do
      {:dedent, _, _} ->
        {out, Enum.reverse(one_rm), advance(state)}

      {:eof, _, _} ->
        {out, Enum.reverse(one_rm), state}

      {tag, field, _} when tag in [:keyword, :bare_word] ->
        case field do
          "one_rm" ->
            state = advance(state)
            {:ok, exercise_ref, state} = expect_bare_word(state)
            {:ok, value, state} = expect_number(state)
            {unit, state} = consume_optional_weight_unit(state)

            entry = %AST.OneRMEntry{
              exercise_ref: exercise_ref,
              value: value,
              unit: unit
            }

            parse_athlete_thresholds_body(state, out, [entry | one_rm])

          _ ->
            state = advance(state)
            {:ok, value, state} = expect_number(state)
            state = skip_optional_threshold_unit(state)

            out =
              case field do
                "hr_max" -> Map.put(out, :hr_max_bpm, trunc(value))
                "lthr" -> Map.put(out, :lthr_bpm, trunc(value))
                "resting_hr" -> Map.put(out, :resting_hr_bpm, trunc(value))
                "ftp" -> Map.put(out, :ftp_watts, value)
                "vo2max" -> Map.put(out, :vo2max_ml_kg_min, value)
                "critical_pace" -> Map.put(out, :critical_pace_seconds_per_km, value)
                "body_weight" -> Map.put(out, :body_weight_kg, value)
                _ -> out
              end

            parse_athlete_thresholds_body(state, out, one_rm)
        end

      _ ->
        {out, Enum.reverse(one_rm), state}
    end
  end

  # Skips an optional descriptive unit token after a threshold value (e.g. "bpm", "watts", "kg").
  @threshold_units ~w(bpm watts kg lbs)
  defp skip_optional_threshold_unit(state) do
    case current_token(state) do
      {tag, unit, _} when tag in [:keyword, :bare_word] and unit in @threshold_units ->
        advance(state)

      _ ->
        state
    end
  end

  # Consumes an optional weight unit ("kg" / "lb" / "lbs") after a one_rm value.
  # Returns {unit, state} where unit defaults to "kg".
  defp consume_optional_weight_unit(state) do
    case current_token(state) do
      {tag, unit, _} when tag in [:keyword, :bare_word] and unit in ["kg", "lb", "lbs"] ->
        normalized = if unit == "lbs", do: "lb", else: unit
        {normalized, advance(state)}

      _ ->
        {"kg", state}
    end
  end

  defp parse_personalization_section(state) do
    state = advance(state)
    state = skip_newlines(state)

    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        {inputs, rules, state} = parse_personalization_body(state, [], [])

        personalization = %AST.Personalization{
          inputs: if(inputs == [], do: nil, else: inputs),
          rules: rules
        }

        {:ok, personalization, state}

      _ ->
        {:ok, %AST.Personalization{rules: []}, state}
    end
  end

  defp parse_personalization_body(state, inputs, rules) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "INPUTS", _} ->
        state = advance(state)
        state = skip_newlines(state)
        state = expect_indent(state)
        {:ok, new_inputs, state} = parse_inputs(state, [])
        parse_personalization_body(state, inputs ++ new_inputs, rules)

      {:keyword, "RULES", _} ->
        state = advance(state)
        state = skip_newlines(state)
        state = expect_indent(state)
        {:ok, new_rules, state} = parse_rules(state, [])
        parse_personalization_body(state, inputs, rules ++ new_rules)

      {:dedent, _, _} ->
        state = advance(state)
        {inputs, rules, state}

      _ ->
        {inputs, rules, state}
    end
  end

  defp parse_inputs(state, inputs) do
    state = skip_newlines(state)

    case current_token(state) do
      # Accept BOTH bare_word and keyword as the input name. Common input
      # names trainers use — `weight`, `age`, `equipment`, `target`,
      # `intensity` — are reserved keywords in the lexer (see
      # `Lexer.@keywords`). Without this, those declarations slip into the
      # tolerant `_` fallback below and the entire INPUTS block silently
      # drops, leaving `personalization.inputs == []`.
      {kind, name, _} when kind in [:bare_word, :keyword] ->
        state = advance(state)
        state = expect_eq(state)
        {:ok, source, state} = parse_input_source(state)
        state = expect_keyword(state, "as")
        {:ok, type_str, state} = expect_bare_word(state)

        input_type =
          case type_str do
            "number" -> :number
            "string" -> :string
            "array" -> :array
            "enum" -> :enum
            "boolean" -> :boolean
            _ -> :string
          end

        {options, label, state} = parse_input_options_and_label(state, nil, nil)

        input = %AST.Input{
          name: name,
          source: source,
          type: input_type,
          options: options,
          label: label
        }

        parse_inputs(state, [input | inputs])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(inputs), state}

      _ ->
        {:ok, Enum.reverse(inputs), state}
    end
  end

  defp parse_input_source(state) do
    case current_token(state) do
      {:bare_word, source, _} ->
        state = advance(state)
        {:ok, source, state}

      {:keyword, source, _} ->
        state = advance(state)
        {:ok, source, state}

      _ ->
        {:ok, "", state}
    end
  end

  defp parse_input_options_and_label(state, options, label) do
    case current_token(state) do
      {:keyword, "options", _} ->
        state = advance(state)
        state = expect_lparen(state)
        {:ok, opts, state} = parse_enum_list(state)
        state = expect_rparen(state)
        parse_input_options_and_label(state, opts, label)

      {:keyword, "label", _} ->
        state = advance(state)
        {:ok, lbl, state} = expect_string(state)
        parse_input_options_and_label(state, options, lbl)

      _ ->
        {options, label, state}
    end
  end

  defp parse_rules(state, rules) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "WHEN", _} ->
        {:ok, rule, state} = parse_rule(state)
        parse_rules(state, [rule | rules])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(rules), state}

      _ ->
        {:ok, Enum.reverse(rules), state}
    end
  end

  defp parse_rule(state) do
    state = advance(state)
    {:ok, condition, state} = parse_condition(state)
    state = expect_colon(state)
    state = skip_newlines(state)
    state = expect_indent(state)
    {:ok, actions, state} = parse_actions(state, [])

    rule = %AST.Rule{
      condition: condition,
      actions: actions
    }

    {:ok, rule, state}
  end

  defp parse_condition(state) do
    parse_or_expr(state)
  end

  defp parse_or_expr(state) do
    {:ok, left, state} = parse_and_expr(state)

    case current_token(state) do
      {:keyword, "OR", _} ->
        state = advance(state)
        {:ok, right, state} = parse_or_expr(state)

        condition = %AST.Condition{
          type: :compound,
          operator: :or,
          conditions: [left, right]
        }

        {:ok, condition, state}

      _ ->
        {:ok, left, state}
    end
  end

  defp parse_and_expr(state) do
    {:ok, left, state} = parse_predicate(state)

    case current_token(state) do
      {:keyword, "AND", _} ->
        state = advance(state)
        {:ok, right, state} = parse_and_expr(state)

        condition = %AST.Condition{
          type: :compound,
          operator: :and,
          conditions: [left, right]
        }

        {:ok, condition, state}

      _ ->
        {:ok, left, state}
    end
  end

  defp parse_predicate(state) do
    case current_token(state) do
      {:lparen, _, _} ->
        state = advance(state)
        {:ok, condition, state} = parse_condition(state)
        state = expect_rparen(state)
        {:ok, condition, state}

      {:bare_word, _field, _} ->
        parse_simple_predicate(state)

      {:keyword, _field, _} ->
        parse_simple_predicate(state)

      _ ->
        # Return a dummy condition on error
        {:ok, %AST.Condition{type: :simple, field: "unknown", op: :eq, value: nil}, state}
    end
  end

  defp parse_simple_predicate(state) do
    {:ok, field, state} = expect_bare_word_or_keyword(state)
    {op, state} = parse_comparison_op(state)
    {:ok, value, state} = parse_value(state)

    condition = %AST.Condition{
      type: :simple,
      field: field,
      op: op,
      value: value
    }

    {:ok, condition, state}
  end

  defp parse_comparison_op(state) do
    case current_token(state) do
      {:eq, "==", _} -> {:eq, advance(state)}
      {:eq, "=", _} -> {:eq, advance(state)}
      {:neq, _, _} -> {:neq, advance(state)}
      {:gte, _, _} -> {:gte, advance(state)}
      {:lte, _, _} -> {:lte, advance(state)}
      {:gt, _, _} -> {:gt, advance(state)}
      {:lt, _, _} -> {:lt, advance(state)}
      {:keyword, "contains", _} -> {:contains, advance(state)}
      {:keyword, "not_contains", _} -> {:not_contains, advance(state)}
      _ -> {:eq, state}
    end
  end

  defp parse_value(state) do
    case current_token(state) do
      {:number, num, _} ->
        {:ok, num, advance(state)}

      {:string, str, _} ->
        {:ok, str, advance(state)}

      {:bare_word, word, _} ->
        {:ok, word, advance(state)}

      {:keyword, word, _} ->
        {:ok, word, advance(state)}

      _ ->
        {:ok, nil, state}
    end
  end

  defp parse_actions(state, actions) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, action_word, _}
      when action_word in ["reduce", "modify", "add", "replace", "exclude", "remove", "increase"] ->
        {:ok, action, state} = parse_action(state)
        parse_actions(state, [action | actions])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(actions), state}

      _ ->
        {:ok, Enum.reverse(actions), state}
    end
  end

  defp parse_action(state) do
    case current_token(state) do
      {:keyword, "reduce", _} ->
        state = advance(state)
        parse_reduce_action(state)

      {:keyword, "modify", _} ->
        state = advance(state)
        parse_modify_action(state)

      {:keyword, "add", _} ->
        state = advance(state)
        parse_add_action(state)

      {:keyword, "replace", _} ->
        state = advance(state)
        parse_replace_action(state)

      {:keyword, "exclude", _} ->
        state = advance(state)
        parse_exclude_action(state)

      {:keyword, "remove", _} ->
        state = advance(state)
        parse_exclude_action(state)

      {:keyword, "increase", _} ->
        state = advance(state)
        parse_increase_action(state)

      _ ->
        {:ok, %AST.Action{type: :modify_intensity, params: %{}, scope: :plan}, state}
    end
  end

  defp parse_reduce_action(state) do
    case current_token(state) do
      {type, "intensity", _} when type in [:keyword, :bare_word] ->
        state = advance(state)
        state = expect_keyword(state, "by")
        {:ok, value, state} = expect_number(state)
        state = expect_percent(state)
        scope = parse_optional_scope(state)
        {scope_val, state} = scope

        action = %AST.Action{
          type: :modify_intensity,
          params: %{factor: 1 - value / 100},
          scope: scope_val
        }

        {:ok, action, state}

      {type, "sets", _} when type in [:keyword, :bare_word] ->
        state = advance(state)
        state = expect_keyword(state, "by")
        {:ok, value, state} = expect_number(state)
        {scope_val, state} = parse_optional_scope(state)

        action = %AST.Action{
          type: :reduce_sets,
          params: %{amount: trunc(value)},
          scope: scope_val
        }

        {:ok, action, state}

      {type, "reps", _} when type in [:keyword, :bare_word] ->
        state = advance(state)
        state = expect_keyword(state, "by")
        {:ok, value, state} = expect_number(state)
        {scope_val, state} = parse_optional_scope(state)

        action = %AST.Action{
          type: :reduce_reps,
          params: %{amount: trunc(value)},
          scope: scope_val
        }

        {:ok, action, state}

      _ ->
        {:ok, %AST.Action{type: :modify_intensity, params: %{}, scope: :plan}, state}
    end
  end

  defp parse_modify_action(state) do
    state = expect_keyword(state, "intensity")
    state = expect_keyword(state, "factor")
    {:ok, factor, state} = expect_number(state)
    {scope_val, state} = parse_optional_scope(state)

    action = %AST.Action{
      type: :modify_intensity,
      params: %{factor: factor},
      scope: scope_val
    }

    {:ok, action, state}
  end

  defp parse_add_action(state) do
    case current_token(state) do
      {:keyword, "warmup", _} ->
        state = advance(state)
        {:ok, minutes, state} = expect_number(state)
        state = expect_keyword(state, "minutes")
        {scope_val, state} = parse_optional_scope(state)

        action = %AST.Action{
          type: :add_warmup_time,
          params: %{minutes: trunc(minutes)},
          scope: scope_val
        }

        {:ok, action, state}

      {:keyword, "activity", _} ->
        state = advance(state)
        {:ok, activity_name, state} = expect_bare_word(state)
        {placement, state} = parse_optional_placement(state)
        {scope_val, state} = parse_optional_scope(state)

        action = %AST.Action{
          type: :add_activity,
          params: %{activity: activity_name, placement: placement},
          scope: scope_val
        }

        {:ok, action, state}

      _ ->
        {:ok, %AST.Action{type: :add_activity, params: %{}, scope: :plan}, state}
    end
  end

  defp parse_replace_action(state) do
    {:ok, from, state} = expect_bare_word(state)
    state = expect_arrow(state)
    {:ok, to, state} = expect_bare_word(state)
    {scope_val, state} = parse_optional_scope(state)

    action = %AST.Action{
      type: :replace_exercise,
      params: %{from: from, to: to},
      scope: scope_val
    }

    {:ok, action, state}
  end

  defp parse_exclude_action(state) do
    {:ok, exercise, state} = expect_bare_word(state)
    {scope_val, state} = parse_optional_scope(state)

    action = %AST.Action{
      type: :exclude_exercise,
      params: %{exercise: exercise},
      scope: scope_val
    }

    {:ok, action, state}
  end

  defp parse_increase_action(state) do
    state = expect_keyword(state, "rest")
    state = expect_keyword(state, "by")
    {:ok, duration, state} = parse_duration(state)
    {scope_val, state} = parse_optional_scope(state)

    action = %AST.Action{
      type: :increase_rest,
      params: %{duration: duration},
      scope: scope_val
    }

    {:ok, action, state}
  end

  defp parse_optional_scope(state) do
    case current_token(state) do
      {:keyword, "scope", _} ->
        state = advance(state)
        {:ok, scope_str, state} = expect_bare_word(state)

        scope =
          case scope_str do
            "activity" -> :activity
            "block" -> :block
            "day" -> :day
            "week" -> :week
            "phase" -> :phase
            "plan" -> :plan
            _ -> :plan
          end

        {scope, state}

      _ ->
        {:plan, state}
    end
  end

  defp parse_optional_placement(state) do
    case current_token(state) do
      {:keyword, "before", _} ->
        state = advance(state)
        {:ok, target, state} = expect_bare_word(state)
        {{:before, target}, state}

      {:keyword, "after", _} ->
        state = advance(state)
        {:ok, target, state} = expect_bare_word(state)
        {{:after, target}, state}

      {:keyword, "in", _} ->
        state = advance(state)
        {:ok, target, state} = expect_bare_word(state)
        {{:in, target}, state}

      _ ->
        {nil, state}
    end
  end

  # =============================================================================
  # Phases Section
  # =============================================================================

  defp parse_phases_section(state) do
    state = advance(state)
    state = skip_newlines(state)

    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        {:ok, phases, state} = parse_phases(state, [])
        {:ok, phases, state}

      _ ->
        {:ok, [], state}
    end
  end

  defp parse_phases(state, phases) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "PHASE", _} ->
        {:ok, phase, state} = parse_phase(state)
        parse_phases(state, [phase | phases])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(phases), state}

      {:eof, _, _} ->
        {:ok, Enum.reverse(phases), state}

      # Stray token between PHASE blocks — skip forward instead of bailing
      # out, so a garbled bit of one phase's trailing content doesn't drop
      # every subsequent PHASE (nutrition + workout sections often land
      # back-to-back under the PHASES header).
      _ ->
        parse_phases(advance(state), phases)
    end
  end

  @phase_types ~w(accumulation intensification realization deload base build peak recovery transition)

  defp parse_phase(state) do
    state = advance(state)
    {:ok, name, state} = expect_string(state)

    # Optional periodization role (schema v1.5.0+): PHASE "Name" accumulation (4 weeks):
    # Bug 6 fix: detect and reject unknown phase type words with an explicit error.
    {phase_type, state} =
      case current_token(state) do
        {:keyword, word, _loc} when word in @phase_types ->
          {word, advance(state)}

        {:bare_word, word, _loc} when word in @phase_types ->
          {word, advance(state)}

        # An unrecognised bare_word before the opening paren is an unknown phase type.
        {:bare_word, word, loc} ->
          allowed = Enum.join(@phase_types, ", ")

          error =
            ParseError.invalid_structure(
              "Unknown phase type '#{word}'. Allowed: #{allowed}.",
              loc
            )

          state = %{state | errors: [error | state.errors]}
          state = advance(state)
          {nil, state}

        # Same for keyword tokens that are not in the allowed set (e.g. if the
        # lexer classifies the word as a keyword for another reason).
        {:keyword, word, loc}
        when word not in @phase_types and word not in ["WEEK", "PHASE"] ->
          # Only treat it as an unknown phase type if followed by a paren — otherwise
          # it might be a real grammar token that `expect_lparen` will handle gracefully.
          case peek_token(state, 1) do
            {:lparen, _, _} ->
              allowed = Enum.join(@phase_types, ", ")

              error =
                ParseError.invalid_structure(
                  "Unknown phase type '#{word}'. Allowed: #{allowed}.",
                  loc
                )

              state = %{state | errors: [error | state.errors]}
              state = advance(state)
              {nil, state}

            _ ->
              {nil, state}
          end

        _ ->
          {nil, state}
      end

    state = expect_lparen(state)
    {:ok, duration, state} = parse_duration(state)
    state = expect_rparen(state)
    state = expect_colon(state)
    state = skip_newlines(state)

    state =
      case current_token(state) do
        {:indent, _, _} -> advance(state)
        _ -> state
      end

    {attrs, weeks, state} = parse_phase_body(state, %{}, [])

    phase = %AST.Phase{
      name: name,
      type: phase_type,
      duration: duration,
      goals: attrs[:goals],
      description: attrs[:description],
      weeks: weeks
    }

    {:ok, phase, state}
  end

  defp parse_phase_body(state, attrs, weeks) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "goals", _} ->
        state = advance(state)
        {:ok, goals, state} = parse_enum_list(state)
        parse_phase_body(state, Map.put(attrs, :goals, goals), weeks)

      {:keyword, "description", _} ->
        state = advance(state)
        {:ok, desc, state} = expect_string(state)
        parse_phase_body(state, Map.put(attrs, :description, desc), weeks)

      {:keyword, "WEEK", _} ->
        {:ok, week, state} = parse_week(state)
        parse_phase_body(state, attrs, [week | weeks])

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, Enum.reverse(weeks), state}

      {:eof, _, _} ->
        {attrs, Enum.reverse(weeks), state}

      # Hand control back to the outer `parse_phases` when the next sibling
      # PHASE begins; otherwise we'd greedily consume it here.
      {:keyword, "PHASE", _} ->
        {attrs, Enum.reverse(weeks), state}

      # Stray token between WEEK blocks within a phase — skip and keep
      # scanning so one bad exercise line doesn't cost us the rest of the
      # phase's weeks.
      _ ->
        parse_phase_body(advance(state), attrs, weeks)
    end
  end

  defp parse_week(state) do
    state = advance(state)
    {:ok, number, state} = expect_number(state)

    # Optional deload flag (schema v1.5.0+): WEEK 4 deload "Name":
    {is_deload, state} =
      case current_token(state) do
        {:keyword, "deload", _} -> {true, advance(state)}
        _ -> {nil, state}
      end

    name =
      case current_token(state) do
        {:string, n, _} ->
          state = advance(state)
          {n, state}

        _ ->
          {nil, state}
      end

    {name_val, state} = name
    state = expect_colon(state)
    state = skip_newlines(state)

    # Track whether we entered an indented body. Used to distinguish
    # legitimate empty weeks (placeholder week with no indented content,
    # e.g. periodisation scaffold) from the silent-drop case where the
    # body contains non-DAY content like inline `Monday: ...` summaries.
    {entered_indent?, state} =
      case current_token(state) do
        {:indent, _, _} -> {true, advance(state)}
        _ -> {false, state}
      end

    week_number = trunc(number)
    week_for_error = if entered_indent?, do: week_number, else: nil
    {:ok, days, state} = parse_days(state, [], week_for_error)

    week = %AST.Week{
      number: week_number,
      name: name_val,
      is_deload: is_deload,
      days: days
    }

    {:ok, week, state}
  end

  defp parse_days(state, days, week_for_error) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "DAY", _} ->
        {:ok, day, state} = parse_day(state)
        parse_days(state, [day | days], week_for_error)

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(days), state}

      {:eof, _, _} ->
        {:ok, Enum.reverse(days), state}

      # Hand control back to the caller when the next sibling at the outer
      # grammar level appears — don't consume WEEK or PHASE headers.
      {:keyword, outer, _} when outer in ["WEEK", "PHASE"] ->
        {:ok, Enum.reverse(days), state}

      # Silent-drop guard (parity with wpl-ai 1.11.0). When parse_week
      # entered an indented body but the content here isn't a DAY block,
      # emit a precise parse error with a repair_hint so agentic loops
      # can regenerate this specific week. Only fires once per week (when
      # we have zero DAYs accumulated AND week_for_error is set).
      {_tok_type, tok_value, location} when days == [] and not is_nil(week_for_error) ->
        got_token = "#{tok_value}"
        error = ParseError.week_has_no_valid_days(week_for_error, got_token, location)
        state = %{state | errors: [error | state.errors]}
        # Recover: skip tokens until we hit dedent / eof / peer-keyword
        # so subsequent weeks parse cleanly. Pass nil for week_for_error
        # so we don't double-emit on recovery.
        {:ok, Enum.reverse(days), recover_to_peer(state)}

      _ ->
        parse_days(advance(state), days, week_for_error)
    end
  end

  defp recover_to_peer(state) do
    case current_token(state) do
      {:dedent, _, _} -> advance(state)
      {:eof, _, _} -> state
      {:keyword, outer, _} when outer in ["WEEK", "PHASE"] -> state
      _ -> recover_to_peer(advance(state))
    end
  end

  defp parse_day(state) do
    state = advance(state)

    # Day name (Monday, Tuesday, etc. or number)
    {:ok, day_name, state} = parse_day_name(state)

    # Day type
    {:ok, day_type, state} = expect_bare_word(state)

    day_type_atom =
      case day_type do
        "training" -> :training
        "rest" -> :rest
        "active_recovery" -> :active_recovery
        "assessment" -> :assessment
        _ -> :training
      end

    # Duration
    {:ok, duration, state} = parse_duration_inline(state)

    # Optional label
    label =
      case current_token(state) do
        {:string, lbl, _} ->
          state = advance(state)
          {lbl, state}

        _ ->
          {nil, state}
      end

    {label_val, state} = label
    state = expect_colon(state)
    state = skip_newlines(state)

    state =
      case current_token(state) do
        {:indent, _, _} -> advance(state)
        _ -> state
      end

    {attrs, blocks, state} = parse_day_body(state, %{}, [])

    day = %AST.Day{
      day_name: day_name,
      day_type: day_type_atom,
      duration: duration,
      label: label_val,
      schedule: attrs[:schedule],
      blocks: blocks,
      notes: attrs[:notes]
    }

    {:ok, day, state}
  end

  defp parse_day_name(state) do
    case current_token(state) do
      {:keyword, name, _}
      when name in [
             "Monday",
             "Tuesday",
             "Wednesday",
             "Thursday",
             "Friday",
             "Saturday",
             "Sunday"
           ] ->
        {:ok, name, advance(state)}

      {:number, num, _} ->
        {:ok, trunc(num), advance(state)}

      {:bare_word, name, _} ->
        {:ok, name, advance(state)}

      _ ->
        {:ok, "Monday", state}
    end
  end

  defp parse_day_body(state, attrs, blocks) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "schedule", _} ->
        state = advance(state)
        {:ok, pref, state} = expect_bare_word(state)
        {:ok, flex, state} = expect_bare_word(state)

        schedule = {
          parse_schedule_pref(pref),
          parse_schedule_flex(flex)
        }

        parse_day_body(state, Map.put(attrs, :schedule, schedule), blocks)

      {:keyword, "notes", _} ->
        state = advance(state)
        {:ok, notes, state} = expect_string(state)
        parse_day_body(state, Map.put(attrs, :notes, notes), blocks)

      {:keyword, block_type, _}
      when block_type in [
             "warmup",
             "main",
             "cooldown",
             "nutrition",
             "meditation",
             "education",
             "assessment"
           ] ->
        {:ok, block, state} = parse_block(state)
        parse_day_body(state, attrs, [block | blocks])

      # `meals:` — the phase_nutrition subagent emits one meals block per day
      # containing multiple `MEAL <CATEGORY>: <name>` entries with macro
      # lines. Compile it into a single nutrition block whose activities are
      # one `%AST.Nutrition{}` per MEAL (category, name, macros, calories).
      {:bare_word, "meals", _} ->
        {:ok, block, state} = parse_meals_block(state)
        parse_day_body(state, attrs, [block | blocks])

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, Enum.reverse(blocks), state}

      # Tolerant fallback. Two shapes we see in the wild:
      #   (a) unknown sub-block like `meals:` before we had native support —
      #       skip header + indented body;
      #   (b) stray trailing tokens leaking from exercise lines (e.g.
      #       `bird_dog 3x10 each side rpe 7` dumps `each`, `side`, then
      #       `rpe 7` after parse_block_body finishes). Those stray tokens
      #       (bare_words, keywords, even numbers) would otherwise cascade
      #       up through parse_days / parse_week / parse_phase_body and drop
      #       every subsequent DAY and WEEK. Consume one token and keep
      #       looking; eof/dedent/outer-structural-keywords halt the loop.
      #
      # CRITICAL: must NOT consume `DAY` / `WEEK` / `PHASE` keywords — those
      # belong to the outer parser (parse_days / parse_phase_body /
      # parse_phases). Eating `DAY Tuesday` here would swallow the next day
      # and every keyword token that followed, collapsing a multi-day week
      # into one day.
      {:keyword, outer, _} when outer in ["DAY", "WEEK", "PHASE"] ->
        {attrs, Enum.reverse(blocks), state}

      {tag, _, _} when tag in [:bare_word, :keyword] ->
        state =
          if looks_like_sub_block_header?(state) do
            skip_sub_block_header_and_body(state)
          else
            advance(state)
          end

        parse_day_body(state, attrs, blocks)

      {:number, _, _} ->
        parse_day_body(advance(state), attrs, blocks)

      {:eof, _, _} ->
        {attrs, Enum.reverse(blocks), state}

      _ ->
        {attrs, Enum.reverse(blocks), state}
    end
  end

  # `meals:` block — multiple MEAL entries, each with macros. Emits one
  # %AST.Block{type: :nutrition} containing %AST.Nutrition{} activities so
  # the compiler can reuse its existing nutrition-activity path.
  defp parse_meals_block(state) do
    state = advance(state)
    state = expect_colon(state)
    state = skip_newlines(state)

    state =
      case current_token(state) do
        {:indent, _, _} -> advance(state)
        _ -> state
      end

    {activities, state} = parse_meal_entries(state, [])

    block = %AST.Block{
      type: :nutrition,
      structure: nil,
      rounds: nil,
      rest_between_rounds: nil,
      activities: activities
    }

    {:ok, block, state}
  end

  defp parse_meal_entries(state, acc) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "MEAL", _} ->
        {:ok, meal, state} = parse_meal_entry(state)
        parse_meal_entries(state, [meal | acc])

      {:dedent, _, _} ->
        {Enum.reverse(acc), advance(state)}

      _ ->
        {Enum.reverse(acc), state}
    end
  end

  # `MEAL BREAKFAST: smoothie_bowl` followed by indented macro lines.
  defp parse_meal_entry(state) do
    state = advance(state)
    {:ok, category, state} = expect_bare_word(state)
    state = expect_colon(state)
    {:ok, name, state} = expect_bare_word(state)
    state = skip_newlines(state)

    state =
      case current_token(state) do
        {:indent, _, _} -> advance(state)
        _ -> state
      end

    {attrs, state} = parse_meal_body(state, %{})

    nutrition = %AST.Nutrition{
      category: normalize_meal_category(category),
      name: name,
      macros: attrs[:macros],
      calories: attrs[:calories]
    }

    {:ok, nutrition, state}
  end

  # Macro lines inside a MEAL: `PROTEIN 20g`, `CARBS 45g`, `FAT 10g`,
  # `CALORIES 400kcal`. Lexer tokenises each number as :number and the unit
  # suffix as :bare_word (both for single-char `g` and multi-char `kcal`),
  # so consuming one optional bare_word after the number is enough.
  defp parse_meal_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {tag, name, _} when tag in [:keyword, :bare_word] and name in ["PROTEIN", "CARBS", "FAT"] ->
        state = advance(state)
        {:ok, grams, state} = expect_number(state)
        state = skip_optional_bare_word(state)
        macros = Map.get(attrs, :macros) || %AST.Macros{}
        key = meal_macro_key(name)
        macros = Map.put(macros, key, {grams, grams, "g"})
        parse_meal_body(state, Map.put(attrs, :macros, macros))

      {tag, "CALORIES", _} when tag in [:keyword, :bare_word] ->
        state = advance(state)
        {:ok, kcal, state} = expect_number(state)
        state = skip_optional_bare_word(state)
        parse_meal_body(state, Map.put(attrs, :calories, {kcal, kcal, "kcal"}))

      {:dedent, _, _} ->
        {attrs, advance(state)}

      _ ->
        {attrs, state}
    end
  end

  defp skip_optional_bare_word(state) do
    case current_token(state) do
      {:bare_word, _, _} -> advance(state)
      _ -> state
    end
  end

  defp meal_macro_key("PROTEIN"), do: :protein
  defp meal_macro_key("CARBS"), do: :carbs
  defp meal_macro_key("FAT"), do: :fat

  defp normalize_meal_category(c) when is_binary(c), do: String.downcase(c)
  defp normalize_meal_category(c), do: c

  defp looks_like_sub_block_header?(state) do
    # Look ahead: header is `<bare_word|keyword> :`
    case current_token(state) do
      {tag, _, _} when tag in [:bare_word, :keyword] ->
        case current_token(advance(state)) do
          {:colon, _, _} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp skip_sub_block_header_and_body(state) do
    # Consume the header keyword/bare_word and the following colon.
    state = advance(state)
    state = advance(state)
    state = skip_newlines(state)

    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        skip_until_matching_dedent(state, 1)

      _ ->
        state
    end
  end

  defp parse_schedule_pref(value) do
    case value do
      "morning" -> :morning
      "afternoon" -> :afternoon
      "evening" -> :evening
      "any" -> :any
      _ -> :any
    end
  end

  defp parse_schedule_flex(value) do
    case value do
      "strict" -> :strict
      "flexible" -> :flexible
      _ -> :flexible
    end
  end

  # =============================================================================
  # Blocks and Activities
  # =============================================================================

  defp parse_block(state) do
    {:ok, block_type, state} = expect_bare_word(state)

    block_type_atom =
      case block_type do
        "warmup" -> :warmup
        "main" -> :main
        "cooldown" -> :cooldown
        "nutrition" -> :nutrition
        "meditation" -> :meditation
        "education" -> :education
        "assessment" -> :assessment
        _ -> :main
      end

    # Optional structure
    structure =
      case current_token(state) do
        {:keyword, struct, _}
        when struct in [
               "circuit",
               "straight_sets",
               "superset",
               "emom",
               "amrap",
               "tabata"
             ] ->
          state = advance(state)
          {String.to_atom(struct), state}

        {:bare_word, struct, _}
        when struct in [
               "circuit",
               "straight_sets",
               "superset",
               "emom",
               "amrap",
               "tabata"
             ] ->
          state = advance(state)
          {String.to_atom(struct), state}

        _ ->
          {nil, state}
      end

    {structure_val, state} = structure
    state = expect_colon(state)
    state = skip_newlines(state)

    state =
      case current_token(state) do
        {:indent, _, _} -> advance(state)
        _ -> state
      end

    {attrs, activities, state} = parse_block_body(state, %{}, [], block_type_atom)

    block = %AST.Block{
      type: block_type_atom,
      structure: structure_val,
      rounds: attrs[:rounds],
      rest_between_rounds: attrs[:rest_between_rounds],
      activities: activities
    }

    {:ok, block, state}
  end

  defp parse_block_body(state, attrs, activities, block_type) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "rounds", _} ->
        state = advance(state)
        {:ok, rounds, state} = expect_number(state)
        parse_block_body(state, Map.put(attrs, :rounds, trunc(rounds)), activities, block_type)

      {:keyword, "rest_between_rounds", _} ->
        state = advance(state)
        {:ok, duration, state} = parse_duration(state)

        parse_block_body(
          state,
          Map.put(attrs, :rest_between_rounds, duration),
          activities,
          block_type
        )

      {:keyword, "cardio", _} ->
        {:ok, activity, state} = parse_cardio_activity(state)
        parse_block_body(state, attrs, [activity | activities], block_type)

      {:keyword, "nutrition", _} ->
        {:ok, activity, state} = parse_nutrition_activity(state)
        parse_block_body(state, attrs, [activity | activities], block_type)

      {:keyword, "meditation", _} ->
        {:ok, activity, state} = parse_meditation_activity(state)
        parse_block_body(state, attrs, [activity | activities], block_type)

      {:keyword, "recovery", _} ->
        {:ok, activity, state} = parse_recovery_activity(state)
        parse_block_body(state, attrs, [activity | activities], block_type)

      {:keyword, "habit", _} ->
        {:ok, activity, state} = parse_habit_activity(state)
        parse_block_body(state, attrs, [activity | activities], block_type)

      {:keyword, "subplan", _} ->
        {:ok, activity, state} = parse_sub_plan_activity(state)
        parse_block_body(state, attrs, [activity | activities], block_type)

      {:bare_word, _, _} ->
        # In cooldown blocks, bare words are typically recovery exercises.
        # Bug 7 fix: detect `<bare_word> <number> <time_unit> EOL` in cooldown
        # context and route to an inline CardioActivity instead of a RecoveryExercise.
        {:ok, activity, state} =
          if block_type == :cooldown and cooldown_cardio_pattern?(state) do
            parse_cooldown_inline_cardio(state)
          else
            if block_type == :cooldown do
              parse_recovery_exercise(state)
            else
              parse_exercise_or_simple_activity(state)
            end
          end

        parse_block_body(state, attrs, [activity | activities], block_type)

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, Enum.reverse(activities), state}

      {:eof, _, _} ->
        {attrs, Enum.reverse(activities), state}

      # Hand control back to the outer parser when a sibling block header
      # (warmup / main / cooldown / meals / ...) or an outer grammar token
      # (DAY / WEEK / PHASE) appears. These are caught by parse_day_body, not
      # here.
      {:keyword, outer, _}
      when outer in [
             "DAY",
             "WEEK",
             "PHASE",
             "warmup",
             "main",
             "cooldown",
             "nutrition",
             "meditation",
             "education",
             "assessment"
           ] ->
        {attrs, Enum.reverse(activities), state}

      # Keywords that are valid exercise names (e.g. muscle/movement-pattern
      # vocabulary terms like `squat`, `lunge`, `chest` that the lexer now
      # classifies as keywords). Attempt to parse them as exercises.
      {:keyword, word, _}
      when word not in [
             "DAY",
             "WEEK",
             "PHASE",
             "warmup",
             "main",
             "cooldown",
             "nutrition",
             "meditation",
             "education",
             "assessment",
             "cardio",
             "habit",
             "recovery",
             "subplan",
             "rounds",
             "rest_between_rounds",
             "PHASES",
             "GOALS",
             "REQUIRES",
             "PERSONALIZATION",
             "PROGRESS",
             "NOTIFICATIONS",
             "RENDERING",
             "HABITS",
             "ATHLETE_THRESHOLDS"
           ] ->
        {:ok, activity, state} =
          if block_type == :cooldown do
            parse_recovery_exercise(state)
          else
            parse_exercise_or_simple_activity(state)
          end

        parse_block_body(state, attrs, [activity | activities], block_type)

      # Stray tokens leaking from a malformed exercise line (e.g.
      # `bird_dog 3x10 each side rpe 7` leaves `rpe 7` after exercise
      # parsing gives up). Previously we returned here, but then the
      # caller saw the dedent before we'd finished the block — it thought
      # the block ended early and the cooldown/next-block got absorbed by
      # parse_days as stray tokens. Consume and keep scanning so the real
      # dedent closes the block cleanly.
      _ ->
        parse_block_body(advance(state), attrs, activities, block_type)
    end
  end

  # Cardio modalities commonly appear as the "exercise ref" in sets×reps
  # prescriptions emitted by LLMs ("running 1x60 rpe 5 rest 90 seconds").
  # Accept them silently — the WPL JSON schema permits exercise_ref as a
  # free string, and the semantic validator can flag unsupported usage.
  @cardio_modality_set ~w(running walking cycling rowing elliptical swimming
    jump_rope hiking)

  # Two-tier exercise-ref resolution (commit 2137782).
  #
  # Tier 1 — high-confidence (Jaro-Winkler >= 0.85): auto-correct typos.
  #   `pushup` → `push_up`, `bnech_press` → `bench_press`.
  # Tier 2 — no high-confidence match: accept ref as-is. The WPL JSON
  #   schema permits exercise_ref as a free string; the semantic validator
  #   can emit a warning later if needed.
  #
  # Returns the (possibly substituted) exercise ref string.
  defp resolve_exercise_ref(name) do
    if name in @cardio_modality_set do
      name
    else
      case ExerciseMatcher.validate(name) do
        :ok ->
          name

        {:unknown, _suggestions} ->
          case ExerciseMatcher.best_match(name) do
            {:ok, best} -> best
            :no_match -> name
          end
      end
    end
  end

  defp parse_exercise_or_simple_activity(state) do
    {:ok, name, state} = expect_bare_word(state)

    # Check if this looks like an exercise (has sets x reps pattern)
    case current_token(state) do
      {:number, sets, _} ->
        state = advance(state)

        case current_token(state) do
          {:keyword, "x", _} ->
            # This is sets x reps
            state = advance(state)
            {:ok, reps, state} = parse_reps_spec(state)
            {modifiers, state} = parse_exercise_modifiers(state, %{})
            resolved_name = resolve_exercise_ref(name)

            exercise = %AST.Exercise{
              exercise_ref: resolved_name,
              name: modifiers[:name],
              sets: trunc(sets),
              reps: reps,
              rpe: modifiers[:rpe],
              rpe_min: modifiers[:rpe_min],
              rpe_max: modifiers[:rpe_max],
              rir: modifiers[:rir],
              rir_min: modifiers[:rir_min],
              rir_max: modifiers[:rir_max],
              tempo: modifiers[:tempo],
              rest: modifiers[:rest],
              weight: modifiers[:weight],
              to_failure: modifiers[:to_failure],
              primary_muscles: modifiers[:primary_muscles],
              secondary_muscles: modifiers[:secondary_muscles],
              movement_pattern: modifiers[:movement_pattern]
            }

            {:ok, exercise, state}

          {:bare_word, "x", _} ->
            # This is sets x reps (x as bare_word)
            state = advance(state)
            {:ok, reps, state} = parse_reps_spec(state)
            {modifiers, state} = parse_exercise_modifiers(state, %{})
            resolved_name = resolve_exercise_ref(name)

            exercise = %AST.Exercise{
              exercise_ref: resolved_name,
              name: modifiers[:name],
              sets: trunc(sets),
              reps: reps,
              rpe: modifiers[:rpe],
              rpe_min: modifiers[:rpe_min],
              rpe_max: modifiers[:rpe_max],
              rir: modifiers[:rir],
              rir_min: modifiers[:rir_min],
              rir_max: modifiers[:rir_max],
              tempo: modifiers[:tempo],
              rest: modifiers[:rest],
              weight: modifiers[:weight],
              to_failure: modifiers[:to_failure],
              primary_muscles: modifiers[:primary_muscles],
              secondary_muscles: modifiers[:secondary_muscles],
              movement_pattern: modifiers[:movement_pattern]
            }

            {:ok, exercise, state}

          {:bare_word, xamrap, _}
          when xamrap in ["xAMRAP", "xamrap", "xAmrap"] ->
            # Compact form: NxAMRAP — the lexer fuses "x" and "AMRAP" into one token
            # because "x" is not stopped before uppercase letters.
            state = advance(state)
            {modifiers, state} = parse_exercise_modifiers(state, %{})
            resolved_name = resolve_exercise_ref(name)

            exercise = %AST.Exercise{
              exercise_ref: resolved_name,
              name: modifiers[:name],
              sets: trunc(sets),
              reps: :amrap,
              rpe: modifiers[:rpe],
              rpe_min: modifiers[:rpe_min],
              rpe_max: modifiers[:rpe_max],
              rir: modifiers[:rir],
              rir_min: modifiers[:rir_min],
              rir_max: modifiers[:rir_max],
              tempo: modifiers[:tempo],
              rest: modifiers[:rest],
              weight: modifiers[:weight],
              to_failure: modifiers[:to_failure],
              primary_muscles: modifiers[:primary_muscles],
              secondary_muscles: modifiers[:secondary_muscles],
              movement_pattern: modifiers[:movement_pattern]
            }

            {:ok, exercise, state}

          # Accept both short bare_word units ("m", "s", "h") and long
          # keyword units ("minutes", "seconds", "hours", "days") so the
          # unit token is always consumed. Without long-form support the
          # keyword `minutes` would leak into block-body parsing and
          # silently truncate subsequent WEEK blocks.
          {unit_tag, unit, _}
          when (unit_tag == :bare_word and unit in ["s", "m", "h"]) or
                 (unit_tag == :keyword and unit in ["seconds", "minutes", "hours", "days"]) ->
            # Simple activity with duration (e.g., "jumping_jacks 2m" or "cycling 10 minutes")
            state = advance(state)
            # Consume trailing intensity modifiers (rpe, rir, rest, etc.) — the
            # SimpleActivity schema has no fields for them, but failing to consume
            # lets the keywords leak into block-body parsing and silently truncate
            # subsequent WEEK blocks.
            state = consume_simple_activity_modifiers(state)

            simple = %AST.SimpleActivity{
              name: name,
              duration: %AST.Duration{value: sets, unit: parse_time_unit(unit)},
              params: nil
            }

            {:ok, simple, state}

          _ ->
            # Simple activity with number only (assume minutes)
            state = consume_simple_activity_modifiers(state)

            simple = %AST.SimpleActivity{
              name: name,
              duration: %AST.Duration{value: sets, unit: :minutes},
              params: nil
            }

            {:ok, simple, state}
        end

      _ ->
        # Simple activity without parameters
        # Check for inline duration like "2m"
        {duration, state} = parse_optional_inline_duration(state)

        simple = %AST.SimpleActivity{
          name: name,
          duration: duration,
          params: nil
        }

        {:ok, simple, state}
    end
  end

  defp parse_reps_spec(state) do
    # Check for AMRAP-only form: "x amrap" (no leading number)
    case current_token(state) do
      {tag, amrap, _} when tag in [:keyword, :bare_word] and amrap in ["AMRAP", "amrap"] ->
        state = advance(state)
        {:ok, :amrap, state}

      _ ->
        {:ok, first, state} = expect_number(state)

        case current_token(state) do
          {:range, _, _} ->
            state = advance(state)
            {:ok, second, state} = expect_number(state)

            # Check for target
            case current_token(state) do
              {:keyword, "target", _} ->
                state = advance(state)
                {:ok, target, state} = expect_number(state)
                state = skip_optional_target_unit(state)
                {:ok, {trunc(first), trunc(second), trunc(target)}, state}

              _ ->
                # Same time-unit-suffix handling as the single-number branch.
                # Range forms like `plank 3x20..30s rpe 6` need the trailing `s` /
                # `seconds` consumed when a modifier keyword follows, otherwise the
                # unit token leaks and truncates downstream WEEK blocks.
                state = maybe_consume_reps_unit_suffix(state)
                {:ok, {trunc(first), trunc(second)}, state}
            end

          # Plain count followed by `target N` — e.g. `squat 3x10 target 10 rpe 6`.
          # Subagents emit this shape (mirror of the range form); without this
          # branch the `target` keyword leaks past parse_reps_spec and cascades
          # up to block/day/week parsers, silently dropping everything after.
          {:keyword, "target", _} ->
            state = advance(state)
            {:ok, target, state} = expect_number(state)
            state = skip_optional_target_unit(state)
            {:ok, {trunc(first), trunc(first), trunc(target)}, state}

          # AMRAP after a number: "NxAMRAP" where the number is sets (parsed by the
          # outer exercise parser) and amrap is the reps spec. The "Nx" consumed sets
          # already, so at this point `first` is actually reps — but when form is
          # "1xAMRAP" sets=1, reps=AMRAP. The AMRAP token is matched here.
          {tag, amrap, _} when tag in [:keyword, :bare_word] and amrap in ["AMRAP", "amrap"] ->
            state = advance(state)
            {:ok, :amrap, state}

          _ ->
            # Tolerate trailing time-unit suffix on the reps number ("20s", "2m") —
            # BUT only when followed by an exercise modifier keyword. Models often
            # write `plank 3x30s rpe 6 rest 60 seconds` meaning "3 sets × 30 sec at
            # RPE 6." Without consuming the `s`, the modifier keywords leak into
            # parent parsing and silently truncate subsequent WEEK blocks.
            state = maybe_consume_reps_unit_suffix(state)
            {:ok, trunc(first), state}
        end
    end
  end

  # Modifier keywords that can legitimately follow a reps spec on the same line.
  # When a unit suffix sits between reps and one of these keywords (e.g. `3x30s rpe 6`),
  # we consume the suffix; otherwise we leave it in the stream so existing conformance
  # behaviour around terminal `s` (parsed as a separate simple activity) is preserved.
  @reps_modifier_follow ~w(rpe rir rest tempo weight name to_failure bodyweight)

  # Consume a trailing `s`/`m` or long-form `seconds`/`minutes`/`hours` after a
  # reps number, but only when the next token after the unit is a known modifier
  # keyword. This prevents the unit from leaking into block-body parsing.
  defp maybe_consume_reps_unit_suffix(state) do
    case current_token(state) do
      {:bare_word, unit, _} when unit in ["s", "m"] ->
        check_reps_unit_follow(state)

      {:keyword, unit, _} when unit in ["seconds", "minutes", "hours"] ->
        check_reps_unit_follow(state)

      _ ->
        state
    end
  end

  defp check_reps_unit_follow(state) do
    # peek one token ahead — tokens are 0-indexed from state.pos
    next_pos = state.pos + 1

    if next_pos < length(state.tokens) do
      case Enum.at(state.tokens, next_pos) do
        {:keyword, kw, _} when kw in @reps_modifier_follow ->
          advance(state)

        _ ->
          state
      end
    else
      state
    end
  end

  # Consume trailing exercise-modifier keywords on a simple activity and discard
  # them. SimpleActivity has no fields for rpe/rir/rest/etc, so the values are
  # dropped — but consuming the tokens prevents them from leaking into block-body
  # parsing where they would silently truncate downstream WEEK blocks. Tolerant;
  # bails on the first token that is not a known modifier keyword.
  @simple_activity_modifier_keywords ~w(rpe rir rest tempo weight name to_failure
    bodyweight heart_rate_zone bpm pace)

  defp consume_simple_activity_modifiers(state) do
    case current_token(state) do
      {:keyword, kw, _} when kw in @simple_activity_modifier_keywords ->
        # Consume the modifier keyword then eat its arguments until we reach a
        # structural boundary or another modifier keyword.
        state = advance(state)
        state = consume_until_modifier_or_boundary(state)
        consume_simple_activity_modifiers(state)

      _ ->
        state
    end
  end

  defp consume_until_modifier_or_boundary(state) do
    case current_token(state) do
      {:newline, _, _} -> state
      {:dedent, _, _} -> state
      {:indent, _, _} -> state
      {:eof, _, _} -> state
      {:keyword, kw, _} when kw in @simple_activity_modifier_keywords -> state
      _ -> consume_until_modifier_or_boundary(advance(state))
    end
  end

  # Workout subagents emit `target N kg` when the target is a weight rather
  # than a rep count (e.g. `bench_press 3x8..10 target 40 kg rpe 7 rest 60
  # seconds`). The parser treated `target` as a reps count only, so the unit
  # token leaked past parse_reps_spec and — since parse_exercise_modifiers
  # doesn't handle it — cascaded up and dropped everything after the first
  # exercise.
  #
  # Both :bare_word ("reps") and :keyword ("kg", "lbs" — lexed as keywords
  # because they're in the grammar's unit list) are accepted. We currently
  # don't carry the unit in the rep target tuple; the intent captured by
  # the judge and UI is the number.
  @target_units ~w(kg lbs reps sec seconds m min percentage_1rm)
  defp skip_optional_target_unit(state) do
    case current_token(state) do
      {tag, unit, _} when tag in [:bare_word, :keyword] and unit in @target_units ->
        advance(state)

      _ ->
        state
    end
  end

  # Workout subagents emit `bird_dog 3x10 each side rpe 7` or
  # `step_up 3x10 each leg rpe 7` — "each side" / "per leg" are contextual
  # qualifiers attached to the rep count, not the start of a new exercise.
  # Without this, the trailing bare_words leaked out of parse_reps_spec,
  # parse_block_body saw them as new exercises, and the UI showed phantom
  # "each", "side", "per", "leg" items beside real exercises.
  @exercise_qualifiers ~w(each per side sides leg legs arm arms both left right)

  @muscle_groups ~w(chest upper_back lats traps front_delts side_delts rear_delts
    biceps triceps forearms abs obliques lower_back spinal_erectors
    glutes quadriceps hamstrings calves hip_adductors hip_abductors hip_flexors neck)

  @movement_patterns ~w(squat hinge lunge push_horizontal push_vertical
    pull_horizontal pull_vertical carry rotate anti_rotate gait jump isolation)

  defp parse_exercise_modifiers(state, modifiers) do
    state = skip_exercise_qualifiers(state)

    case current_token(state) do
      {:keyword, "rpe", _} ->
        state = advance(state)
        {:ok, first, state} = expect_number(state)

        # Support `rpe 7..8` range syntax — models frequently emit ranges
        # to express target zones; the range token previously leaked into
        # downstream parsing and silently truncated entire WEEK blocks.
        case current_token(state) do
          {:range, _, _} ->
            state = advance(state)
            {:ok, second, state} = expect_number(state)

            modifiers =
              modifiers
              |> Map.put(:rpe_min, trunc(first))
              |> Map.put(:rpe_max, trunc(second))

            parse_exercise_modifiers(state, modifiers)

          _ ->
            parse_exercise_modifiers(state, Map.put(modifiers, :rpe, trunc(first)))
        end

      {:keyword, "rir", _} ->
        state = advance(state)
        {:ok, first, state} = expect_number(state)

        # Support `rir 1..2` range syntax — same reasoning as rpe ranges above.
        case current_token(state) do
          {:range, _, _} ->
            state = advance(state)
            {:ok, second, state} = expect_number(state)

            modifiers =
              modifiers
              |> Map.put(:rir_min, trunc(first))
              |> Map.put(:rir_max, trunc(second))

            parse_exercise_modifiers(state, modifiers)

          _ ->
            parse_exercise_modifiers(state, Map.put(modifiers, :rir, trunc(first)))
        end

      {:keyword, "tempo", _} ->
        state = advance(state)
        {:ok, tempo, state} = parse_tempo(state)
        parse_exercise_modifiers(state, Map.put(modifiers, :tempo, tempo))

      {:keyword, "rest", _} ->
        state = advance(state)
        {:ok, duration, state} = parse_duration(state)
        parse_exercise_modifiers(state, Map.put(modifiers, :rest, duration))

      {:keyword, "weight", _} ->
        state = advance(state)
        {:ok, weight, state} = parse_weight_spec(state)
        parse_exercise_modifiers(state, Map.put(modifiers, :weight, weight))

      {:keyword, "name", _} ->
        state = advance(state)
        {:ok, name, state} = expect_string(state)
        parse_exercise_modifiers(state, Map.put(modifiers, :name, name))

      {:keyword, "muscles", _} ->
        state = advance(state)
        {primary, secondary, state} = parse_muscle_spec(state)

        modifiers =
          modifiers
          |> Map.put(:primary_muscles, primary)
          |> Map.put(:secondary_muscles, secondary)

        parse_exercise_modifiers(state, modifiers)

      {:keyword, "pattern", _} ->
        state = advance(state)
        {pattern, state} = parse_movement_pattern(state)
        parse_exercise_modifiers(state, Map.put(modifiers, :movement_pattern, pattern))

      {:keyword, "to_failure", _} ->
        state = advance(state)
        parse_exercise_modifiers(state, Map.put(modifiers, :to_failure, true))

      {:bare_word, "to_failure", _} ->
        state = advance(state)
        parse_exercise_modifiers(state, Map.put(modifiers, :to_failure, true))

      # Bug 7 fix: bare `bodyweight` keyword after reps/sets is a shorthand
      # for `weight bodyweight` — attach it as weight: {type: bodyweight} on
      # the exercise rather than emitting a phantom simple activity.
      {:keyword, "bodyweight", _} ->
        weight = %AST.Weight{type: :bodyweight, value: nil, unit: nil}
        state = advance(state)
        parse_exercise_modifiers(state, Map.put(modifiers, :weight, weight))

      _ ->
        {modifiers, state}
    end
  end

  # Parses the muscle spec after the `muscles` keyword.
  # Two forms:
  #   muscles chest, triceps                            — all primary, no secondary
  #   muscles primary chest secondary triceps, front_delts
  defp parse_muscle_spec(state) do
    case current_token(state) do
      {:keyword, "primary", _} ->
        state = advance(state)
        {primary, state} = parse_muscle_list(state)

        {secondary, state} =
          case current_token(state) do
            {:keyword, "secondary", _} ->
              state = advance(state)
              parse_muscle_list(state)

            _ ->
              {[], state}
          end

        {primary, secondary, state}

      _ ->
        # Shorthand: all primary
        {primary, state} = parse_muscle_list(state)
        {primary, [], state}
    end
  end

  # Parses a comma-separated list of muscle group tokens.
  defp parse_muscle_list(state, acc \\ []) do
    case current_token(state) do
      {tag, value, _} when tag in [:keyword, :bare_word] and value in @muscle_groups ->
        state = advance(state)

        case current_token(state) do
          {:comma, _, _} ->
            parse_muscle_list(advance(state), [value | acc])

          _ ->
            {Enum.reverse([value | acc]), state}
        end

      _ ->
        {Enum.reverse(acc), state}
    end
  end

  # Parses a single movement pattern token.
  defp parse_movement_pattern(state) do
    case current_token(state) do
      {tag, value, _} when tag in [:keyword, :bare_word] and value in @movement_patterns ->
        {value, advance(state)}

      _ ->
        {nil, state}
    end
  end

  defp skip_exercise_qualifiers(state) do
    case current_token(state) do
      {tag, word, _} when tag in [:bare_word, :keyword] and word in @exercise_qualifiers ->
        skip_exercise_qualifiers(advance(state))

      _ ->
        state
    end
  end

  # Read a single tempo segment: either a number or the "X"/"x" keyword.
  # Returns `{segment_string, new_state}` where segment_string is e.g. "3" or "X".
  defp read_tempo_segment(state) do
    case current_token(state) do
      {:number, n, _} -> {"#{trunc(n)}", advance(state)}
      {:keyword, x, _} when x in ["X", "x"] -> {"X", advance(state)}
      {:bare_word, x, _} when x in ["X", "x"] -> {"X", advance(state)}
      _ -> {"0", state}
    end
  end

  defp parse_tempo(state) do
    # Tempo can be like "3-1-2-0", "3-0-X-1", or as separate tokens.
    # The lexer emits either :minus or :range tokens between numbers depending
    # on context — after the N-M range fix (commit 327e456), `3-1` between two
    # numbers produces [:number, :range, :number]. parse_tempo must accept both
    # :minus and :range as separators so tempo strings survive unchanged.
    case current_token(state) do
      {:number, first, _} ->
        state = advance(state)

        case current_token(state) do
          {sep, _, _} when sep in [:minus, :range] ->
            # Parse tempo pattern (supports X for explosive concentric).
            state = advance(state)
            {second, state} = read_tempo_segment(state)
            state = expect_minus_or_range(state)
            {third, state} = read_tempo_segment(state)
            state = expect_minus_or_range(state)
            {fourth, state} = read_tempo_segment(state)
            {:ok, "#{trunc(first)}-#{second}-#{third}-#{fourth}", state}

          _ ->
            {:ok, "#{trunc(first)}", state}
        end

      {:bare_word, tempo, _} when byte_size(tempo) == 7 ->
        # Already formatted like "3-1-2-0"
        {:ok, tempo, advance(state)}

      _ ->
        {:ok, "2-0-2-0", state}
    end
  end

  defp parse_weight_spec(state) do
    case current_token(state) do
      {:keyword, "bodyweight", _} ->
        weight = %AST.Weight{type: :bodyweight, value: nil, unit: nil}
        {:ok, weight, advance(state)}

      {:number, value, _} ->
        state = advance(state)

        # Check for `N% bw` / `N% bodyweight` / `N% rm` forms (percent sign
        # followed by a unit bareword).
        {percent_syntax, state} =
          case current_token(state) do
            {:percent, _, _} -> {true, advance(state)}
            _ -> {false, state}
          end

        {:ok, unit, state} = expect_bare_word(state)

        type =
          cond do
            unit in ["bw", "bodyweight", "percentage_bodyweight"] ->
              :percentage_bodyweight

            percent_syntax or unit in ["rm", "1rm", "percentage_1rm"] ->
              :percentage_1rm

            true ->
              :absolute
          end

        # Optional `metric <enum>` qualifier (schema v1.6.0+)
        # The metric token may start with a digit (e.g. "1rm", "e1rm") —
        # in that case the lexer splits "1rm" into :number 1 + :bare_word "rm".
        {metric, state} =
          case current_token(state) do
            {tag, "metric", _} when tag in [:keyword, :bare_word] ->
              state = advance(state)

              case current_token(state) do
                {tag2, m, _} when tag2 in [:keyword, :bare_word] ->
                  {canonicalize_weight_metric(m), advance(state)}

                # "1rm" → :number 1 followed by :bare_word "rm"
                {:number, n, _} ->
                  state = advance(state)

                  suffix =
                    case current_token(state) do
                      {tag3, s, _} when tag3 in [:keyword, :bare_word] ->
                        {s, advance(state)}

                      _ ->
                        {"", state}
                    end

                  {suffix_str, state} = suffix
                  raw = "#{trunc(n)}#{suffix_str}"
                  {canonicalize_weight_metric(raw), state}

                _ ->
                  {nil, state}
              end

            _ ->
              {nil, state}
          end

        weight = %AST.Weight{type: type, value: value, unit: unit, metric: metric}
        {:ok, weight, state}

      _ ->
        {:ok, %AST.Weight{type: :bodyweight}, state}
    end
  end

  defp parse_optional_inline_duration(state) do
    case current_token(state) do
      {:number, value, _} ->
        state = advance(state)

        case current_token(state) do
          {:bare_word, unit, _} when unit in ["s", "m", "h", "seconds", "minutes", "hours"] ->
            state = advance(state)
            duration = %AST.Duration{value: value, unit: parse_time_unit(unit)}
            {duration, state}

          _ ->
            {nil, state}
        end

      _ ->
        {nil, state}
    end
  end

  # Bug 7 helpers: detect and parse `<bare_word> <number> <time_unit> EOL` pattern
  # in cooldown blocks as an inline CardioActivity (continuous, with total_duration).
  @time_unit_tokens ~w(s m h sec min seconds minutes hours)

  defp cooldown_cardio_pattern?(state) do
    # pos 0: bare_word (modality)
    # pos 1: number
    # pos 2: bare_word matching a time unit
    # pos 3: newline/dedent/eof (nothing else on the line)
    case {peek_token(state, 1), peek_token(state, 2), peek_token(state, 3)} do
      {{:number, _, _}, {tag2, unit, _}, {sentinel, _, _}}
      when tag2 in [:bare_word, :keyword] and unit in @time_unit_tokens and
             sentinel in [:newline, :dedent, :eof] ->
        true

      _ ->
        false
    end
  end

  defp parse_cooldown_inline_cardio(state) do
    {:ok, modality, state} = expect_bare_word(state)
    {:ok, value, state} = expect_number(state)

    unit =
      case current_token(state) do
        {tag, u, _} when tag in [:bare_word, :keyword] and u in @time_unit_tokens ->
          state = advance(state)
          {parse_time_unit(u), state}

        _ ->
          {:minutes, state}
      end

    {unit_atom, state} = unit

    cardio = %AST.Cardio{
      modality: modality,
      cardio_type: :continuous,
      total_duration: %AST.Duration{value: value, unit: unit_atom},
      zone: nil,
      intensity: nil,
      intervals: nil
    }

    {:ok, cardio, state}
  end

  defp parse_cardio_activity(state) do
    state = advance(state)
    {:ok, modality, state} = expect_bare_word(state)
    {:ok, cardio_type, state} = expect_bare_word(state)
    state = expect_colon(state)
    state = skip_newlines(state)

    state =
      case current_token(state) do
        {:indent, _, _} -> advance(state)
        _ -> state
      end

    {attrs, state} = parse_cardio_body(state, %{})

    cardio_type_atom =
      case cardio_type do
        "continuous" -> :continuous
        "intervals" -> :intervals
        "fartlek" -> :fartlek
        _ -> :continuous
      end

    # Propagate zone_model (if present) into the intensity field (schema v1.3.0+).
    intensity =
      case {attrs[:intensity], attrs[:zone_model]} do
        {nil, zone_model} when zone_model != nil ->
          %AST.Intensity{
            type: :heart_rate_zone,
            value: attrs[:zone],
            range: nil,
            zone_model: zone_model
          }

        {intensity, zone_model} when intensity != nil and zone_model != nil ->
          %{intensity | zone_model: zone_model}

        {intensity, _} ->
          intensity
      end

    cardio = %AST.Cardio{
      modality: modality,
      cardio_type: cardio_type_atom,
      total_duration: attrs[:total_duration],
      zone: attrs[:zone],
      intensity: intensity,
      intervals: attrs[:intervals]
    }

    {:ok, cardio, state}
  end

  defp parse_cardio_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "total", _} ->
        state = advance(state)
        {:ok, duration, state} = parse_duration(state)
        parse_cardio_body(state, Map.put(attrs, :total_duration, duration))

      {:keyword, "zone", _} ->
        state = advance(state)
        {:ok, zone, state} = expect_number(state)
        attrs = Map.put(attrs, :zone, trunc(zone))

        # Optional `model <zone_model>` qualifier (schema v1.3.0+).
        {attrs, state} =
          case current_token(state) do
            {:keyword, "model", _} ->
              state = advance(state)

              case current_token(state) do
                {tag, value, _} when tag in [:keyword, :bare_word] ->
                  {Map.put(attrs, :zone_model, value), advance(state)}

                _ ->
                  {attrs, state}
              end

            _ ->
              {attrs, state}
          end

        parse_cardio_body(state, attrs)

      {:keyword, "intensity", _} ->
        state = advance(state)
        {:ok, intensity, state} = parse_intensity(state)
        parse_cardio_body(state, Map.put(attrs, :intensity, intensity))

      # The phase_workout prompt teaches `WORKs 30s / RESTs 30s x10` for
      # interval patterns, but the canonical grammar expected just the bare
      # `30s / 30s x10`. Without consuming these prefixes, they leaked into
      # parse_block_body and their following `30s` became a phantom simple
      # activity named "s". Skip the WORKs/RESTs label and fall through to
      # the number case that handles the actual interval numbers.
      {:keyword, label, _} when label in ["WORKs", "RESTs", "WORK", "REST"] ->
        parse_cardio_body(advance(state), attrs)

      {:number, _work, _} ->
        # Interval pattern: 30s work / 30s rest x10
        {:ok, intervals, state} = parse_interval_pattern(state)
        parse_cardio_body(state, Map.put(attrs, :intervals, intervals))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  defp parse_intensity(state) do
    case current_token(state) do
      {:keyword, "rpe", _} ->
        state = advance(state)
        {:ok, first, state} = expect_number(state)

        # Support `rpe 7..8` (range) in addition to `rpe 7` (single value).
        # Models commonly emit ranges to express target zones; treating them
        # as a syntax error silently truncated the rest of the document.
        case current_token(state) do
          {:range, _, _} ->
            state = advance(state)
            {:ok, second, state} = expect_number(state)
            intensity = %AST.Intensity{type: :rpe, value: nil, range: {first, second}}
            {:ok, intensity, state}

          _ ->
            intensity = %AST.Intensity{type: :rpe, value: first, range: nil}
            {:ok, intensity, state}
        end

      {:keyword, "heart_rate_zone", _} ->
        state = advance(state)
        {:ok, value, state} = expect_number(state)
        intensity = %AST.Intensity{type: :heart_rate_zone, value: trunc(value), range: nil}
        {:ok, intensity, state}

      {:keyword, "bpm", _} ->
        state = advance(state)
        {:ok, min, state} = expect_number(state)
        state = expect_range(state)
        {:ok, max, state} = expect_number(state)
        intensity = %AST.Intensity{type: :bpm, value: nil, range: {trunc(min), trunc(max)}}
        {:ok, intensity, state}

      {:keyword, "pace", _} ->
        state = advance(state)
        {:ok, pace, state} = expect_string(state)
        intensity = %AST.Intensity{type: :pace, value: pace, range: nil}
        {:ok, intensity, state}

      # intensity power N (schema v1.3.0+)
      {:keyword, "power", _} ->
        state = advance(state)
        {:ok, value, state} = expect_number(state)
        intensity = %AST.Intensity{type: :power, value: value, range: nil}
        {:ok, intensity, state}

      _ ->
        {:ok, nil, state}
    end
  end

  defp parse_interval_pattern(state) do
    {:ok, work, state} = expect_number(state)
    # Expect 's' for seconds
    state =
      case current_token(state) do
        {:bare_word, "s", _} -> advance(state)
        _ -> state
      end

    state = expect_keyword(state, "work")
    state = expect_slash(state)
    {:ok, rest_seconds, state} = expect_number(state)

    state =
      case current_token(state) do
        {:bare_word, "s", _} -> advance(state)
        _ -> state
      end

    state = expect_keyword(state, "rest")

    # Handle both "x" as keyword and bare_word
    state =
      case current_token(state) do
        {:keyword, "x", _} -> advance(state)
        {:bare_word, "x", _} -> advance(state)
        _ -> state
      end

    {:ok, repeats, state} = expect_number(state)

    intervals = %AST.IntervalPattern{
      work_seconds: trunc(work),
      rest_seconds: trunc(rest_seconds),
      repeats: trunc(repeats)
    }

    {:ok, intervals, state}
  end

  defp parse_nutrition_activity(state) do
    state = advance(state)
    {:ok, category, state} = expect_bare_word(state)
    state = expect_colon(state)
    state = skip_newlines(state)

    state =
      case current_token(state) do
        {:indent, _, _} -> advance(state)
        _ -> state
      end

    {attrs, state} = parse_nutrition_body(state, %{})

    nutrition = %AST.Nutrition{
      category: category,
      timing: attrs[:timing],
      macros: attrs[:macros],
      calories: attrs[:calories],
      suggestions: attrs[:suggestions]
    }

    {:ok, nutrition, state}
  end

  defp parse_nutrition_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "timing", _} ->
        state = advance(state)
        {:ok, timing, state} = parse_nutrition_timing(state)
        parse_nutrition_body(state, Map.put(attrs, :timing, timing))

      {:keyword, "protein", _} ->
        state = advance(state)
        {:ok, range, state} = parse_macro_range(state)
        macros = Map.get(attrs, :macros) || %AST.Macros{}
        parse_nutrition_body(state, Map.put(attrs, :macros, %{macros | protein: range}))

      {:keyword, "carbs", _} ->
        state = advance(state)
        {:ok, range, state} = parse_macro_range(state)
        macros = Map.get(attrs, :macros) || %AST.Macros{}
        parse_nutrition_body(state, Map.put(attrs, :macros, %{macros | carbs: range}))

      {:keyword, "fat", _} ->
        state = advance(state)
        {:ok, range, state} = parse_fat_range(state)
        macros = Map.get(attrs, :macros) || %AST.Macros{}
        parse_nutrition_body(state, Map.put(attrs, :macros, %{macros | fat: range}))

      {:keyword, "calories", _} ->
        state = advance(state)
        {:ok, min, state} = expect_number(state)
        state = expect_range(state)
        {:ok, max, state} = expect_number(state)

        {cal_unit, state} =
          case current_token(state) do
            {:bare_word, u, _} when u in ["kcal", "kcal_per_kg", "multiplier_of_tdee"] ->
              {u, advance(state)}

            {:keyword, u, _} when u in ["kcal", "kcal_per_kg", "multiplier_of_tdee"] ->
              {u, advance(state)}

            _ ->
              {"kcal", state}
          end

        calories =
          if cal_unit == "multiplier_of_tdee" or cal_unit == "kcal_per_kg" do
            {min, max, cal_unit}
          else
            {trunc(min), trunc(max), cal_unit}
          end

        parse_nutrition_body(state, Map.put(attrs, :calories, calories))

      {:keyword, "suggestions", _} ->
        state = advance(state)
        state = expect_colon(state)
        state = skip_newlines(state)
        state = expect_indent(state)
        {:ok, suggestions, state} = parse_suggestion_list(state, [])
        parse_nutrition_body(state, Map.put(attrs, :suggestions, suggestions))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  defp parse_nutrition_timing(state) do
    case current_token(state) do
      {:keyword, "after_workout", _} ->
        state = advance(state)
        state = expect_plus(state)
        {:ok, duration, state} = parse_duration(state)
        timing = %AST.NutritionTiming{type: :after_workout, duration: duration, time: nil}
        {:ok, timing, state}

      {:keyword, "before_workout", _} ->
        state = advance(state)
        state = expect_minus(state)
        {:ok, duration, state} = parse_duration(state)
        timing = %AST.NutritionTiming{type: :before_workout, duration: duration, time: nil}
        {:ok, timing, state}

      {:keyword, "at", _} ->
        state = advance(state)
        {:ok, time, state} = expect_time(state)
        timing = %AST.NutritionTiming{type: :at_time, duration: nil, time: time}
        {:ok, timing, state}

      _ ->
        {:ok, nil, state}
    end
  end

  @macro_units ~w(g g_per_kg)

  defp parse_macro_range(state) do
    {:ok, min, state} = expect_number(state)
    state = expect_range(state)
    {:ok, max, state} = expect_number(state)

    {unit, state} =
      case current_token(state) do
        {:bare_word, u, _} when u in @macro_units ->
          {u, advance(state)}

        _ ->
          {"g", state}
      end

    if unit == "g_per_kg" do
      {:ok, {min, max, unit}, state}
    else
      {:ok, {trunc(min), trunc(max), unit}, state}
    end
  end

  defp parse_fat_range(state) do
    case current_token(state) do
      {:lte, _, _} ->
        state = advance(state)
        {:ok, max, state} = expect_number(state)

        {unit, state} =
          case current_token(state) do
            {:bare_word, u, _} when u in @macro_units ->
              {u, advance(state)}

            _ ->
              {"g", state}
          end

        value = if unit == "g_per_kg", do: max, else: trunc(max)
        {:ok, {:max, value, unit}, state}

      _ ->
        parse_macro_range(state)
    end
  end

  defp parse_suggestion_list(state, suggestions) do
    state = skip_newlines(state)

    case current_token(state) do
      {:minus, _, _} ->
        state = advance(state)
        {:ok, value, state} = parse_value(state)
        parse_suggestion_list(state, [value | suggestions])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(suggestions), state}

      _ ->
        {:ok, Enum.reverse(suggestions), state}
    end
  end

  defp parse_meditation_activity(state) do
    state = advance(state)
    {:ok, category, state} = expect_bare_word(state)
    state = expect_colon(state)
    state = skip_newlines(state)

    state =
      case current_token(state) do
        {:indent, _, _} -> advance(state)
        _ -> state
      end

    {attrs, state} = parse_meditation_body(state, %{})

    meditation = %AST.Meditation{
      category: category,
      duration: attrs[:duration],
      guided: attrs[:guided],
      audio_id: attrs[:audio_id]
    }

    {:ok, meditation, state}
  end

  defp parse_meditation_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "duration", _} ->
        state = advance(state)
        {:ok, duration, state} = parse_duration(state)
        parse_meditation_body(state, Map.put(attrs, :duration, duration))

      {:keyword, "guided", _} ->
        state = advance(state)
        {:ok, value, state} = expect_boolean(state)
        parse_meditation_body(state, Map.put(attrs, :guided, value))

      {:keyword, "audio", _} ->
        state = advance(state)
        {:ok, audio_id, state} = expect_bare_word(state)
        parse_meditation_body(state, Map.put(attrs, :audio_id, audio_id))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  defp parse_recovery_activity(state) do
    state = advance(state)
    {:ok, category, state} = expect_bare_word(state)
    state = expect_colon(state)
    state = skip_newlines(state)

    state =
      case current_token(state) do
        {:indent, _, _} -> advance(state)
        _ -> state
      end

    {attrs, exercises, state} = parse_recovery_body(state, %{}, [])

    recovery = %AST.Recovery{
      category: category,
      duration: attrs[:duration],
      exercises: if(exercises == [], do: nil, else: exercises)
    }

    {:ok, recovery, state}
  end

  defp parse_recovery_body(state, attrs, exercises) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "duration", _} ->
        state = advance(state)
        {:ok, duration, state} = parse_duration(state)
        parse_recovery_body(state, Map.put(attrs, :duration, duration), exercises)

      {:bare_word, _name, _} ->
        {:ok, exercise, state} = parse_recovery_exercise(state)
        # Check if a pnf continuation line follows (same indent level)
        state = skip_newlines(state)
        {exercise, state} = maybe_parse_pnf_continuation(exercise, state)
        parse_recovery_body(state, attrs, [exercise | exercises])

      {:keyword, "pnf", _} ->
        # pnf line at the recovery body level — attach to the last exercise
        case exercises do
          [last | rest] ->
            {:ok, pnf_spec, state} = parse_pnf_spec(state)
            updated = %{last | pnf: pnf_spec}
            parse_recovery_body(state, attrs, [updated | rest])

          [] ->
            # No exercise to attach to; skip the pnf line
            state = skip_to_newline(state)
            parse_recovery_body(state, attrs, exercises)
        end

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, Enum.reverse(exercises), state}

      _ ->
        {attrs, Enum.reverse(exercises), state}
    end
  end

  defp maybe_parse_pnf_continuation(exercise, state) do
    case current_token(state) do
      {:keyword, "pnf", _} ->
        {:ok, pnf_spec, state} = parse_pnf_spec(state)
        {%{exercise | pnf: pnf_spec}, state}

      _ ->
        {exercise, state}
    end
  end

  # pnf <Ns> contract <Ns> relax <int> contractions
  defp parse_pnf_spec(state) do
    state = advance(state)
    {:ok, contraction_seconds, state} = expect_number(state)
    # skip optional 's' unit
    state =
      case current_token(state) do
        {tag, u, _} when tag in [:keyword, :bare_word] and u in ["s", "seconds"] -> advance(state)
        _ -> state
      end

    state = expect_keyword(state, "contract")
    {:ok, relax_seconds, state} = expect_number(state)
    # skip optional 's' unit
    state =
      case current_token(state) do
        {tag, u, _} when tag in [:keyword, :bare_word] and u in ["s", "seconds"] -> advance(state)
        _ -> state
      end

    state = expect_keyword(state, "relax")
    {:ok, contractions, state} = expect_number(state)
    state = expect_keyword(state, "contractions")

    pnf = %AST.PnfSpec{
      contraction_seconds: trunc(contraction_seconds),
      relax_seconds: trunc(relax_seconds),
      contractions: trunc(contractions)
    }

    {:ok, pnf, state}
  end

  defp skip_to_newline(state) do
    case current_token(state) do
      {:newline, _, _} -> state
      {:eof, _, _} -> state
      _ -> skip_to_newline(advance(state))
    end
  end

  defp parse_recovery_exercise(state) do
    {:ok, name, state} = expect_bare_word(state)
    {:ok, hold, state} = expect_number(state)

    # Cooldown subagents emit time units after the hold number —
    # `stretch_name 30s`, `mobility_flow 10m`, `hip_circles 5 min`. Without
    # swallowing them here, the unit leaks into the block and the next
    # bare_word gets treated as a new recovery exercise (e.g. a phantom
    # "m" item after `mobility_flow 10m`). Accept both :bare_word and
    # :keyword variants since `m`/`min` are lexed differently from
    # `seconds`/`minutes`.
    state =
      case current_token(state) do
        {tag, unit, _}
        when tag in [:bare_word, :keyword] and
               unit in ["s", "m", "h", "sec", "min", "seconds", "minutes", "hours"] ->
          advance(state)

        _ ->
          state
      end

    # Handle both "x" as keyword and bare_word
    state =
      case current_token(state) do
        {:keyword, "x", _} -> advance(state)
        {:bare_word, "x", _} -> advance(state)
        _ -> state
      end

    {:ok, reps, state} = expect_number(state)

    sides =
      case current_token(state) do
        {:keyword, "sides", _} ->
          state = advance(state)
          {:ok, side, state} = expect_bare_word(state)

          side_atom =
            case side do
              "both" -> :both
              "left" -> :left
              "right" -> :right
              _ -> :both
            end

          {side_atom, state}

        _ ->
          {nil, state}
      end

    {sides_val, state} = sides

    # Optional v1.6.0 modifiers: modality, intensity (-> intensity_rpe), body (-> body_part)
    {extra, state} = parse_recovery_exercise_extra(state, %{})

    exercise = %AST.RecoveryExercise{
      name: name,
      hold_seconds: trunc(hold),
      reps: trunc(reps),
      sides: sides_val,
      modality: extra[:modality],
      intensity_rpe: extra[:intensity_rpe],
      body_part: extra[:body_part],
      pnf: nil
    }

    {:ok, exercise, state}
  end

  defp parse_recovery_exercise_extra(state, extra) do
    case current_token(state) do
      {tag, "modality", _} when tag in [:keyword, :bare_word] ->
        state = advance(state)

        case current_token(state) do
          {tag2, modality, _} when tag2 in [:keyword, :bare_word] ->
            parse_recovery_exercise_extra(advance(state), Map.put(extra, :modality, modality))

          _ ->
            parse_recovery_exercise_extra(state, extra)
        end

      {tag, "intensity", _} when tag in [:keyword, :bare_word] ->
        state = advance(state)
        {:ok, value, state} = expect_number(state)
        parse_recovery_exercise_extra(state, Map.put(extra, :intensity_rpe, trunc(value)))

      {tag, "body", _} when tag in [:keyword, :bare_word] ->
        state = advance(state)
        {:ok, body, state} = expect_bare_word(state)
        parse_recovery_exercise_extra(state, Map.put(extra, :body_part, body))

      _ ->
        {extra, state}
    end
  end

  # Sub-plan inclusion activity (schema v1.5.0+):
  #   subplan plan_warmup_full_body
  #   subplan plan_warmup_full_body "Standard warmup"
  defp parse_sub_plan_activity(state) do
    state = advance(state)
    {:ok, ref, state} = expect_bare_word(state)

    {name, state} =
      case current_token(state) do
        {:string, s, _} -> {s, advance(state)}
        _ -> {nil, state}
      end

    sub_plan = %AST.SubPlan{
      sub_plan_ref: ref,
      name: name
    }

    {:ok, sub_plan, state}
  end

  defp parse_habit_activity(state) do
    state = advance(state)
    {:ok, category, state} = expect_bare_word(state)
    state = expect_colon(state)
    state = skip_newlines(state)

    state =
      case current_token(state) do
        {:indent, _, _} -> advance(state)
        _ -> state
      end

    {attrs, state} = parse_habit_body(state, %{})

    habit = %AST.Habit{
      category: category,
      target: attrs[:target],
      target_unit: attrs[:target_unit],
      frequency: attrs[:frequency],
      reminders: attrs[:reminders]
    }

    {:ok, habit, state}
  end

  defp parse_habit_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "target", _} ->
        state = advance(state)
        {:ok, value, state} = expect_number(state)
        {:ok, unit, state} = expect_bare_word(state)

        parse_habit_body(
          state,
          Map.merge(attrs, %{target: value, target_unit: unit})
        )

      {:keyword, "frequency", _} ->
        state = advance(state)
        {:ok, freq, state} = expect_bare_word(state)
        # Bug 6 fix: was calling parse_plan_habit_body here (wrong), which
        # does not handle `reminders`. Stay in parse_habit_body so subsequent
        # lines (reminders, etc.) are still parsed.
        parse_habit_body(state, Map.put(attrs, :frequency, freq))

      {:keyword, "reminders", _} ->
        state = advance(state)
        {:ok, times, state} = parse_time_list(state)
        parse_habit_body(state, Map.put(attrs, :reminders, times))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  defp parse_time_list(state, times \\ []) do
    case current_token(state) do
      {:time, time, _} ->
        state = advance(state)
        state = maybe_skip_comma(state)
        parse_time_list(state, [time | times])

      _ ->
        {:ok, Enum.reverse(times), state}
    end
  end

  # =============================================================================
  # Optional Sections (Progress, Notifications, Rendering)
  # =============================================================================

  defp parse_progress_section(state) do
    state = advance(state)
    state = skip_newlines(state)

    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        {attrs, state} = parse_progress_body(state, %{})

        progress = %AST.Progress{
          checkpoints: attrs[:checkpoints],
          points: attrs[:points],
          achievements: attrs[:achievements],
          streaks: attrs[:streaks]
        }

        {:ok, progress, state}

      _ ->
        {:ok, %AST.Progress{}, state}
    end
  end

  defp parse_progress_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      # Inline CHECKPOINT keyword (TS-style): CHECKPOINT "Name":
      {:keyword, "CHECKPOINT", _} ->
        {:ok, checkpoint, state} = parse_checkpoint_inline(state)
        checkpoints = Map.get(attrs, :checkpoints, [])
        parse_progress_body(state, Map.put(attrs, :checkpoints, checkpoints ++ [checkpoint]))

      {:keyword, "checkpoints", _} ->
        state = advance(state)
        state = expect_colon(state)
        state = skip_newlines(state)
        state = expect_indent(state)
        {:ok, checkpoints, state} = parse_checkpoints(state, [])
        parse_progress_body(state, Map.put(attrs, :checkpoints, checkpoints))

      {:keyword, "points", _} ->
        state = advance(state)
        {:ok, enabled, state} = expect_enabled_disabled(state)
        {rules, state} = parse_points_rules(state)
        config = %AST.PointsConfig{enabled: enabled, rules: rules}
        parse_progress_body(state, Map.put(attrs, :points, config))

      {:keyword, "achievements", _} ->
        state = advance(state)
        state = expect_colon(state)
        state = skip_newlines(state)
        state = expect_indent(state)
        {:ok, achievements, state} = parse_achievements(state, [])
        parse_progress_body(state, Map.put(attrs, :achievements, achievements))

      {:keyword, "streaks", _} ->
        state = advance(state)
        {:ok, enabled, state} = expect_enabled_disabled(state)
        {types, state} = parse_streaks_types(state)
        config = %AST.StreaksConfig{enabled: enabled, types: types}
        parse_progress_body(state, Map.put(attrs, :streaks, config))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  defp parse_checkpoints(state, checkpoints) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "checkpoint", _} ->
        {:ok, checkpoint, state} = parse_checkpoint(state)
        parse_checkpoints(state, [checkpoint | checkpoints])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(checkpoints), state}

      _ ->
        {:ok, Enum.reverse(checkpoints), state}
    end
  end

  defp parse_checkpoint(state) do
    state = advance(state)
    {:ok, name, state} = expect_string(state)
    state = expect_colon(state)
    state = skip_newlines(state)
    state = expect_indent(state)
    {attrs, state} = parse_checkpoint_body(state, %{})

    checkpoint = %AST.Checkpoint{
      name: name,
      trigger: attrs[:trigger],
      measurements: attrs[:measurements],
      questions: attrs[:questions]
    }

    {:ok, checkpoint, state}
  end

  # TS-style inline CHECKPOINT "Name": block (no `checkpoints:` wrapper)
  defp parse_checkpoint_inline(state) do
    state = advance(state)
    {:ok, name, state} = expect_string(state)
    state = expect_colon(state)
    state = skip_newlines(state)

    state =
      case current_token(state) do
        {:indent, _, _} -> advance(state)
        _ -> state
      end

    {attrs, state} = parse_checkpoint_body_inline(state, %{})

    checkpoint = %AST.Checkpoint{
      name: name,
      trigger: attrs[:trigger],
      measurements: attrs[:measurements],
      questions: attrs[:questions]
    }

    {:ok, checkpoint, state}
  end

  defp parse_checkpoint_body_inline(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      # `at N weeks/days` — shorthand trigger form (TS-style)
      {:keyword, "at", _} ->
        state = advance(state)
        {:ok, value, state} = expect_number(state)

        {unit, state} =
          case current_token(state) do
            {tag, u, _} when tag in [:keyword, :bare_word] ->
              {parse_time_unit(u), advance(state)}

            _ ->
              {:weeks, state}
          end

        # Store as {:time, value, unit_atom} — compiler uses the value + unit
        trigger = {:time, trunc(value), unit}
        parse_checkpoint_body_inline(state, Map.put(attrs, :trigger, trigger))

      {:keyword, "measure", _} ->
        state = advance(state)
        state = expect_colon(state)
        state = skip_newlines(state)
        state = expect_indent(state)
        {:ok, measurements, state} = parse_typed_measurement_list(state, [])
        parse_checkpoint_body_inline(state, Map.put(attrs, :measurements, measurements))

      {:keyword, "ask", _} ->
        state = advance(state)
        state = expect_colon(state)
        state = skip_newlines(state)
        state = expect_indent(state)
        {:ok, questions, state} = parse_string_list(state, [])
        parse_checkpoint_body_inline(state, Map.put(attrs, :questions, questions))

      {:keyword, "trigger", _} ->
        state = advance(state)
        {:ok, trigger, state} = parse_trigger(state)
        parse_checkpoint_body_inline(state, Map.put(attrs, :trigger, trigger))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      {:keyword, "CHECKPOINT", _} ->
        # Next sibling checkpoint — stop
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  defp parse_checkpoint_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "trigger", _} ->
        state = advance(state)
        {:ok, trigger, state} = parse_trigger(state)
        parse_checkpoint_body(state, Map.put(attrs, :trigger, trigger))

      {:keyword, "measure", _} ->
        state = advance(state)
        state = expect_colon(state)
        state = skip_newlines(state)
        state = expect_indent(state)
        {:ok, measurements, state} = parse_string_list(state, [])
        parse_checkpoint_body(state, Map.put(attrs, :measurements, measurements))

      {:keyword, "ask", _} ->
        state = advance(state)
        state = expect_colon(state)
        state = skip_newlines(state)
        state = expect_indent(state)
        {:ok, questions, state} = parse_string_list(state, [])
        parse_checkpoint_body(state, Map.put(attrs, :questions, questions))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  defp parse_trigger(state) do
    case current_token(state) do
      {:keyword, "at", _} ->
        # "at N weeks" or "at N days"
        state = advance(state)
        {:ok, n, state} = expect_number(state)

        case current_token(state) do
          {:keyword, unit, _} when unit in ["weeks", "days"] ->
            state = advance(state)
            {:ok, {:at, trunc(n), String.to_atom(unit)}, state}

          _ ->
            {:ok, {:at, trunc(n), :weeks}, state}
        end

      {:keyword, "time", _} ->
        state = advance(state)
        state = expect_keyword(state, "week")
        {:ok, week, state} = expect_number(state)
        state = expect_keyword(state, "day")
        {:ok, day, state} = expect_number(state)
        {:ok, {:time, trunc(week), trunc(day)}, state}

      # Bug 5 fix: `trigger completion` (no-arg) used to silently return :completion
      # which swallowed downstream sections. Now emit an explicit parse error.
      # Note: "completion" is lexed as :bare_word (not in @keywords).
      {tag, "completion", _} when tag in [:keyword, :bare_word] ->
        loc = current_location(state)
        state = advance(state)

        error =
          ParseError.invalid_structure(
            "Unsupported checkpoint trigger 'completion' — use 'at N weeks' or 'at N days'.",
            loc
          )

        state = %{state | errors: [error | state.errors]}
        {:ok, :manual, state}

      {:keyword, "manual", _} ->
        {:ok, :manual, advance(state)}

      _ ->
        {:ok, :manual, state}
    end
  end

  # Parse a typed measurement list. Items are one of:
  #   - bare metric token (bare_word or keyword matching @measurement_metrics)
  #   - `<metric> questionnaire <enum> [note "text"]`
  #   - quoted string (back-compat plain string)
  defp parse_typed_measurement_list(state, items) do
    state = skip_newlines(state)

    case current_token(state) do
      {:string, str, _} ->
        state = advance(state)
        parse_typed_measurement_list(state, [str | items])

      {:minus, _, _} ->
        # Dash-prefixed items: "- body_weight_kg" or "- questionnaire_score questionnaire psqi note '...'"
        state = advance(state)

        case current_token(state) do
          {:string, str, _} ->
            state = advance(state)
            parse_typed_measurement_list(state, [str | items])

          {tag, metric, _} when tag in [:keyword, :bare_word] ->
            state = advance(state)

            # Check for optional `questionnaire <enum> [note "text"]` qualifiers
            {item, state} =
              case current_token(state) do
                {:keyword, "questionnaire", _} ->
                  state = advance(state)

                  {questionnaire, state} =
                    case current_token(state) do
                      {qtag, qval, _} when qtag in [:keyword, :bare_word] ->
                        {qval, advance(state)}

                      _ ->
                        {nil, state}
                    end

                  {note, state} =
                    case current_token(state) do
                      {:keyword, "note", _} ->
                        state = advance(state)
                        {:ok, n, state} = expect_string(state)
                        {n, state}

                      {:bare_word, "note", _} ->
                        state = advance(state)
                        {:ok, n, state} = expect_string(state)
                        {n, state}

                      _ ->
                        {nil, state}
                    end

                  {%AST.MeasurementSpec{metric: metric, questionnaire: questionnaire, note: note},
                   state}

                _ ->
                  {%AST.MeasurementSpec{metric: metric}, state}
              end

            parse_typed_measurement_list(state, [item | items])

          _ ->
            parse_typed_measurement_list(state, items)
        end

      {tag, metric, _} when tag in [:keyword, :bare_word] ->
        state = advance(state)

        # Check for optional `questionnaire <enum> [note "text"]`
        spec =
          case current_token(state) do
            {:keyword, "questionnaire", _} ->
              state = advance(state)

              {questionnaire, state} =
                case current_token(state) do
                  {qtag, qval, _} when qtag in [:keyword, :bare_word] ->
                    {qval, advance(state)}

                  _ ->
                    {nil, state}
                end

              {note, state} =
                case current_token(state) do
                  {:keyword, "note", _} ->
                    state = advance(state)
                    {:ok, n, state} = expect_string(state)
                    {n, state}

                  {:bare_word, "note", _} ->
                    state = advance(state)
                    {:ok, n, state} = expect_string(state)
                    {n, state}

                  _ ->
                    {nil, state}
                end

              {%AST.MeasurementSpec{metric: metric, questionnaire: questionnaire, note: note},
               state}

            _ ->
              {%AST.MeasurementSpec{metric: metric}, state}
          end

        {item, state} =
          if is_tuple(spec) do
            spec
          else
            {spec, state}
          end

        parse_typed_measurement_list(state, [item | items])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(items), state}

      _ ->
        {:ok, Enum.reverse(items), state}
    end
  end

  defp parse_string_list(state, items) do
    state = skip_newlines(state)

    case current_token(state) do
      {:minus, _, _} ->
        state = advance(state)

        {:ok, value, state} =
          case current_token(state) do
            {:string, str, _} -> {:ok, str, advance(state)}
            {:bare_word, word, _} -> {:ok, word, advance(state)}
            _ -> {:ok, "", state}
          end

        parse_string_list(state, [value | items])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(items), state}

      _ ->
        {:ok, Enum.reverse(items), state}
    end
  end

  defp parse_points_rules(state) do
    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        state = skip_newlines(state)

        case current_token(state) do
          {:keyword, "rules", _} ->
            state = advance(state)
            state = expect_colon(state)
            state = skip_newlines(state)
            state = expect_indent(state)
            {:ok, rules, state} = parse_points_rules_list(state, [])

            state =
              case current_token(state) do
                {:dedent, _, _} -> advance(state)
                _ -> state
              end

            {rules, state}

          {:dedent, _, _} ->
            {nil, advance(state)}

          _ ->
            {nil, state}
        end

      _ ->
        {nil, state}
    end
  end

  defp parse_points_rules_list(state, rules) do
    state = skip_newlines(state)

    case current_token(state) do
      {:minus, _, _} ->
        state = advance(state)
        {:ok, name, state} = expect_bare_word(state)
        {:ok, points, state} = expect_number(state)
        parse_points_rules_list(state, [{name, trunc(points)} | rules])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(rules), state}

      _ ->
        {:ok, Enum.reverse(rules), state}
    end
  end

  defp parse_achievements(state, achievements) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "achievement", _} ->
        {:ok, achievement, state} = parse_achievement(state)
        parse_achievements(state, [achievement | achievements])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(achievements), state}

      _ ->
        {:ok, Enum.reverse(achievements), state}
    end
  end

  defp parse_achievement(state) do
    state = advance(state)
    {:ok, id, state} = expect_bare_word(state)
    state = expect_colon(state)
    state = skip_newlines(state)
    state = expect_indent(state)
    {attrs, state} = parse_achievement_body(state, %{})

    achievement = %AST.Achievement{
      id: id,
      name: attrs[:name],
      description: attrs[:description],
      condition: attrs[:condition],
      condition_value: attrs[:condition_value],
      points: attrs[:points]
    }

    {:ok, achievement, state}
  end

  defp parse_achievement_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "name", _} ->
        state = advance(state)
        {:ok, name, state} = expect_string(state)
        parse_achievement_body(state, Map.put(attrs, :name, name))

      {:keyword, "description", _} ->
        state = advance(state)
        {:ok, desc, state} = expect_string(state)
        parse_achievement_body(state, Map.put(attrs, :description, desc))

      {:keyword, "condition", _} ->
        state = advance(state)
        {:ok, cond_name, state} = expect_bare_word(state)
        {:ok, cond_value, state} = expect_number(state)

        parse_achievement_body(
          state,
          Map.merge(attrs, %{condition: cond_name, condition_value: trunc(cond_value)})
        )

      {:keyword, "points", _} ->
        state = advance(state)
        {:ok, points, state} = expect_number(state)
        parse_achievement_body(state, Map.put(attrs, :points, trunc(points)))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  defp parse_streaks_types(state) do
    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        state = skip_newlines(state)

        case current_token(state) do
          {:keyword, "types", _} ->
            state = advance(state)
            {:ok, types, state} = parse_enum_list(state)

            state =
              case current_token(state) do
                {:dedent, _, _} -> advance(state)
                _ -> state
              end

            {types, state}

          {:dedent, _, _} ->
            {nil, advance(state)}

          _ ->
            {nil, state}
        end

      _ ->
        {nil, state}
    end
  end

  defp parse_notifications_section(state) do
    state = advance(state)
    state = skip_newlines(state)

    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        {:ok, notifications, state} = parse_notifications(state, [])
        {:ok, notifications, state}

      _ ->
        {:ok, [], state}
    end
  end

  defp parse_notifications(state, notifications) do
    state = skip_newlines(state)

    case current_token(state) do
      {:bare_word, _id, _} ->
        {:ok, notification, state} = parse_notification(state)
        parse_notifications(state, [notification | notifications])

      {:dedent, _, _} ->
        state = advance(state)
        {:ok, Enum.reverse(notifications), state}

      _ ->
        {:ok, Enum.reverse(notifications), state}
    end
  end

  defp parse_notification(state) do
    {:ok, id, state} = expect_bare_word(state)
    state = expect_colon(state)
    state = skip_newlines(state)
    state = expect_indent(state)
    {attrs, state} = parse_notification_body(state, %{})

    notification = %AST.Notification{
      id: id,
      enabled: attrs[:enabled] || false,
      timing: attrs[:timing],
      message: attrs[:message]
    }

    {:ok, notification, state}
  end

  defp parse_notification_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "enabled", _} ->
        state = advance(state)
        {:ok, value, state} = expect_boolean(state)
        parse_notification_body(state, Map.put(attrs, :enabled, value))

      {:keyword, "timing", _} ->
        state = advance(state)
        {:ok, duration, state} = parse_duration(state)
        state = expect_keyword(state, "before")
        {:ok, event, state} = expect_bare_word(state)
        parse_notification_body(state, Map.put(attrs, :timing, {duration, event}))

      {:keyword, "message", _} ->
        state = advance(state)
        {:ok, message, state} = expect_string(state)
        parse_notification_body(state, Map.put(attrs, :message, message))

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  defp parse_rendering_section(state) do
    state = advance(state)
    state = skip_newlines(state)

    case current_token(state) do
      {:indent, _, _} ->
        state = advance(state)
        {attrs, state} = parse_rendering_body(state, %{})

        rendering = %AST.Rendering{
          primary_color: attrs[:primary],
          secondary_color: attrs[:secondary],
          accent_color: attrs[:accent],
          icons: attrs[:icons],
          difficulty_colors: attrs[:difficulty_colors]
        }

        {:ok, rendering, state}

      _ ->
        {:ok, %AST.Rendering{}, state}
    end
  end

  defp parse_rendering_body(state, attrs) do
    state = skip_newlines(state)

    case current_token(state) do
      {:keyword, "primary", _} ->
        state = advance(state)
        {:ok, color, state} = expect_string(state)
        parse_rendering_body(state, Map.put(attrs, :primary, color))

      {:keyword, "secondary", _} ->
        state = advance(state)
        {:ok, color, state} = expect_string(state)
        parse_rendering_body(state, Map.put(attrs, :secondary, color))

      {:keyword, "accent", _} ->
        state = advance(state)
        {:ok, color, state} = expect_string(state)
        parse_rendering_body(state, Map.put(attrs, :accent, color))

      {:keyword, "icon", _} ->
        state = advance(state)
        {:ok, icon_name, state} = expect_bare_word(state)
        state = expect_eq(state)
        {:ok, icon_value, state} = expect_bare_word(state)
        icons = Map.get(attrs, :icons, %{})
        parse_rendering_body(state, Map.put(attrs, :icons, Map.put(icons, icon_name, icon_value)))

      {:keyword, "difficulty_color", _} ->
        state = advance(state)
        {:ok, difficulty, state} = expect_bare_word(state)
        state = expect_eq(state)
        {:ok, color, state} = expect_string(state)
        colors = Map.get(attrs, :difficulty_colors, %{})

        parse_rendering_body(
          state,
          Map.put(attrs, :difficulty_colors, Map.put(colors, difficulty, color))
        )

      {:dedent, _, _} ->
        state = advance(state)
        {attrs, state}

      _ ->
        {attrs, state}
    end
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp parse_duration(state) do
    {:ok, value, state} = expect_number(state)
    {:ok, unit, state} = expect_bare_word(state)

    duration = %AST.Duration{
      value: value,
      unit: parse_time_unit(unit)
    }

    {:ok, duration, state}
  end

  defp parse_duration_inline(state) do
    case current_token(state) do
      {:number, value, _} ->
        state = advance(state)
        # Check for unit suffix
        case current_token(state) do
          {:bare_word, unit, _} when unit in ["m", "s", "h", "minutes", "seconds", "hours"] ->
            state = advance(state)
            duration = %AST.Duration{value: value, unit: parse_time_unit(unit)}
            {:ok, duration, state}

          _ ->
            # Assume minutes
            duration = %AST.Duration{value: value, unit: :minutes}
            {:ok, duration, state}
        end

      _ ->
        {:ok, %AST.Duration{value: 0, unit: :minutes}, state}
    end
  end

  defp parse_time_unit(unit) do
    case unit do
      "s" -> :seconds
      "second" -> :seconds
      "seconds" -> :seconds
      "m" -> :minutes
      "min" -> :minutes
      "minute" -> :minutes
      "minutes" -> :minutes
      "h" -> :hours
      "hour" -> :hours
      "hours" -> :hours
      "d" -> :days
      "day" -> :days
      "days" -> :days
      "week" -> :weeks
      "weeks" -> :weeks
      "wk" -> :weeks
      "wks" -> :weeks
      _ -> :minutes
    end
  end

  # Bug 1 + 2 fix: accept number tokens and glue number+bare_word sequences in
  # TAGS context. The lexer produces {:number, 531, _} for "531" and a pair of
  # {:number, 1, _} + {:bare_word, "rm_estimate", _} for "1rm_estimate".
  defp parse_tag_list(state) do
    parse_tag_list_items(state, [])
  end

  defp parse_tag_list_items(state, items) do
    case current_token(state) do
      {:bare_word, word, _} ->
        state = advance(state)
        state = maybe_skip_comma(state)
        parse_tag_list_items(state, [word | items])

      {:keyword, word, _} ->
        state = advance(state)
        state = maybe_skip_comma(state)
        parse_tag_list_items(state, [word | items])

      {:number, num, _} ->
        # Could be a standalone digit-leading tag ("531") or the prefix of a
        # digit-leading identifier ("1rm_estimate" → number(1) + bare_word("rm_estimate")).
        state = advance(state)
        num_str = if is_float(num), do: Float.to_string(num), else: Integer.to_string(trunc(num))

        {tag_str, state} =
          case current_token(state) do
            {:bare_word, suffix, _} ->
              # Glue: "1" + "rm_estimate" → "1rm_estimate"
              {num_str <> suffix, advance(state)}

            _ ->
              {num_str, state}
          end

        state = maybe_skip_comma(state)
        parse_tag_list_items(state, [tag_str | items])

      _ ->
        {:ok, Enum.reverse(items), state}
    end
  end

  defp parse_enum_list(state, items \\ []) do
    case current_token(state) do
      {:bare_word, word, _} ->
        state = advance(state)
        state = maybe_skip_comma(state)
        parse_enum_list(state, [word | items])

      {:keyword, word, _} ->
        state = advance(state)
        state = maybe_skip_comma(state)
        parse_enum_list(state, [word | items])

      _ ->
        {:ok, Enum.reverse(items), state}
    end
  end

  defp expect_bare_word(state) do
    case current_token(state) do
      {:bare_word, word, _} ->
        {:ok, word, advance(state)}

      {:keyword, word, _} ->
        {:ok, word, advance(state)}

      {_type, value, _loc} ->
        {:ok, "#{value}", state}
    end
  end

  defp expect_bare_word_or_keyword(state) do
    case current_token(state) do
      {:bare_word, word, _} -> {:ok, word, advance(state)}
      {:keyword, word, _} -> {:ok, word, advance(state)}
      _ -> {:ok, "", state}
    end
  end

  defp expect_string(state) do
    case current_token(state) do
      {:string, str, _} ->
        {:ok, str, advance(state)}

      _ ->
        {:ok, "", state}
    end
  end

  defp expect_number(state) do
    case current_token(state) do
      {:number, num, _} ->
        {:ok, num, advance(state)}

      _ ->
        {:ok, 0, state}
    end
  end

  defp expect_date(state) do
    case current_token(state) do
      {:date, date, _} ->
        {:ok, date, advance(state)}

      _ ->
        {:ok, Date.utc_today(), state}
    end
  end

  defp expect_time(state) do
    case current_token(state) do
      {:time, time, _} ->
        {:ok, time, advance(state)}

      _ ->
        {:ok, ~T[00:00:00], state}
    end
  end

  defp expect_boolean(state) do
    case current_token(state) do
      {:keyword, "true", _} -> {:ok, true, advance(state)}
      {:keyword, "false", _} -> {:ok, false, advance(state)}
      {:bare_word, "true", _} -> {:ok, true, advance(state)}
      {:bare_word, "false", _} -> {:ok, false, advance(state)}
      _ -> {:ok, false, state}
    end
  end

  defp expect_enabled_disabled(state) do
    case current_token(state) do
      {:keyword, "enabled", _} -> {:ok, true, advance(state)}
      {:keyword, "disabled", _} -> {:ok, false, advance(state)}
      _ -> {:ok, false, state}
    end
  end

  defp expect_colon(state) do
    case current_token(state) do
      {:colon, _, _} -> advance(state)
      _ -> state
    end
  end

  defp expect_lparen(state) do
    case current_token(state) do
      {:lparen, _, _} -> advance(state)
      _ -> state
    end
  end

  defp expect_rparen(state) do
    case current_token(state) do
      {:rparen, _, _} -> advance(state)
      _ -> state
    end
  end

  defp expect_range(state) do
    case current_token(state) do
      {:range, _, _} -> advance(state)
      _ -> state
    end
  end

  defp expect_arrow(state) do
    case current_token(state) do
      {:arrow, _, _} -> advance(state)
      _ -> state
    end
  end

  defp expect_eq(state) do
    case current_token(state) do
      {:eq, _, _} -> advance(state)
      _ -> state
    end
  end

  defp expect_percent(state) do
    case current_token(state) do
      {:percent, _, _} -> advance(state)
      _ -> state
    end
  end

  defp expect_plus(state) do
    case current_token(state) do
      {:plus, _, _} -> advance(state)
      _ -> state
    end
  end

  defp expect_minus(state) do
    case current_token(state) do
      {:minus, _, _} -> advance(state)
      _ -> state
    end
  end

  # Accept either :minus or :range as a separator — after the N-M range fix,
  # `3-1` in tempo context produces [:number, :range, :number] rather than
  # [:number :minus :number]. Both forms must advance past the separator.
  defp expect_minus_or_range(state) do
    case current_token(state) do
      {:minus, _, _} -> advance(state)
      {:range, _, _} -> advance(state)
      _ -> state
    end
  end

  defp expect_slash(state) do
    case current_token(state) do
      {:slash, _, _} -> advance(state)
      _ -> state
    end
  end

  defp expect_indent(state) do
    case current_token(state) do
      {:indent, _, _} -> advance(state)
      _ -> state
    end
  end

  defp expect_keyword(state, expected) do
    case current_token(state) do
      {:keyword, ^expected, _} -> advance(state)
      {:bare_word, ^expected, _} -> advance(state)
      _ -> state
    end
  end

  defp maybe_skip_comma(state) do
    case current_token(state) do
      {:comma, _, _} -> advance(state)
      _ -> state
    end
  end

  defp skip_newlines(state) do
    case current_token(state) do
      {:newline, _, _} -> skip_newlines(advance(state))
      _ -> state
    end
  end

  defp skip_dedents(state) do
    case current_token(state) do
      {:dedent, _, _} -> skip_dedents(advance(state))
      _ -> state
    end
  end

  defp current_token(%{tokens: tokens, pos: pos}) do
    if pos < length(tokens) do
      Enum.at(tokens, pos)
    else
      {:eof, nil, Location.new(0, 0)}
    end
  end

  defp current_location(%{tokens: tokens, pos: pos}) do
    case current_token(%{tokens: tokens, pos: pos}) do
      {_, _, loc} -> loc
      _ -> Location.new(0, 0)
    end
  end

  # Canonicalize the weight metric DSL token to its schema enum value.
  # DSL is case-insensitive; schema uses mixed-case for some values.
  defp canonicalize_weight_metric(token) do
    case String.downcase(token) do
      "1rm" -> "1RM"
      "e1rm" -> "e1RM"
      "training_max" -> "training_max"
      "daily_max" -> "daily_max"
      other -> other
    end
  end

  defp advance(state) do
    %{state | pos: state.pos + 1}
  end

  defp peek_token(%{tokens: tokens, pos: pos}, offset) do
    target = pos + offset

    if target < length(tokens) do
      Enum.at(tokens, target)
    else
      {:eof, nil, Location.new(0, 0)}
    end
  end
end
