defmodule WplAi.Decompiler do
  @moduledoc """
  Decompiles WPL JSON to WPL-AI text format.

  This enables round-trip transformation and allows LLMs to edit
  existing plans in the more readable WPL-AI format.

  ## Example

      iex> json = %{"plan" => %{"name" => "Test", "type" => "workout", ...}}
      iex> {:ok, text} = Decompiler.decompile(json)
      iex> text
      \"\"\"
      PLAN "Test"
      TYPE workout
      ...
      \"\"\"

  """

  @indent "  "

  @doc """
  Decompile WPL JSON to WPL-AI text.

  Returns `{:ok, text}` on success, or `{:error, reason}` on failure.
  """
  @spec decompile(map()) :: {:ok, String.t()} | {:error, term()}
  def decompile(%{"plan" => plan} = _json) do
    lines = []

    # Header
    lines = lines ++ decompile_header(plan)

    # Goals
    lines =
      case plan["goals"] do
        goals when is_list(goals) and goals != [] ->
          lines ++ [""] ++ decompile_goals(goals)

        _ ->
          lines
      end

    # Requirements
    lines =
      case plan["requirements"] do
        req when is_map(req) and map_size(req) > 0 ->
          lines ++ [""] ++ decompile_requirements(req)

        _ ->
          lines
      end

    # Personalization
    lines =
      case plan["personalization"] do
        pers when is_map(pers) ->
          rules = pers["rules"] || []

          if rules != [] do
            lines ++ [""] ++ decompile_personalization(pers)
          else
            lines
          end

        _ ->
          lines
      end

    # Phases
    lines =
      case plan["phases"] do
        phases when is_list(phases) and phases != [] ->
          lines ++ [""] ++ decompile_phases(phases)

        _ ->
          lines
      end

    # Progress
    lines =
      case plan["progress"] do
        progress when is_map(progress) and map_size(progress) > 0 ->
          lines ++ [""] ++ decompile_progress(progress)

        _ ->
          lines
      end

    {:ok, Enum.join(lines, "\n") <> "\n"}
  end

  def decompile(_), do: {:error, :invalid_json_structure}

  @doc """
  Decompile WPL JSON to WPL-AI text, raising on error.
  """
  @spec decompile!(map()) :: String.t()
  def decompile!(json) do
    case decompile(json) do
      {:ok, text} -> text
      {:error, reason} -> raise "Decompile error: #{inspect(reason)}"
    end
  end

  # =============================================================================
  # Header Decompilation
  # =============================================================================

  defp decompile_header(plan) do
    lines = [
      ~s(PLAN "#{plan["name"]}"),
      "TYPE #{plan["type"]}"
    ]

    lines =
      case plan["visibility"] do
        vis when vis in ["private", "public", "template"] ->
          lines ++ ["VISIBILITY #{vis}"]

        _ ->
          lines
      end

    metadata = plan["metadata"] || %{}

    lines =
      case metadata["difficulty"] do
        diff when is_binary(diff) ->
          lines ++ ["DIFFICULTY #{diff}"]

        _ ->
          lines
      end

    lines =
      case metadata["tags"] do
        tags when is_list(tags) and tags != [] ->
          lines ++ ["TAGS #{Enum.join(tags, ", ")}"]

        _ ->
          lines
      end

    lines =
      case metadata["language"] do
        lang when is_binary(lang) ->
          lines ++ ["LANGUAGE #{lang}"]

        _ ->
          lines
      end

    lines
  end

  # =============================================================================
  # Goals Decompilation
  # =============================================================================

  defp decompile_goals(goals) do
    goal_lines =
      goals
      |> Enum.flat_map(&decompile_goal/1)

    ["GOALS"] ++ goal_lines
  end

  defp decompile_goal(goal) do
    priority = goal["type"] || "primary"
    category = goal["category"]

    line = "#{@indent}GOAL #{priority} #{category}:"

    target_lines =
      case goal["target"] do
        %{"metric" => metric, "target_value" => value, "unit" => unit} = target ->
          measurement = target["measurement_type"] || "absolute"
          ["#{@indent}#{@indent}target #{metric} #{value} #{unit} #{measurement}"]

        _ ->
          []
      end

    [line] ++ target_lines
  end

  # =============================================================================
  # Requirements Decompilation
  # =============================================================================

  defp decompile_requirements(req) do
    lines = ["REQUIRES"]

    # Age range
    lines =
      case {req["min_age"], req["max_age"]} do
        {min, max} when is_integer(min) and is_integer(max) ->
          lines ++ ["#{@indent}age #{min}..#{max}"]

        _ ->
          lines
      end

    # Fitness levels
    lines =
      case req["fitness_level"] do
        levels when is_list(levels) and levels != [] ->
          lines ++ ["#{@indent}fitness #{Enum.join(levels, ", ")}"]

        _ ->
          lines
      end

    # Equipment
    lines =
      case req["equipment"] do
        equipment when is_list(equipment) and equipment != [] ->
          equip_lines =
            equipment
            |> Enum.map(&decompile_equipment/1)
            |> Enum.map(&("#{@indent}#{@indent}" <> &1))

          lines ++ ["#{@indent}equipment:"] ++ equip_lines

        _ ->
          lines
      end

    # Contraindications
    lines =
      case req["contraindications"] do
        contras when is_list(contras) and contras != [] ->
          contra_lines =
            contras
            |> Enum.map(&decompile_contraindication/1)
            |> Enum.map(&("#{@indent}#{@indent}" <> &1))

          lines ++ ["#{@indent}contraindications:"] ++ contra_lines

        _ ->
          lines
      end

    lines
  end

  defp decompile_equipment(equip) do
    name = equip["name"]
    required = if equip["required"], do: "required", else: "optional"

    case equip["alternatives"] do
      alts when is_list(alts) and alts != [] ->
        "#{name} (#{required}, alternatives: #{Enum.join(alts, ", ")})"

      _ ->
        "#{name} (#{required})"
    end
  end

  defp decompile_contraindication(contra) do
    condition = contra["condition"]
    action = contra["action"] || "exclude"

    case contra["affected_activities"] do
      affects when is_list(affects) and affects != [] ->
        "#{condition} #{action} #{Enum.join(affects, ", ")}"

      _ ->
        "#{condition} #{action}"
    end
  end

  # =============================================================================
  # Personalization Decompilation
  # =============================================================================

  defp decompile_personalization(pers) do
    lines = ["PERSONALIZATION"]

    # Rules
    lines =
      case pers["rules"] do
        rules when is_list(rules) and rules != [] ->
          rule_lines = Enum.flat_map(rules, &decompile_rule/1)
          lines ++ ["#{@indent}RULES"] ++ rule_lines

        _ ->
          lines
      end

    lines
  end

  defp decompile_rule(rule) do
    condition = decompile_condition(rule["condition"])
    actions = rule["actions"] || []

    when_line = "#{@indent}#{@indent}WHEN #{condition}:"

    action_lines =
      Enum.map(actions, fn action ->
        "#{@indent}#{@indent}#{@indent}#{decompile_action(action)}"
      end)

    [when_line] ++ action_lines
  end

  defp decompile_condition(%{"operator" => operator, "conditions" => conditions})
       when is_list(conditions) do
    # Compound condition
    cond_strs =
      Enum.map(conditions, fn c ->
        "#{c["field"]} #{format_op(c["op"])} #{format_value(c["value"])}"
      end)

    joiner = if operator == "and", do: " AND ", else: " OR "
    Enum.join(cond_strs, joiner)
  end

  defp decompile_condition(%{"field" => field, "op" => op, "value" => value}) do
    # Simple condition
    "#{field} #{format_op(op)} #{format_value(value)}"
  end

  defp decompile_condition(_), do: "true"

  defp format_op("eq"), do: "=="
  defp format_op("neq"), do: "!="
  defp format_op("gt"), do: ">"
  defp format_op("gte"), do: ">="
  defp format_op("lt"), do: "<"
  defp format_op("lte"), do: "<="
  defp format_op("contains"), do: "contains"
  defp format_op("not_contains"), do: "not contains"
  defp format_op(op), do: op

  defp format_value(v) when is_binary(v), do: v
  defp format_value(v), do: inspect(v)

  defp decompile_action(%{"type" => "replace_exercise"} = action) do
    from = action["from"]
    to = action["to"]
    "replace #{from} -> #{to}"
  end

  defp decompile_action(%{"type" => "exclude_exercise"} = action) do
    exercise = action["exercise"]
    "exclude #{exercise}"
  end

  defp decompile_action(%{"type" => "reduce_sets"} = action) do
    amount = action["amount"] || 1
    "reduce sets by #{amount}"
  end

  defp decompile_action(%{"type" => "reduce_reps"} = action) do
    amount = action["amount"] || 1
    "reduce reps by #{amount}"
  end

  defp decompile_action(%{"type" => "reduce_intensity"} = action) do
    amount = action["amount"] || action["by"] || 10
    "reduce intensity by #{amount} %"
  end

  defp decompile_action(%{"type" => "modify_intensity"} = action) do
    amount = action["amount"] || action["by"] || 10
    "reduce intensity by #{amount} %"
  end

  defp decompile_action(%{"type" => type}), do: type

  # =============================================================================
  # Phases Decompilation
  # =============================================================================

  defp decompile_phases(phases) do
    phase_lines = Enum.flat_map(phases, &decompile_phase/1)
    ["PHASES"] ++ phase_lines
  end

  defp decompile_phase(phase) do
    name = phase["name"]
    duration = decompile_duration_inline(phase["duration"])

    header = "#{@indent}PHASE \"#{name}\" (#{duration}):"

    week_lines =
      (phase["weeks"] || [])
      |> Enum.flat_map(&decompile_week/1)

    [header] ++ week_lines
  end

  defp decompile_week(week) do
    number = week["order"] || 1
    header = "#{@indent}#{@indent}WEEK #{number}:"

    day_lines =
      (week["days"] || [])
      |> Enum.flat_map(&decompile_day/1)

    [header] ++ day_lines
  end

  defp decompile_day(day) do
    day_name = number_to_day_name(day["day_of_week"])
    day_type = day["type"] || "training"
    duration = format_duration_short(day["estimated_duration_minutes"])
    label = day["name"]

    header =
      if label do
        "#{@indent}#{@indent}#{@indent}DAY #{day_name} #{day_type} #{duration} \"#{label}\":"
      else
        "#{@indent}#{@indent}#{@indent}DAY #{day_name} #{day_type} #{duration}:"
      end

    block_lines =
      (day["blocks"] || [])
      |> Enum.flat_map(&decompile_block/1)

    [header] ++ block_lines
  end

  defp decompile_block(block) do
    type = block["type"]
    structure = block["structure"]

    header =
      if structure do
        "#{@indent}#{@indent}#{@indent}#{@indent}#{type} #{structure}:"
      else
        "#{@indent}#{@indent}#{@indent}#{@indent}#{type}:"
      end

    activity_lines =
      (block["activities"] || [])
      |> Enum.map(&decompile_activity/1)
      |> Enum.map(&("#{@indent}#{@indent}#{@indent}#{@indent}#{@indent}" <> &1))

    [header] ++ activity_lines
  end

  # =============================================================================
  # Activity Decompilation
  # =============================================================================

  defp decompile_activity(%{"type" => "exercise"} = activity) do
    ref = activity["exercise_ref"]
    prescription = activity["prescription"] || %{}

    parts = [ref]

    # Sets and reps
    parts =
      case {prescription["sets"], prescription["reps"]} do
        {sets, %{"min" => min, "max" => max, "target" => target}}
        when is_integer(sets) ->
          parts ++ ["#{sets}x#{min}..#{max} target #{target}"]

        {sets, %{"min" => min, "max" => max}} when is_integer(sets) ->
          parts ++ ["#{sets}x#{min}..#{max}"]

        {sets, %{"target" => target}} when is_integer(sets) ->
          parts ++ ["#{sets}x#{target}"]

        {sets, reps} when is_integer(sets) and is_integer(reps) ->
          parts ++ ["#{sets}x#{reps}"]

        _ ->
          parts
      end

    # RPE
    parts =
      case activity["target_rpe"] do
        rpe when is_integer(rpe) -> parts ++ ["rpe #{rpe}"]
        _ -> parts
      end

    # RIR
    parts =
      case activity["target_rir"] do
        rir when is_integer(rir) -> parts ++ ["rir #{rir}"]
        _ -> parts
      end

    # Rest
    parts =
      case prescription["rest"] do
        %{"value" => v, "unit" => u} -> parts ++ ["rest #{v} #{u}"]
        _ -> parts
      end

    # Weight
    parts =
      case prescription["weight"] do
        %{"type" => "bodyweight"} -> parts ++ ["weight bodyweight"]
        %{"value" => v, "unit" => u} -> parts ++ ["weight #{v} #{u}"]
        _ -> parts
      end

    Enum.join(parts, " ")
  end

  defp decompile_activity(%{"type" => "cardio"} = activity) do
    modality = activity["modality"]
    prescription = activity["prescription"] || %{}
    cardio_type = prescription["type"] || "continuous"

    lines = ["cardio #{modality} #{cardio_type}:"]

    # Duration
    lines =
      case prescription["duration"] do
        %{"value" => v, "unit" => u} ->
          lines ++ ["  total #{v} #{u}"]

        _ ->
          lines
      end

    # Zone
    lines =
      case prescription["intensity"] do
        %{"zone" => zone} -> lines ++ ["  zone #{zone}"]
        _ -> lines
      end

    # Intervals
    lines =
      case prescription["intervals"] do
        %{"work" => %{"duration" => work}, "rest" => %{"duration" => rest}, "repeat" => reps} ->
          lines ++ ["  #{work}s work / #{rest}s rest x#{reps}"]

        _ ->
          lines
      end

    Enum.join(lines, "\n#{@indent}#{@indent}#{@indent}#{@indent}#{@indent}")
  end

  defp decompile_activity(%{"type" => "nutrition"} = activity) do
    category = activity["category"]
    prescription = activity["prescription"] || %{}

    lines = ["nutrition #{category}:"]

    # Macros
    lines =
      case prescription["macros"] do
        %{} = macros ->
          macro_lines =
            Enum.flat_map(["protein", "carbs", "fat"], fn macro ->
              case macros[macro] do
                %{"min" => min, "max" => max} -> ["  #{macro} #{min}..#{max} g"]
                _ -> []
              end
            end)

          lines ++ macro_lines

        _ ->
          lines
      end

    Enum.join(lines, "\n#{@indent}#{@indent}#{@indent}#{@indent}#{@indent}")
  end

  defp decompile_activity(%{"type" => "meditation"} = activity) do
    category = activity["category"]
    prescription = activity["prescription"] || %{}

    lines = ["meditation #{category}:"]

    lines =
      case prescription["duration"] do
        %{"value" => v, "unit" => u} -> lines ++ ["  duration #{v} #{u}"]
        _ -> lines
      end

    lines =
      case prescription["guided"] do
        true -> lines ++ ["  guided true"]
        false -> lines ++ ["  guided false"]
        _ -> lines
      end

    Enum.join(lines, "\n#{@indent}#{@indent}#{@indent}#{@indent}#{@indent}")
  end

  defp decompile_activity(%{"type" => "recovery"} = activity) do
    category = activity["category"]
    "recovery #{category}"
  end

  defp decompile_activity(%{"type" => "recovery_exercise"} = activity) do
    name = activity["name"]
    hold = activity["hold_seconds"]
    reps = activity["reps"]
    sides = activity["sides"]

    parts = [name]

    parts =
      if hold do
        parts ++ ["#{hold}s"]
      else
        parts
      end

    parts =
      if reps do
        parts ++ ["x#{reps}"]
      else
        parts
      end

    parts =
      if sides do
        parts ++ ["sides #{sides}"]
      else
        parts
      end

    Enum.join(parts, " ")
  end

  defp decompile_activity(%{"type" => "habit"} = activity) do
    category = activity["category"]
    target = activity["target"]
    unit = activity["target_unit"]
    frequency = activity["frequency"]

    lines = ["habit #{category}:"]

    lines =
      if target && unit do
        lines ++ ["  target #{target} #{unit}"]
      else
        lines
      end

    lines =
      if frequency do
        lines ++ ["  frequency #{frequency}"]
      else
        lines
      end

    Enum.join(lines, "\n#{@indent}#{@indent}#{@indent}#{@indent}#{@indent}")
  end

  defp decompile_activity(%{"type" => "simple", "name" => name} = activity) do
    case activity["duration"] do
      %{"value" => v, "unit" => "minutes"} -> "#{name} #{v}m"
      %{"value" => v, "unit" => "seconds"} -> "#{name} #{v}s"
      %{"value" => v, "unit" => u} -> "#{name} #{v} #{u}"
      _ -> name
    end
  end

  defp decompile_activity(%{"name" => name}), do: name
  defp decompile_activity(_), do: "unknown_activity"

  # =============================================================================
  # Progress Decompilation
  # =============================================================================

  defp decompile_progress(progress) do
    lines = ["PROGRESS"]

    # Checkpoints
    lines =
      case progress["checkpoints"] do
        checkpoints when is_list(checkpoints) and checkpoints != [] ->
          checkpoint_lines = Enum.flat_map(checkpoints, &decompile_checkpoint/1)
          lines ++ ["#{@indent}CHECKPOINTS"] ++ checkpoint_lines

        _ ->
          lines
      end

    # Points
    lines =
      case progress["points"] do
        %{"enabled" => true} = points ->
          points_lines = decompile_points(points)
          lines ++ ["#{@indent}POINTS"] ++ points_lines

        _ ->
          lines
      end

    lines
  end

  defp decompile_checkpoint(cp) do
    name = cp["name"]

    trigger =
      case cp["at"] do
        %{"value" => v, "unit" => u} -> " at #{v} #{u}"
        _ -> ""
      end

    ["#{@indent}#{@indent}\"#{name}\"#{trigger}"]
  end

  defp decompile_points(points) do
    rules = points["rules"] || []

    Enum.map(rules, fn %{"event" => event, "points" => pts} ->
      "#{@indent}#{@indent}#{event}: #{pts}"
    end)
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp decompile_duration_inline(%{"value" => v, "unit" => "weeks"}), do: "#{v} weeks"
  defp decompile_duration_inline(%{"value" => v, "unit" => "days"}), do: "#{v} days"
  defp decompile_duration_inline(_), do: "1 weeks"

  defp format_duration_short(nil), do: "30m"
  defp format_duration_short(mins) when is_integer(mins), do: "#{mins}m"
  defp format_duration_short(_), do: "30m"

  defp number_to_day_name(1), do: "Monday"
  defp number_to_day_name(2), do: "Tuesday"
  defp number_to_day_name(3), do: "Wednesday"
  defp number_to_day_name(4), do: "Thursday"
  defp number_to_day_name(5), do: "Friday"
  defp number_to_day_name(6), do: "Saturday"
  defp number_to_day_name(7), do: "Sunday"
  defp number_to_day_name(_), do: "Monday"
end
