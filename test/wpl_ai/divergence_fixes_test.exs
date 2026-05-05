defmodule WplAi.DivergenceFixesTest do
  @moduledoc """
  Tests for the two TS-parity fixes:
    1. metadata.language defaults to "en" when not set in DSL.
    2. Activity display name auto-derived from exercise_ref / modality / category token.
  """

  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Minimal DSL snippets for each test
  # ---------------------------------------------------------------------------

  @minimal_plan """
  PLAN "Test Plan"
  TYPE workout
  VISIBILITY public

  GOALS

  PHASES
    PHASE "Foundation" (1 weeks):
      WEEK 1:
  """

  @exercise_plan """
  PLAN "Exercise Plan"
  TYPE workout
  VISIBILITY public

  GOALS

  PHASES
    PHASE "Training" (1 weeks):
      WEEK 1:
        DAY Monday training:
          main straight_sets:
            push_up 3x8..12
  """

  @cardio_plan """
  PLAN "Cardio Plan"
  TYPE workout
  VISIBILITY public

  GOALS

  PHASES
    PHASE "Cardio" (1 weeks):
      WEEK 1:
        DAY Monday training:
          main:
            cardio running continuous:
              total 30 minutes
  """

  @nutrition_plan """
  PLAN "Nutrition Plan"
  TYPE nutrition
  VISIBILITY public

  GOALS

  PHASES
    PHASE "Bulk" (1 weeks):
      WEEK 1:
        DAY Monday training:
          nutrition:
            nutrition daily_target:
              protein 1.6..2.2 g_per_kg
  """

  # ---------------------------------------------------------------------------
  # Divergence 1 — metadata.language defaults to "en"
  # ---------------------------------------------------------------------------

  describe "metadata.language default" do
    test "minimal plan compiles with metadata.language set to en" do
      assert {:ok, json} = WplAi.to_wpl(@minimal_plan)
      assert json["plan"]["metadata"]["language"] == "en"
    end

    test "explicit language in DSL is preserved" do
      source = """
      PLAN "Spanish Plan"
      TYPE workout
      LANGUAGE es
      VISIBILITY public

      GOALS

      PHASES
        PHASE "Base" (1 weeks):
          WEEK 1:
      """

      assert {:ok, json} = WplAi.to_wpl(source)
      assert json["plan"]["metadata"]["language"] == "es"
    end
  end

  # ---------------------------------------------------------------------------
  # Divergence 2 — auto-derived activity display name
  # ---------------------------------------------------------------------------

  describe "exercise activity auto-derived name" do
    test "push_up exercise_ref produces name Push Up" do
      assert {:ok, json} = WplAi.to_wpl(@exercise_plan)
      activity = first_activity(json)
      assert activity["name"] == "Push Up"
    end

    test "auto-derived name is a fallback when no explicit name in DSL" do
      assert {:ok, json} = WplAi.to_wpl(@exercise_plan)
      activity = first_activity(json)
      # Name comes from exercise_ref "push_up" -> "Push Up"
      assert activity["exercise_ref"] == "push_up"
      assert activity["name"] == "Push Up"
    end
  end

  describe "cardio activity auto-derived name" do
    test "running modality produces name Running" do
      assert {:ok, json} = WplAi.to_wpl(@cardio_plan)
      activity = first_activity(json)
      assert activity["type"] == "cardio"
      assert activity["name"] == "Running"
    end
  end

  describe "nutrition activity auto-derived name" do
    test "daily_target category produces name Daily Target" do
      assert {:ok, json} = WplAi.to_wpl(@nutrition_plan)
      activity = first_activity(json)
      assert activity["type"] == "nutrition"
      assert activity["name"] == "Daily Target"
    end
  end

  describe "acronym handling in auto-derived names" do
    test "hiit modality is uppercased to HIIT" do
      source = """
      PLAN "HIIT Plan"
      TYPE workout
      VISIBILITY public

      GOALS

      PHASES
        PHASE "Training" (1 weeks):
          WEEK 1:
            DAY Monday training:
              main:
                cardio hiit interval:
                  total 20 minutes
                  intervals 40s on 20s off x8
      """

      assert {:ok, json} = WplAi.to_wpl(source)
      activity = first_activity(json)
      assert activity["type"] == "cardio"
      assert activity["name"] == "HIIT"
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp first_activity(json) do
    json
    |> get_in(["plan", "phases"])
    |> List.first()
    |> get_in(["weeks"])
    |> List.first()
    |> get_in(["days"])
    |> List.first()
    |> get_in(["blocks"])
    |> List.first()
    |> get_in(["activities"])
    |> List.first()
  end
end
