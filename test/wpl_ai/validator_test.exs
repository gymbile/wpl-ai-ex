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
end
