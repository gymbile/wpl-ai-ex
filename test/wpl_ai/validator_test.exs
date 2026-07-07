defmodule WplAi.ValidatorTest do
  use ExUnit.Case, async: true

  alias WplAi.{AST, Validator}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  @minimal_header ~S"""
  PLAN "Test"
  TYPE workout
  """

  defp parse_and_validate!(source) do
    assert {:ok, doc, _repairs} = WplAi.Parser.parse(source)
    Validator.validate_semantics(doc)
  end

  # Build a minimal Document with a single checkpoint containing the given measurements
  defp doc_with_measurements(measurements) do
    %AST.Document{
      header: %AST.Header{
        name: "Test",
        type: :workout,
        visibility: nil,
        difficulty: nil,
        duration: nil,
        tags: nil,
        language: "en",
        min_app_version: nil,
        schema: nil
      },
      goals: nil,
      requirements: nil,
      personalization: nil,
      athlete_thresholds: nil,
      phases: [],
      progress: %AST.Progress{
        checkpoints: [
          %AST.Checkpoint{
            name: "Week 4",
            trigger: {:time, 4, 1},
            measurements: measurements,
            questions: nil
          }
        ],
        points: nil,
        achievements: nil,
        streaks: nil
      },
      notifications: nil,
      rendering: nil
    }
  end

  # ---------------------------------------------------------------------------
  # DSL-path tests (parser → validator)
  # ---------------------------------------------------------------------------

  describe "MeasurementMetric v1.6.0 — DSL path" do
    test "no warning for typed MeasurementSpec body_weight_kg" do
      source =
        @minimal_header <>
          "\nPROGRESS\n  CHECKPOINT \"Week 4\":\n    at 4 weeks\n    measure:\n      body_weight_kg\n"

      warnings = parse_and_validate!(source)
      metric_warnings = Enum.filter(warnings, &String.contains?(&1.message, "measurement metric"))
      assert metric_warnings == []
    end

    test "no warning for questionnaire_score with valid questionnaire psqi" do
      source =
        @minimal_header <>
          "\nPROGRESS\n  CHECKPOINT \"Week 4\":\n    at 4 weeks\n    measure:\n      questionnaire_score questionnaire psqi\n"

      warnings = parse_and_validate!(source)

      relevant =
        Enum.filter(warnings, fn w ->
          String.contains?(w.message, "measurement metric") or
            String.contains?(w.message, "questionnaire")
        end)

      assert relevant == []
    end

    test "no warning for legacy quoted string 'weight' (back-compat)" do
      source =
        @minimal_header <>
          ~S"""

          PROGRESS
            CHECKPOINT "Week 4":
              at 4 weeks
              measure:
                "weight"
          """

      warnings = parse_and_validate!(source)
      metric_warnings = Enum.filter(warnings, &String.contains?(&1.message, "measurement metric"))
      assert metric_warnings == []
    end

    test "warns for unknown plain string measurement item" do
      source =
        @minimal_header <>
          "\nPROGRESS\n  CHECKPOINT \"Week 4\":\n    at 4 weeks\n    measure:\n      - totally_made_up\n"

      warnings = parse_and_validate!(source)
      metric_warnings = Enum.filter(warnings, &String.contains?(&1.message, "measurement metric"))
      assert length(metric_warnings) > 0
      assert String.contains?(hd(metric_warnings).message, "totally_made_up")
    end
  end

  # ---------------------------------------------------------------------------
  # Direct AST tests (bypass parser; exercise validator object-path logic)
  # ---------------------------------------------------------------------------

  describe "MeasurementMetric v1.6.0 — direct AST" do
    test "no warning for typed MeasurementSpec { metric: 'body_weight_kg' }" do
      doc = doc_with_measurements([%AST.MeasurementSpec{metric: "body_weight_kg"}])
      warnings = Validator.validate_semantics(doc)
      metric_warnings = Enum.filter(warnings, &String.contains?(&1.message, "measurement metric"))
      assert metric_warnings == []
    end

    test "no warning for { metric: 'questionnaire_score', questionnaire: 'psqi' }" do
      doc =
        doc_with_measurements([
          %AST.MeasurementSpec{metric: "questionnaire_score", questionnaire: "psqi"}
        ])

      warnings = Validator.validate_semantics(doc)

      relevant =
        Enum.filter(warnings, fn w ->
          String.contains?(w.message, "measurement metric") or
            String.contains?(w.message, "questionnaire")
        end)

      assert relevant == []
    end

    test "warns for { metric: 'questionnaire_score', questionnaire: 'phq' } — 'phq' is not a valid questionnaire" do
      doc =
        doc_with_measurements([
          %AST.MeasurementSpec{metric: "questionnaire_score", questionnaire: "phq"}
        ])

      warnings = Validator.validate_semantics(doc)
      quest_warnings = Enum.filter(warnings, &String.contains?(&1.message, "questionnaire"))
      assert length(quest_warnings) > 0
      assert String.contains?(hd(quest_warnings).message, "phq")
    end

    test "warns for { metric: 'totally_made_up' } — unknown metric in typed spec" do
      doc = doc_with_measurements([%AST.MeasurementSpec{metric: "totally_made_up"}])
      warnings = Validator.validate_semantics(doc)
      metric_warnings = Enum.filter(warnings, &String.contains?(&1.message, "measurement metric"))
      assert length(metric_warnings) > 0
      assert String.contains?(hd(metric_warnings).message, "totally_made_up")
    end
  end

  # ---------------------------------------------------------------------------
  # Goal category vocabulary
  # ---------------------------------------------------------------------------

  describe "validate_semantics/1 - goal category vocabulary" do
    test "no warning for canonical category weight_loss" do
      source = @minimal_header <> "\nGOALS\n  GOAL primary weight_loss:\n    name \"Lose weight\"\n"
      warnings = parse_and_validate!(source)
      goal_warnings = Enum.filter(warnings, &String.contains?(&1.message, "goal category"))
      assert goal_warnings == []
    end

    test "no warning for general_fitness (new in WPL 1.9.0)" do
      source =
        @minimal_header <> "\nGOALS\n  GOAL primary general_fitness:\n    name \"Get fit\"\n"

      warnings = parse_and_validate!(source)
      goal_warnings = Enum.filter(warnings, &String.contains?(&1.message, "goal category"))
      assert goal_warnings == []
    end

    test "no warning for custom" do
      source = @minimal_header <> "\nGOALS\n  GOAL primary custom:\n    name \"My goal\"\n"
      warnings = parse_and_validate!(source)
      goal_warnings = Enum.filter(warnings, &String.contains?(&1.message, "goal category"))
      assert goal_warnings == []
    end

    test "warns for unknown goal category" do
      source = @minimal_header <> "\nGOALS\n  GOAL primary made_up_thing:\n    name \"Bad\"\n"
      warnings = parse_and_validate!(source)
      goal_warnings = Enum.filter(warnings, &String.contains?(&1.message, "goal category"))
      assert length(goal_warnings) == 1
      assert String.contains?(hd(goal_warnings).message, "made_up_thing")
    end

    test "plan with unknown goal category is still valid (warning, not error)" do
      source = @minimal_header <> "\nGOALS\n  GOAL primary made_up_thing:\n    name \"Bad\"\n"
      assert {:ok, _doc, _repairs} = WplAi.Parser.parse(source)
    end
  end

  # ---------------------------------------------------------------------------
  # Unknown exercise refs
  # ---------------------------------------------------------------------------

  describe "validate_semantics/1 - unknown exercise refs" do
    test "emits a warning for an exercise_ref absent from the catalog" do
      source = ~S"""
      PLAN "Unknown Ex Plan"
      TYPE workout
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "D1":
              main straight_sets:
                totally_unknown_exercise_xyz 3x10
      """

      {:ok, doc, _repairs} = WplAi.parse(source)
      warnings = WplAi.validate_semantics(doc)

      unknown_warnings =
        Enum.filter(warnings, fn w ->
          String.contains?(w.message, "totally_unknown_exercise_xyz")
        end)

      assert length(unknown_warnings) >= 1
      assert hd(unknown_warnings).severity == :warning
    end

    test "does not emit a warning for a known exercise ref" do
      source = ~S"""
      PLAN "Known Ex Plan"
      TYPE workout
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "D1":
              main straight_sets:
                push_up 3x10
      """

      {:ok, doc, _repairs} = WplAi.parse(source)
      warnings = WplAi.validate_semantics(doc)

      unknown_warnings =
        Enum.filter(warnings, fn w ->
          String.contains?(w.message, "push_up") and w.severity == :warning
        end)

      assert unknown_warnings == []
    end
  end
end
