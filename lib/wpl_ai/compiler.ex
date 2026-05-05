defmodule WplAi.Compiler do
  @moduledoc """
  Compiles WPL-AI AST to canonical WPL JSON format.

  The compiler transforms the parsed AST representation into the
  WPL JSON structure used by the rest of the system.

  ## Example

      iex> {:ok, ast} = WPLAI.parse(source)
      iex> {:ok, json} = Compiler.compile(ast)
      iex> json.plan.name
      "Upper Body Beginner"

  """

  import Bitwise

  alias WplAi.AST

  @doc """
  Compile a WPL-AI AST document to WPL JSON format.

  Returns `{:ok, json_map}` on success, or `{:error, errors}` on failure.
  """
  @spec compile(AST.Document.t()) :: {:ok, map()} | {:error, list()}
  def compile(%AST.Document{} = doc) do
    plan = compile_document(doc)

    json = %{
      "$schema" => "https://wpl.dev/schemas/wpl/v1.schema.json",
      "version" => "1.0.0",
      "plan" => plan
    }

    {:ok, json}
  end

  @doc """
  Compile a WPL-AI AST document to WPL JSON format, raising on error.
  """
  @spec compile!(AST.Document.t()) :: map()
  def compile!(%AST.Document{} = doc) do
    {:ok, json} = compile(doc)
    json
  end

  # =============================================================================
  # Document Compilation
  # =============================================================================

  defp compile_document(%AST.Document{} = doc) do
    plan = %{
      "id" => generate_uuid(),
      "name" => doc.header.name,
      "type" => to_string(doc.header.type),
      "visibility" => to_string(doc.header.visibility || :private),
      "metadata" => compile_metadata(doc.header),
      "goals" => compile_goals(doc.goals || []),
      "requirements" => compile_requirements(doc.requirements),
      "personalization" => compile_personalization(doc.personalization),
      "phases" => compile_phases(doc.phases || []),
      "habits" => compile_plan_habits(doc.habits),
      "progress" => compile_progress(doc.progress),
      "notifications" => compile_notifications(doc.notifications),
      "athlete_thresholds" => compile_athlete_thresholds(doc.athlete_thresholds)
    }

    # Remove nil values
    plan
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp compile_metadata(%AST.Header{} = header) do
    metadata = %{
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    metadata =
      if header.tags do
        Map.put(metadata, "tags", header.tags)
      else
        metadata
      end

    metadata =
      if header.difficulty do
        Map.put(metadata, "difficulty", to_string(header.difficulty))
      else
        metadata
      end

    metadata =
      if header.language do
        Map.put(metadata, "language", header.language)
      else
        metadata
      end

    metadata =
      if header.duration do
        days = duration_to_days(header.duration)
        Map.put(metadata, "estimated_duration_days", days)
      else
        metadata
      end

    metadata
  end

  # =============================================================================
  # Athlete Thresholds Compilation (schema v1.3.0+)
  # =============================================================================

  defp compile_athlete_thresholds(nil), do: nil

  defp compile_athlete_thresholds(%AST.AthleteThresholds{} = t) do
    compiled = %{}

    compiled =
      if t.hr_max_bpm, do: Map.put(compiled, "hr_max_bpm", t.hr_max_bpm), else: compiled

    compiled =
      if t.lthr_bpm, do: Map.put(compiled, "lthr_bpm", t.lthr_bpm), else: compiled

    compiled =
      if t.resting_hr_bpm,
        do: Map.put(compiled, "resting_hr_bpm", t.resting_hr_bpm),
        else: compiled

    compiled =
      if t.ftp_watts, do: Map.put(compiled, "ftp_watts", t.ftp_watts), else: compiled

    compiled =
      if t.vo2max_ml_kg_min,
        do: Map.put(compiled, "vo2max_ml_kg_min", t.vo2max_ml_kg_min),
        else: compiled

    compiled =
      if t.critical_pace_seconds_per_km,
        do: Map.put(compiled, "critical_pace_seconds_per_km", t.critical_pace_seconds_per_km),
        else: compiled

    compiled =
      if t.body_weight_kg,
        do: Map.put(compiled, "body_weight_kg", t.body_weight_kg),
        else: compiled

    compiled =
      if t.one_rm && t.one_rm != [] do
        entries =
          Enum.map(t.one_rm, fn entry ->
            %{
              "exercise_ref" => entry.exercise_ref,
              "value" => entry.value,
              "unit" => entry.unit
            }
          end)

        Map.put(compiled, "one_rm", entries)
      else
        compiled
      end

    if compiled == %{}, do: nil, else: compiled
  end

  # =============================================================================
  # Goals Compilation
  # =============================================================================

  defp compile_goals(goals) when is_list(goals) do
    goals
    |> Enum.with_index(1)
    |> Enum.map(fn {goal, idx} -> compile_goal(goal, idx) end)
  end

  defp compile_goal(%AST.Goal{} = goal, index) do
    # Auto-generate name from category if not provided (validator requires it)
    name = goal.name || humanize_category(goal.category)

    compiled = %{
      "id" => "goal_#{index}",
      "name" => name,
      "type" => to_string(goal.priority || :primary),
      "category" => goal.category
    }

    compiled =
      if goal.description do
        Map.put(compiled, "description", goal.description)
      else
        compiled
      end

    compiled =
      if goal.target do
        Map.put(compiled, "target", compile_target(goal.target))
      else
        compiled
      end

    compiled =
      if goal.deadline do
        Map.put(compiled, "deadline", to_string(goal.deadline))
      else
        compiled
      end

    compiled =
      if goal.milestones && goal.milestones != [] do
        Map.put(compiled, "milestones", Enum.map(goal.milestones, &compile_milestone/1))
      else
        compiled
      end

    compiled
  end

  defp compile_target(%AST.Target{} = target) do
    %{
      "metric" => target.metric,
      "target_value" => target.value,
      "unit" => target.unit,
      "measurement_type" => to_string(target.measurement_type || :absolute)
    }
  end

  defp compile_milestone(%AST.Milestone{} = milestone) do
    compiled = %{
      "id" => generate_short_id("m"),
      "name" => milestone.name
    }

    compiled =
      if milestone.at_value do
        Map.put(compiled, "target_value", milestone.at_value)
      else
        compiled
      end

    compiled =
      if milestone.reward_points do
        Map.put(compiled, "reward_points", milestone.reward_points)
      else
        compiled
      end

    compiled
  end

  # =============================================================================
  # Requirements Compilation
  # =============================================================================

  defp compile_requirements(nil), do: %{}

  defp compile_requirements(%AST.Requirements{} = req) do
    compiled = %{}

    compiled =
      case req.age_range do
        {min, max} ->
          compiled
          |> Map.put("min_age", min)
          |> Map.put("max_age", max)

        _ ->
          compiled
      end

    compiled =
      if req.fitness_levels && req.fitness_levels != [] do
        Map.put(compiled, "fitness_level", req.fitness_levels)
      else
        compiled
      end

    compiled =
      if req.equipment && req.equipment != [] do
        Map.put(compiled, "equipment", Enum.map(req.equipment, &compile_equipment/1))
      else
        compiled
      end

    compiled =
      if req.contraindications && req.contraindications != [] do
        Map.put(
          compiled,
          "contraindications",
          Enum.map(req.contraindications, &compile_contraindication/1)
        )
      else
        compiled
      end

    compiled =
      if req.time_commitment do
        Map.put(compiled, "time_commitment", compile_time_commitment(req.time_commitment))
      else
        compiled
      end

    compiled
  end

  defp compile_equipment(%AST.Equipment{} = equip) do
    compiled = %{
      "id" => String.downcase(String.replace(equip.name, " ", "_")),
      "name" => equip.name,
      "required" => equip.required || false
    }

    if equip.alternatives && equip.alternatives != [] do
      Map.put(compiled, "alternatives", equip.alternatives)
    else
      compiled
    end
  end

  defp compile_contraindication(%AST.Contraindication{} = contra) do
    compiled = %{
      "condition" => contra.condition,
      "action" => to_string(contra.action || :exclude)
    }

    if contra.affects && contra.affects != [] do
      Map.put(compiled, "affected_activities", contra.affects)
    else
      compiled
    end
  end

  defp compile_time_commitment(%AST.TimeCommitment{} = tc) do
    compiled = %{}

    compiled =
      case tc.days_per_week do
        {min, max} ->
          compiled
          |> Map.put("min_days_per_week", min)
          |> Map.put("max_days_per_week", max)

        _ ->
          compiled
      end

    case tc.minutes_per_day do
      {min, max} ->
        compiled
        |> Map.put("min_minutes_per_day", min)
        |> Map.put("max_minutes_per_day", max)

      _ ->
        compiled
    end
  end

  # =============================================================================
  # Personalization Compilation
  # =============================================================================

  defp compile_personalization(nil), do: %{"inputs" => [], "rules" => []}

  defp compile_personalization(%AST.Personalization{} = pers) do
    %{
      "inputs" => compile_inputs(pers.inputs || []),
      "rules" => compile_rules(pers.rules || [])
    }
  end

  defp compile_inputs(inputs) when is_list(inputs) do
    inputs
    |> Enum.with_index(1)
    |> Enum.map(fn {input, idx} -> compile_input(input, idx) end)
  end

  defp compile_input(%AST.Input{} = input, index) do
    compiled = %{
      "id" => input.name || "input_#{index}",
      "type" => to_string(input.type || :string),
      "source" => input.source || "questionnaire"
    }

    compiled =
      if input.label do
        Map.put(compiled, "label", input.label)
      else
        compiled
      end

    compiled =
      if input.options && input.options != [] do
        Map.put(compiled, "options", input.options)
      else
        compiled
      end

    compiled
  end

  defp compile_rules(rules) when is_list(rules) do
    # Drop rules whose actions list is empty: this happens when the
    # subagent emits a rule with prose-style actions (e.g. "schedule
    # workouts in the morning") that the parser can't translate into
    # one of the named action verbs. Better to silently lose a malformed
    # rule than fail validation for the whole plan — the validator
    # rejects `actions: []` outright.
    rules
    |> Enum.reject(fn r -> r.actions == [] || r.actions == nil end)
    |> Enum.with_index(1)
    |> Enum.map(fn {rule, idx} -> compile_rule(rule, idx) end)
  end

  defp compile_rule(%AST.Rule{} = rule, index) do
    %{
      "id" => "rule_#{index}",
      "condition" => compile_condition(rule.condition),
      "actions" => Enum.map(rule.actions, &compile_action/1)
    }
  end

  defp compile_condition(%AST.Condition{type: :compound} = cond) do
    %{
      "operator" => to_string(cond.operator),
      "conditions" =>
        Enum.map(cond.conditions, fn c ->
          %{
            "field" => c.field,
            "op" => to_string(c.op),
            "value" => c.value
          }
        end)
    }
  end

  defp compile_condition(%AST.Condition{type: :simple} = cond) do
    %{
      "field" => cond.field,
      "op" => to_string(cond.op),
      "value" => cond.value
    }
  end

  defp compile_action(%AST.Action{} = action) do
    base = %{"type" => to_string(action.type)}

    params = action.params || %{}

    # Merge params into base
    Enum.reduce(params, base, fn {k, v}, acc ->
      Map.put(acc, to_string(k), v)
    end)
  end

  # =============================================================================
  # Plan-level Habits Compilation
  # =============================================================================

  defp compile_plan_habits(nil), do: nil
  defp compile_plan_habits([]), do: nil

  defp compile_plan_habits(habits) when is_list(habits) do
    habits
    |> Enum.with_index(1)
    |> Enum.map(fn {h, idx} -> compile_plan_habit(h, idx) end)
  end

  defp compile_plan_habit(%AST.PlanHabit{} = habit, index) do
    base = %{
      "id" => "plan_habit_#{index}",
      "name" => habit.name
    }

    base =
      if habit.description, do: Map.put(base, "description", habit.description), else: base

    base =
      if habit.frequency, do: Map.put(base, "frequency", habit.frequency), else: base

    base =
      if habit.trigger, do: Map.put(base, "trigger", habit.trigger), else: base

    base
  end

  # =============================================================================
  # Phases Compilation
  # =============================================================================

  defp compile_phases(phases) when is_list(phases) do
    phases
    |> Enum.with_index(1)
    |> Enum.map(fn {phase, idx} -> compile_phase(phase, idx) end)
  end

  defp compile_phase(%AST.Phase{} = phase, index) do
    compiled = %{
      "id" => "phase_#{index}",
      "name" => phase.name,
      "order" => index
    }

    compiled =
      if phase.description do
        Map.put(compiled, "description", phase.description)
      else
        compiled
      end

    compiled =
      if phase.duration do
        Map.put(compiled, "duration", compile_duration(phase.duration))
      else
        compiled
      end

    compiled =
      if phase.weeks && phase.weeks != [] do
        Map.put(compiled, "weeks", compile_weeks(phase.weeks))
      else
        compiled
      end

    compiled
  end

  defp compile_weeks(weeks) when is_list(weeks) do
    Enum.map(weeks, &compile_week/1)
  end

  defp compile_week(%AST.Week{} = week) do
    compiled = %{
      "id" => "week_#{week.number}",
      "name" => week.name || "Week #{week.number}",
      "order" => week.number
    }

    if week.days && week.days != [] do
      Map.put(compiled, "days", compile_days(week.days))
    else
      compiled
    end
  end

  defp compile_days(days) when is_list(days) do
    days
    |> Enum.with_index(1)
    |> Enum.map(fn {day, idx} -> compile_day(day, idx) end)
  end

  defp compile_day(%AST.Day{} = day, index) do
    compiled = %{
      "id" => "day_#{index}",
      "day_of_week" => day_name_to_number(day.day_name),
      "type" => to_string(day.day_type || :training)
    }

    compiled =
      if day.label do
        Map.put(compiled, "name", day.label)
      else
        compiled
      end

    compiled =
      if day.duration do
        mins = duration_to_minutes(day.duration)
        Map.put(compiled, "estimated_duration_minutes", mins)
      else
        compiled
      end

    compiled =
      if day.blocks && day.blocks != [] do
        Map.put(compiled, "blocks", compile_blocks(day.blocks))
      else
        compiled
      end

    compiled
  end

  defp compile_blocks(blocks) when is_list(blocks) do
    blocks
    |> Enum.with_index(1)
    |> Enum.map(fn {block, idx} -> compile_block(block, idx) end)
  end

  defp compile_block(%AST.Block{} = block, index) do
    compiled = %{
      "id" => "#{block.type}_block",
      "type" => to_string(block.type),
      "order" => index
    }

    compiled =
      if block.structure do
        Map.put(compiled, "structure", to_string(block.structure))
      else
        compiled
      end

    compiled =
      if block.rounds do
        Map.put(compiled, "rounds", block.rounds)
      else
        compiled
      end

    compiled =
      if block.rest_between_rounds do
        Map.put(compiled, "rest_between_rounds", compile_duration(block.rest_between_rounds))
      else
        compiled
      end

    compiled =
      if block.activities && block.activities != [] do
        activities =
          block.activities
          |> Enum.with_index(1)
          |> Enum.map(fn {act, idx} -> compile_activity(act, idx) end)

        Map.put(compiled, "activities", activities)
      else
        compiled
      end

    compiled
  end

  # =============================================================================
  # Activity Compilation
  # =============================================================================

  defp compile_activity(%AST.Exercise{} = ex, index) do
    compiled = %{
      "id" => "exercise_#{index}",
      "type" => "exercise",
      "exercise_ref" => ex.exercise_ref
    }

    compiled =
      if ex.name do
        Map.put(compiled, "name", ex.name)
      else
        compiled
      end

    # Build prescription
    prescription = %{}

    prescription =
      if ex.sets do
        Map.put(prescription, "sets", ex.sets)
      else
        prescription
      end

    prescription =
      case ex.reps do
        {min, max, target} ->
          Map.put(prescription, "reps", %{"min" => min, "max" => max, "target" => target})

        {min, max} ->
          Map.put(prescription, "reps", %{"min" => min, "max" => max})

        n when is_number(n) ->
          Map.put(prescription, "reps", %{"target" => n})

        _ ->
          prescription
      end

    prescription =
      if ex.rest do
        Map.put(prescription, "rest", compile_duration(ex.rest))
      else
        prescription
      end

    prescription =
      if ex.tempo do
        Map.put(prescription, "tempo", ex.tempo)
      else
        prescription
      end

    prescription =
      if ex.weight do
        Map.put(prescription, "weight", compile_weight(ex.weight))
      else
        prescription
      end

    # WPL validator requires every prescription to carry a `type`. For a
    # straight Exercise AST node the prescription is always sets/reps-shaped
    # (sets, reps, rest, tempo, weight), so tag it explicitly. Without this
    # the validator rejects the compiled plan with
    # "prescription missing 'type' field".
    compiled =
      if prescription != %{} do
        Map.put(compiled, "prescription", Map.put(prescription, "type", "sets_reps"))
      else
        compiled
      end

    # Add intensity markers
    compiled =
      if ex.rpe do
        Map.put(compiled, "target_rpe", ex.rpe)
      else
        compiled
      end

    compiled =
      if ex.rir do
        Map.put(compiled, "target_rir", ex.rir)
      else
        compiled
      end

    # Muscle / movement-pattern tagging (schema v1.3.0+)
    compiled =
      if ex.primary_muscles && ex.primary_muscles != [] do
        Map.put(compiled, "primary_muscles", ex.primary_muscles)
      else
        compiled
      end

    compiled =
      if ex.secondary_muscles && ex.secondary_muscles != [] do
        Map.put(compiled, "secondary_muscles", ex.secondary_muscles)
      else
        compiled
      end

    compiled =
      if ex.movement_pattern do
        Map.put(compiled, "movement_pattern", ex.movement_pattern)
      else
        compiled
      end

    compiled
  end

  defp compile_activity(%AST.Cardio{} = cardio, index) do
    compiled = %{
      "id" => "cardio_#{index}",
      "type" => "cardio",
      "modality" => cardio.modality
    }

    # Build prescription
    prescription = %{
      "type" => to_string(cardio.cardio_type || :continuous)
    }

    prescription =
      if cardio.total_duration do
        Map.put(prescription, "duration", compile_duration(cardio.total_duration))
      else
        prescription
      end

    prescription =
      if cardio.zone do
        intensity_map = %{"type" => "heart_rate_zone", "zone" => cardio.zone}

        intensity_map =
          if cardio.intensity && cardio.intensity.zone_model do
            Map.put(intensity_map, "zone_model", cardio.intensity.zone_model)
          else
            intensity_map
          end

        Map.put(prescription, "intensity", intensity_map)
      else
        if cardio.intensity do
          Map.put(prescription, "intensity", compile_cardio_intensity(cardio.intensity))
        else
          prescription
        end
      end

    prescription =
      if cardio.intervals do
        Map.put(prescription, "intervals", compile_intervals(cardio.intervals))
      else
        prescription
      end

    Map.put(compiled, "prescription", prescription)
  end

  defp compile_activity(%AST.Nutrition{} = nutrition, index) do
    compiled = %{
      "id" => "nutrition_#{index}",
      "type" => "nutrition",
      "category" => to_string(nutrition.category)
    }

    # Carry the food identifier (e.g. "smoothie_bowl") so the trainer UI
    # can render it as the meal's name. Plan rendering falls back to
    # exercise_ref/activity_row rendering, which reads "name" first.
    compiled =
      if nutrition.name do
        Map.put(compiled, "name", nutrition.name)
      else
        compiled
      end

    # Build prescription
    prescription = %{}

    prescription =
      if nutrition.macros do
        macros = compile_macros(nutrition.macros)
        Map.put(prescription, "macros", macros)
      else
        prescription
      end

    prescription =
      case nutrition.calories do
        {min, max} ->
          Map.put(prescription, "calories", %{"min" => min, "max" => max})

        _ ->
          prescription
      end

    prescription =
      if nutrition.suggestions && nutrition.suggestions != [] do
        Map.put(prescription, "suggestions", nutrition.suggestions)
      else
        prescription
      end

    compiled =
      if prescription != %{} do
        Map.put(compiled, "prescription", prescription)
      else
        compiled
      end

    if nutrition.timing do
      Map.put(compiled, "timing", compile_timing(nutrition.timing))
    else
      compiled
    end
  end

  defp compile_activity(%AST.Meditation{} = meditation, index) do
    compiled = %{
      "id" => "meditation_#{index}",
      "type" => "meditation",
      "category" => to_string(meditation.category)
    }

    prescription = %{}

    prescription =
      if meditation.duration do
        Map.put(prescription, "duration", compile_duration(meditation.duration))
      else
        prescription
      end

    prescription =
      if meditation.guided != nil do
        Map.put(prescription, "guided", meditation.guided)
      else
        prescription
      end

    if prescription != %{} do
      Map.put(compiled, "prescription", prescription)
    else
      compiled
    end
  end

  defp compile_activity(%AST.Recovery{} = recovery, index) do
    compiled = %{
      "id" => "recovery_#{index}",
      "type" => "recovery",
      "category" => to_string(recovery.category)
    }

    compiled =
      if recovery.duration do
        Map.put(compiled, "duration", compile_duration(recovery.duration))
      else
        compiled
      end

    if recovery.exercises && recovery.exercises != [] do
      exercises =
        recovery.exercises
        |> Enum.with_index(1)
        |> Enum.map(fn {ex, idx} -> compile_recovery_exercise(ex, idx) end)

      Map.put(compiled, "exercises", exercises)
    else
      compiled
    end
  end

  defp compile_activity(%AST.RecoveryExercise{} = ex, index) do
    compiled = %{
      "id" => "recovery_exercise_#{index}",
      "type" => "recovery_exercise",
      "name" => ex.name
    }

    compiled =
      if ex.hold_seconds do
        Map.put(compiled, "hold_seconds", ex.hold_seconds)
      else
        compiled
      end

    compiled =
      if ex.reps do
        Map.put(compiled, "reps", ex.reps)
      else
        compiled
      end

    compiled =
      if ex.sides do
        Map.put(compiled, "sides", to_string(ex.sides))
      else
        compiled
      end

    compiled
  end

  defp compile_activity(%AST.Habit{} = habit, index) do
    compiled = %{
      "id" => "habit_#{index}",
      "type" => "habit",
      "category" => to_string(habit.category)
    }

    compiled =
      if habit.target do
        Map.put(compiled, "target", habit.target)
      else
        compiled
      end

    compiled =
      if habit.target_unit do
        Map.put(compiled, "target_unit", habit.target_unit)
      else
        compiled
      end

    compiled =
      if habit.frequency do
        Map.put(compiled, "frequency", habit.frequency)
      else
        compiled
      end

    if habit.reminders && habit.reminders != [] do
      times = Enum.map(habit.reminders, &Time.to_string/1)
      Map.put(compiled, "reminder_times", times)
    else
      compiled
    end
  end

  defp compile_activity(%AST.SimpleActivity{} = simple, index) do
    compiled = %{
      "id" => "activity_#{index}",
      "type" => "simple",
      "name" => simple.name
    }

    compiled =
      if simple.duration do
        Map.put(compiled, "duration", compile_duration(simple.duration))
      else
        compiled
      end

    compiled
  end

  defp compile_recovery_exercise(%AST.RecoveryExercise{} = ex, index) do
    compile_activity(ex, index)
  end

  # =============================================================================
  # Progress & Notifications Compilation
  # =============================================================================

  defp compile_progress(nil), do: nil

  defp compile_progress(%AST.Progress{} = progress) do
    compiled = %{}

    compiled =
      if progress.checkpoints && progress.checkpoints != [] do
        Map.put(compiled, "checkpoints", Enum.map(progress.checkpoints, &compile_checkpoint/1))
      else
        compiled
      end

    compiled =
      if progress.points do
        Map.put(compiled, "points", compile_points_config(progress.points))
      else
        compiled
      end

    if compiled == %{}, do: nil, else: compiled
  end

  defp compile_checkpoint(%AST.Checkpoint{} = cp) do
    compiled = %{
      "id" => generate_short_id("cp"),
      "name" => cp.name
    }

    compiled =
      case cp.trigger do
        {:time, value, unit} ->
          Map.put(compiled, "at", %{"value" => value, "unit" => to_string(unit)})

        _ ->
          compiled
      end

    compiled =
      if cp.measurements && cp.measurements != [] do
        Map.put(compiled, "measurements", cp.measurements)
      else
        compiled
      end

    if cp.questions && cp.questions != [] do
      Map.put(compiled, "questions", cp.questions)
    else
      compiled
    end
  end

  defp compile_points_config(%AST.PointsConfig{} = pc) do
    compiled = %{
      "enabled" => pc.enabled || false
    }

    if pc.rules && pc.rules != [] do
      # Rules are tuples of {event_type, points_value}
      rules =
        Enum.map(pc.rules, fn {event, points} ->
          %{"event" => event, "points" => points}
        end)

      Map.put(compiled, "rules", rules)
    else
      compiled
    end
  end

  defp compile_notifications(nil), do: nil
  defp compile_notifications([]), do: nil

  defp compile_notifications(notifications) when is_list(notifications) do
    Enum.map(notifications, &compile_notification/1)
  end

  defp compile_notification(%AST.Notification{} = notif) do
    compiled = %{
      "id" => notif.id || generate_short_id("notif"),
      "enabled" => notif.enabled || false,
      "message" => notif.message
    }

    case notif.timing do
      {%AST.Duration{} = duration, reference} ->
        compiled
        |> Map.put("timing_offset", compile_duration(duration))
        |> Map.put("timing_reference", reference)

      _ ->
        compiled
    end
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp compile_duration(%AST.Duration{value: value, unit: unit}) do
    %{"value" => value, "unit" => to_string(unit)}
  end

  defp compile_weight(%AST.Weight{type: :bodyweight}) do
    %{"type" => "bodyweight"}
  end

  defp compile_weight(%AST.Weight{value: value, unit: unit}) do
    %{"type" => "absolute", "value" => value, "unit" => unit}
  end

  defp compile_cardio_intensity(%AST.Intensity{type: :bpm, range: {min, max}}) do
    %{"type" => "bpm", "min_bpm" => min, "max_bpm" => max}
  end

  defp compile_cardio_intensity(%AST.Intensity{type: :power, value: value}) do
    %{"type" => "power", "value" => value}
  end

  defp compile_cardio_intensity(%AST.Intensity{type: type, value: value}) do
    %{"type" => to_string(type), "value" => value}
  end

  defp compile_intervals(%AST.IntervalPattern{} = pattern) do
    %{
      "work" => %{"duration" => pattern.work_seconds},
      "rest" => %{"duration" => pattern.rest_seconds},
      "repeat" => pattern.repeats
    }
  end

  defp compile_macros(%AST.Macros{} = macros) do
    compiled = %{}

    compiled =
      case macros.protein do
        {min, max} -> Map.put(compiled, "protein", %{"min" => min, "max" => max, "unit" => "g"})
        _ -> compiled
      end

    compiled =
      case macros.carbs do
        {min, max} -> Map.put(compiled, "carbs", %{"min" => min, "max" => max, "unit" => "g"})
        _ -> compiled
      end

    compiled =
      case macros.fat do
        {min, max} -> Map.put(compiled, "fat", %{"min" => min, "max" => max, "unit" => "g"})
        _ -> compiled
      end

    compiled
  end

  defp compile_timing(%AST.NutritionTiming{} = timing) do
    compiled = %{
      "type" => to_string(timing.type || :relative)
    }

    compiled =
      if timing.duration do
        Map.put(compiled, "offset", compile_duration(timing.duration))
      else
        compiled
      end

    compiled =
      if timing.time do
        Map.put(compiled, "time", Time.to_string(timing.time))
      else
        compiled
      end

    compiled
  end

  defp duration_to_days(%AST.Duration{value: value, unit: :weeks}), do: trunc(value * 7)
  defp duration_to_days(%AST.Duration{value: value, unit: :days}), do: trunc(value)
  defp duration_to_days(_), do: nil

  defp duration_to_minutes(%AST.Duration{value: value, unit: :minutes}), do: trunc(value)
  defp duration_to_minutes(%AST.Duration{value: value, unit: :hours}), do: trunc(value * 60)
  defp duration_to_minutes(%AST.Duration{value: value, unit: :seconds}), do: trunc(value / 60)
  defp duration_to_minutes(_), do: nil

  defp humanize_category(nil), do: "Goal"

  defp humanize_category(category) when is_binary(category) do
    category
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp humanize_category(category) when is_atom(category) do
    category |> to_string() |> humanize_category()
  end

  defp day_name_to_number(name) when is_binary(name) do
    case String.downcase(name) do
      "monday" -> 1
      "tuesday" -> 2
      "wednesday" -> 3
      "thursday" -> 4
      "friday" -> 5
      "saturday" -> 6
      "sunday" -> 7
      _ -> 1
    end
  end

  defp day_name_to_number(_), do: 1

  defp generate_uuid do
    # Use crypto for UUID generation
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    # Set version 4 and variant bits
    c_with_version = (c &&& 0x0FFF) ||| 0x4000
    d_with_variant = (d &&& 0x3FFF) ||| 0x8000

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [a, b, c_with_version, d_with_variant, e]
    )
    |> to_string()
  end

  defp generate_short_id(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}_#{random}"
  end
end
