defmodule WplAi.BugFixesTest do
  @moduledoc """
  Unit tests pinning the desired behavior for the 7 corpus-surfaced bugs.
  Each test is written to fail before the fix and pass after.
  """

  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp compile_plan(source) do
    {:ok, result, _repairs} = WplAi.to_wpl(source)
    result
  end

  defp get_activity(source) do
    plan = compile_plan(source)

    plan["plan"]["phases"]
    |> hd()
    |> Map.get("weeks")
    |> hd()
    |> Map.get("days")
    |> hd()
    |> Map.get("blocks")
    |> hd()
    |> Map.get("activities")
    |> hd()
  end

  defp get_activities(source) do
    plan = compile_plan(source)

    plan["plan"]["phases"]
    |> hd()
    |> Map.get("weeks")
    |> hd()
    |> Map.get("days")
    |> hd()
    |> Map.get("blocks")
    |> hd()
    |> Map.get("activities")
  end

  # Build a minimal workout plan DSL string with a single exercise line.
  # Uses 2-space indentation throughout (the only unit accepted by the lexer
  # when it is first established at the PHASES level).
  defp exercise_source(exercise_line) do
    "PLAN \"Test Plan\"\n" <>
      "TYPE workout\n" <>
      "VISIBILITY public\n" <>
      "\n" <>
      "PHASES\n" <>
      "  PHASE \"Phase 1\" (1 weeks):\n" <>
      "    WEEK 1:\n" <>
      "      DAY Monday training:\n" <>
      "        main straight_sets:\n" <>
      "          " <> exercise_line <> "\n"
  end

  # Build a minimal nutrition plan DSL with a single nutrition activity.
  # `nutrition_body` is the indented content under `nutrition <category>:`
  # (must already contain the correct leading spaces).
  defp nutrition_source(category, nutrition_body) do
    "PLAN \"Nutrition Plan\"\n" <>
      "TYPE nutrition\n" <>
      "VISIBILITY public\n" <>
      "\n" <>
      "PHASES\n" <>
      "  PHASE \"Phase 1\" (1 weeks):\n" <>
      "    WEEK 1:\n" <>
      "      DAY Monday training:\n" <>
      "        nutrition:\n" <>
      "          nutrition " <>
      category <>
      ":\n" <>
      nutrition_body
  end

  # Build a minimal workout plan DSL string with a single habit activity.
  defp habit_source(category, habit_body) do
    "PLAN \"Habit Plan\"\n" <>
      "TYPE workout\n" <>
      "VISIBILITY public\n" <>
      "\n" <>
      "PHASES\n" <>
      "  PHASE \"Phase 1\" (1 weeks):\n" <>
      "    WEEK 1:\n" <>
      "      DAY Monday training:\n" <>
      "        main:\n" <>
      "          habit " <>
      category <>
      ":\n" <>
      habit_body
  end

  # ---------------------------------------------------------------------------
  # Bug 1 — tempo field emitted as structured object (not raw string)
  # ---------------------------------------------------------------------------

  describe "Bug 1 — tempo structured emit" do
    test "dashed tempo 3-1-1-0 emits structured object" do
      activity = get_activity(exercise_source("bench_press 3x8 tempo 3 - 1 - 1 - 0"))
      tempo = activity["prescription"]["tempo"]

      assert is_map(tempo), "expected tempo to be a map, got: #{inspect(tempo)}"
      assert tempo["eccentric"] == 3
      assert tempo["pause_bottom"] == 1
      assert tempo["concentric"] == 1
      assert tempo["pause_top"] == 0
    end

    test "dashed tempo 4-0-1-0 emits structured object" do
      activity = get_activity(exercise_source("squat 4x6 tempo 4 - 0 - 1 - 0"))
      tempo = activity["prescription"]["tempo"]

      assert is_map(tempo)
      assert tempo["eccentric"] == 4
      assert tempo["pause_bottom"] == 0
      assert tempo["concentric"] == 1
      assert tempo["pause_top"] == 0
    end

    test "tempo with X sets explosive_concentric: true and concentric: 0" do
      activity = get_activity(exercise_source("bench_press 3x8 tempo 3 - 0 - X - 1"))
      tempo = activity["prescription"]["tempo"]

      assert is_map(tempo)
      assert tempo["eccentric"] == 3
      assert tempo["pause_bottom"] == 0
      assert tempo["concentric"] == 0
      assert tempo["pause_top"] == 1
      assert tempo["explosive_concentric"] == true
    end

    test "tempo does not emit explosive_concentric when not present" do
      activity = get_activity(exercise_source("bench_press 3x8 tempo 3 - 1 - 1 - 0"))
      tempo = activity["prescription"]["tempo"]

      refute Map.has_key?(tempo, "explosive_concentric")
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 2 — weight N% bw emits unit: "bw" (not "%")
  # ---------------------------------------------------------------------------

  describe "Bug 2 — weight percentage_bodyweight unit" do
    test "weight 50% bw emits unit: bw" do
      activity = get_activity(exercise_source("pull_up 3x8 weight 50% bw"))
      weight = activity["prescription"]["weight"]

      assert weight["type"] == "percentage_bodyweight"
      assert weight["value"] == 50
      assert weight["unit"] == "bw"
    end

    test "weight 75% bodyweight emits unit: bw" do
      activity = get_activity(exercise_source("pull_up 3x6 weight 75% bodyweight"))
      weight = activity["prescription"]["weight"]

      assert weight["type"] == "percentage_bodyweight"
      assert weight["unit"] == "bw"
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 3 — Calories unit "kcal" is omitted (default), non-defaults emitted
  # ---------------------------------------------------------------------------

  describe "Bug 3 — calories kcal default omitted" do
    test "calories with default kcal does not emit unit field" do
      body = "            calories 1800..2200\n"
      activity = get_activity(nutrition_source("daily_target", body))
      calories = activity["prescription"]["calories"]

      refute Map.has_key?(calories, "unit"),
             "unit should be omitted for default kcal, got: #{inspect(calories)}"

      assert calories["min"] == 1800
      assert calories["max"] == 2200
    end

    test "calories with explicit kcal does not emit unit field" do
      body = "            calories 1800..2200 kcal\n"
      activity = get_activity(nutrition_source("daily_target", body))
      calories = activity["prescription"]["calories"]

      refute Map.has_key?(calories, "unit"),
             "unit should be omitted for explicit kcal, got: #{inspect(calories)}"
    end

    test "calories with kcal_per_kg does emit unit" do
      body = "            calories 30..35 kcal_per_kg\n"
      activity = get_activity(nutrition_source("daily_target", body))
      calories = activity["prescription"]["calories"]

      assert calories["unit"] == "kcal_per_kg"
    end

    test "calories with multiplier_of_tdee does emit unit" do
      body = "            calories 1.0..1.2 multiplier_of_tdee\n"
      activity = get_activity(nutrition_source("daily_target", body))
      calories = activity["prescription"]["calories"]

      assert calories["unit"] == "multiplier_of_tdee"
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 4 — Nutrition timing absolute: type "absolute", time "HH:MM"
  # ---------------------------------------------------------------------------

  describe "Bug 4 — nutrition timing absolute type and time format" do
    test "at 07:30 emits type: absolute" do
      body = "            timing at 07:30\n            protein 30..50 g\n"
      activity = get_activity(nutrition_source("breakfast", body))
      timing = activity["timing"]

      assert timing["type"] == "absolute",
             "expected type: absolute, got: #{inspect(timing["type"])}"
    end

    test "at 07:30 emits time without seconds" do
      body = "            timing at 07:30\n            protein 30..50 g\n"
      activity = get_activity(nutrition_source("breakfast", body))
      timing = activity["timing"]

      assert timing["time"] == "07:30",
             "expected time: 07:30, got: #{inspect(timing["time"])}"
    end

    test "at time does not emit offset field" do
      body = "            timing at 07:30\n            protein 30..50 g\n"
      activity = get_activity(nutrition_source("breakfast", body))
      timing = activity["timing"]

      refute Map.has_key?(timing, "offset")
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 5 — Nutrition timing before/after workout doesn't drop body content
  # ---------------------------------------------------------------------------

  describe "Bug 5 — nutrition timing preserves body content" do
    test "before_workout timing preserves protein macro" do
      body = "            timing before_workout - 30 minutes\n            protein 30..50 g\n"
      activity = get_activity(nutrition_source("pre_workout", body))
      timing = activity["timing"]

      assert timing["type"] == "relative"
      assert timing["reference"] == "workout_start"

      prescription = activity["prescription"]

      assert prescription != nil,
             "prescription should not be nil when macros are present"

      macros = prescription["macros"]

      assert macros != nil && Map.has_key?(macros, "protein"),
             "protein macro should be present under prescription.macros, got prescription: #{inspect(prescription)}"
    end

    test "after_workout timing preserves calorie content" do
      body = "            timing after_workout + 30 minutes\n            calories 400..600\n"
      activity = get_activity(nutrition_source("post_workout", body))
      timing = activity["timing"]

      assert timing["type"] == "relative"
      assert timing["reference"] == "workout_end"

      prescription = activity["prescription"]
      assert Map.has_key?(prescription, "calories")
    end

    test "before_workout timing emits reference: workout_start" do
      body = "            timing before_workout - 60 minutes\n            carbs 60..80 g\n"
      activity = get_activity(nutrition_source("pre_workout", body))
      timing = activity["timing"]

      assert timing["reference"] == "workout_start"
    end

    test "after_workout timing emits reference: workout_end" do
      body = "            timing after_workout + 45 minutes\n            protein 25..40 g\n"
      activity = get_activity(nutrition_source("post_workout", body))
      timing = activity["timing"]

      assert timing["reference"] == "workout_end"
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 6 — Habit activity emits nested prescription wrapper
  # ---------------------------------------------------------------------------

  describe "Bug 6 — habit nested prescription" do
    test "habit target is nested under prescription" do
      body = "            target 8 glasses\n            frequency daily\n"
      activity = get_activity(habit_source("hydration", body))

      refute Map.has_key?(activity, "target"),
             "target should NOT be at top level, got: #{inspect(Map.keys(activity))}"

      assert Map.has_key?(activity, "prescription"),
             "prescription key must be present"

      rx = activity["prescription"]
      target = rx["target"]
      assert target != nil, "prescription.target must not be nil"
      assert target["value"] == 8
    end

    test "habit target unit is nested under prescription.target" do
      body = "            target 8 glasses\n"
      activity = get_activity(habit_source("hydration", body))
      rx = activity["prescription"]
      target = rx["target"]

      assert target["unit"] == "glasses"
    end

    test "habit frequency is nested under prescription" do
      body = "            target 8 glasses\n            frequency daily\n"
      activity = get_activity(habit_source("hydration", body))
      rx = activity["prescription"]

      assert rx["frequency"] == "daily",
             "expected prescription.frequency: daily, got: #{inspect(rx)}"

      refute Map.has_key?(activity, "frequency"),
             "frequency should NOT be at top level"
    end

    test "habit reminder_times are nested under prescription" do
      body =
        "            target 8 hours\n            frequency daily\n            reminders 21:00\n"

      activity = get_activity(habit_source("sleep", body))
      rx = activity["prescription"]

      assert Map.has_key?(rx, "reminder_times"),
             "prescription.reminder_times must be present, got: #{inspect(rx)}"

      refute Map.has_key?(activity, "reminder_times"),
             "reminder_times must NOT be at top level"
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 7 — bodyweight keyword attaches as weight: {type: "bodyweight"}
  # ---------------------------------------------------------------------------

  describe "Bug 7 — bodyweight keyword in exercise modifier chain" do
    test "pull_up 3x8 bodyweight emits single activity (not two)" do
      activities = get_activities(exercise_source("pull_up 3x8 bodyweight"))

      assert length(activities) == 1,
             "expected 1 activity, got #{length(activities)}: #{inspect(Enum.map(activities, & &1["type"]))}"
    end

    test "pull_up 3x8 bodyweight emits weight type: bodyweight" do
      activity = get_activity(exercise_source("pull_up 3x8 bodyweight"))
      weight = activity["prescription"]["weight"]

      assert weight != nil, "weight must be present"
      assert weight["type"] == "bodyweight"
    end

    test "pull_up 3x8 bodyweight does not emit value or unit in weight" do
      activity = get_activity(exercise_source("pull_up 3x8 bodyweight"))
      weight = activity["prescription"]["weight"]

      refute Map.has_key?(weight, "value")
      refute Map.has_key?(weight, "unit")
    end

    test "dip 4x6 bodyweight preserves sets and reps" do
      activity = get_activity(exercise_source("dip 4x6 bodyweight"))

      assert activity["prescription"]["sets"] == 4
      assert activity["prescription"]["reps"]["target"] == 6
    end
  end
end
