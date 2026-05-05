defmodule WplAi.ErrorsTest do
  use ExUnit.Case, async: true

  alias WplAi.Errors

  describe "format_validation_errors_for_llm/2" do
    test "formats validation errors with header and numbered list" do
      errors = [
        "Goal 1: missing required field 'name'",
        "Plan type 'workout' requires at least one phase"
      ]

      result = Errors.format_validation_errors_for_llm(errors, "PLAN \"Test\"\nTYPE workout")

      assert String.contains?(result, "compiled to JSON but failed WPL validation")
      assert String.contains?(result, "1. Goal 1: missing required field 'name'")
      assert String.contains?(result, "2. Plan type 'workout' requires at least one phase")
      assert String.contains?(result, "Output ONLY the corrected WPL-AI text")
    end

    test "includes goal-related reminders when errors mention 'goal'" do
      errors = ["Goal 1: missing required field 'name'"]
      result = Errors.format_validation_errors_for_llm(errors, "source")

      assert String.contains?(result, "Remember:")
      assert String.contains?(result, "GOAL")
    end

    test "includes phase-related reminders when errors mention 'phase'" do
      errors = ["Plan requires at least one phase"]
      result = Errors.format_validation_errors_for_llm(errors, "source")

      assert String.contains?(result, "Remember:")
      assert String.contains?(result, "PHASE")
    end

    test "includes type-related reminders when errors mention 'type'" do
      errors = ["Invalid plan type 'exercise'"]
      result = Errors.format_validation_errors_for_llm(errors, "source")

      assert String.contains?(result, "Remember:")
      assert String.contains?(result, "workout, nutrition")
    end

    test "limits reminders to at most 4" do
      # Error containing many keywords
      errors = [
        "Invalid type for goal in phase with wrong difficulty on day in week"
      ]

      result = Errors.format_validation_errors_for_llm(errors, "source")
      reminder_lines = result |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "- "))
      assert length(reminder_lines) <= 4
    end

    test "handles empty error list" do
      result = Errors.format_validation_errors_for_llm([], "source")
      assert String.contains?(result, "compiled to JSON but failed WPL validation")
    end
  end
end
