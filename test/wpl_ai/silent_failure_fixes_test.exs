defmodule WplAi.SilentFailureFixesTest do
  @moduledoc """
  Regression tests for 7 silent-failure parser/lexer bugs fixed in v1.6.6.
  Mirrors the TypeScript test suite at __tests__/silent-failure-fixes.test.ts
  in @gymbile/wpl-ai@1.10.4.
  """

  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp parse_ok!(src) do
    case WplAi.Parser.parse(src) do
      {:ok, doc} -> doc
      {:error, errors} -> flunk("Expected parse to succeed, got errors: #{inspect(errors)}")
    end
  end

  defp parse_errors!(src) do
    case WplAi.Parser.parse(src) do
      {:ok, _} -> flunk("Expected parse to fail, but it succeeded")
      {:error, errors} -> Enum.map(errors, & &1.message)
    end
  end

  defp compile_plan!(src) do
    case WplAi.to_wpl(src) do
      {:ok, json} -> json["plan"]
      {:error, errors} -> flunk("Expected compile to succeed, got errors: #{inspect(errors)}")
    end
  end

  # Minimal valid plan with header lines injected after TYPE.
  defp minimal_plan_with_header(header_lines) do
    """
    PLAN "Test"
    TYPE workout
    #{header_lines}

    PHASES
      PHASE "P1" (1 weeks):
        WEEK 1:
          DAY Monday training:
            main:
    """
  end

  # Minimal plan with a REQUIRES block body.
  defp minimal_plan_with_requires(requires_body) do
    """
    PLAN "Test"
    TYPE workout

    REQUIRES
    #{requires_body}

    PHASES
      PHASE "P1" (1 weeks):
        WEEK 1:
          DAY Monday training:
            main:
    """
  end

  # Minimal plan with a PROGRESS block containing checkpoints.
  defp minimal_plan_with_progress(progress_body) do
    """
    PLAN "Test"
    TYPE workout

    PROGRESS
    #{progress_body}

    PHASES
      PHASE "P1" (1 weeks):
        WEEK 1:
          DAY Monday training:
            main:
    """
  end

  # Minimal plan with a phase type keyword.
  defp minimal_plan_with_phase_type(phase_type_word) do
    """
    PLAN "Test"
    TYPE workout

    PHASES
      PHASE "P1" #{phase_type_word} (1 weeks):
        WEEK 1:
    """
  end

  # Minimal plan with a cooldown block body.
  defp minimal_plan_with_cooldown(cooldown_body) do
    """
    PLAN "Test"
    TYPE workout

    PHASES
      PHASE "P1" (1 weeks):
        WEEK 1:
          DAY Monday training:
            cooldown:
    #{cooldown_body}
    """
  end

  # ---------------------------------------------------------------------------
  # Bug 1 — digit-leading tag: `TAGS 531, strength`
  # ---------------------------------------------------------------------------

  describe "Bug 1 — digit-leading tag (531, strength)" do
    test "parses without error and includes 531 and strength" do
      src = minimal_plan_with_header("TAGS 531, strength")
      doc = parse_ok!(src)
      assert "531" in doc.header.tags
      assert "strength" in doc.header.tags
    end

    test "tags list is not empty (regression: was silently [])" do
      src = minimal_plan_with_header("TAGS 531, strength")
      doc = parse_ok!(src)
      assert length(doc.header.tags) == 2
    end

    test "compiled metadata.tags includes the digit-leading value" do
      src = minimal_plan_with_header("TAGS 531, strength")
      plan = compile_plan!(src)
      tags = plan["metadata"]["tags"]
      assert "531" in tags
      assert "strength" in tags
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 2 — digit-leading identifier in TAGS list: 1rm_estimate truncates list
  # ---------------------------------------------------------------------------

  describe "Bug 2 — digit-leading identifier in TAGS list (1rm_estimate)" do
    setup do
      src = minimal_plan_with_header("TAGS strength_test, assessment, 1rm_estimate, powerlifting")
      {:ok, src: src}
    end

    test "all four tags are parsed (list not truncated at 1rm_estimate)", %{src: src} do
      doc = parse_ok!(src)
      assert length(doc.header.tags) == 4
      assert "1rm_estimate" in doc.header.tags
      assert "powerlifting" in doc.header.tags
    end

    test "compiled output preserves all tags", %{src: src} do
      plan = compile_plan!(src)
      tags = plan["metadata"]["tags"]
      assert length(tags) == 4
      assert "1rm_estimate" in tags
      assert "powerlifting" in tags
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 3 — colon in contraindication name (acsm:cardiac_rehab_phase_2)
  # ---------------------------------------------------------------------------

  describe "Bug 3 — colon-qualified identifier in contraindication name" do
    test "parses without error" do
      src = minimal_plan_with_requires("  contraindication acsm:cardiac_rehab_phase_2")
      doc = parse_ok!(src)
      assert [contra | _] = doc.requirements.contraindications
      assert contra != nil
    end

    test "condition includes the full colon-qualified name" do
      src = minimal_plan_with_requires("  contraindication acsm:cardiac_rehab_phase_2")
      doc = parse_ok!(src)
      [contra | _] = doc.requirements.contraindications
      assert contra.condition == "acsm:cardiac_rehab_phase_2"
    end

    test "icd10: prefix is also accepted" do
      src = minimal_plan_with_requires("  contraindication icd10:M54.5")
      doc = parse_ok!(src)
      [contra | _] = doc.requirements.contraindications
      assert contra.condition == "icd10:M54.5"
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 4 — unknown REQUIRES directive produces a parse error
  # ---------------------------------------------------------------------------

  describe "Bug 4 — unknown REQUIRES directive emits error (no silent termination)" do
    test "produces a parse error for `supervision required` in REQUIRES block" do
      src = minimal_plan_with_requires("  supervision required")
      msgs = parse_errors!(src)
      assert length(msgs) > 0
      combined = Enum.join(msgs, " ")
      assert combined =~ ~r/Unknown REQUIRES directive/i
      assert combined =~ "supervision required"
      assert combined =~ ~r/contraindication|fitness|equipment|age|time_commitment/i
    end

    test "error message includes the unrecognised line text" do
      src = minimal_plan_with_requires("  foo_bar whatever")
      msgs = parse_errors!(src)
      combined = Enum.join(msgs, " ")
      assert combined =~ "foo_bar"
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 5 — `trigger completion` (no-arg) emits error
  # ---------------------------------------------------------------------------

  describe "Bug 5 — `trigger completion` emits explicit parse error" do
    test "rejects `trigger completion` with a helpful message" do
      src =
        minimal_plan_with_progress("""
          checkpoints:
            checkpoint "Week 1 review":
              trigger completion
              measure:
                - weight kg
        """)

      msgs = parse_errors!(src)
      assert length(msgs) > 0
      combined = Enum.join(msgs, " ")
      assert combined =~ ~r/completion/i
      assert combined =~ ~r/at N weeks|at N days/i
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 6 — unknown phase type emits explicit error
  # ---------------------------------------------------------------------------

  describe "Bug 6 — unknown phase type emits explicit parse error" do
    test "rejects `rehabilitation` as a phase type with an allowed-list error" do
      src = minimal_plan_with_phase_type("rehabilitation")
      msgs = parse_errors!(src)
      assert length(msgs) > 0
      combined = Enum.join(msgs, " ")
      assert combined =~ "rehabilitation"
      assert combined =~ ~r/accumulation|intensification|realization/i
    end

    test "rejects unknown phase type `cardio_block`" do
      src = minimal_plan_with_phase_type("cardio_block")
      msgs = parse_errors!(src)
      combined = Enum.join(msgs, " ")
      assert combined =~ "cardio_block"
    end

    test "known phase type `accumulation` is still accepted" do
      src = minimal_plan_with_phase_type("accumulation")
      doc = parse_ok!(src)
      [phase | _] = doc.phases
      assert phase.type == "accumulation"
    end
  end

  # ---------------------------------------------------------------------------
  # Bug 7 — `jogging 10m` in cooldown produces CardioActivity, not malformed recovery_exercise
  # ---------------------------------------------------------------------------

  describe "Bug 7 — `jogging 10m` in cooldown parses as CardioActivity" do
    setup do
      src = minimal_plan_with_cooldown("          jogging 10m")
      {:ok, src: src}
    end

    test "parses without error", %{src: src} do
      doc = parse_ok!(src)
      assert doc != nil
    end

    test "produces exactly one activity (no phantom `m` orphan)", %{src: src} do
      doc = parse_ok!(src)
      [phase | _] = doc.phases
      [week | _] = phase.weeks
      [day | _] = week.days
      [block | _] = day.blocks
      assert length(block.activities) == 1
    end

    test "the activity is a Cardio kind (not recovery)", %{src: src} do
      doc = parse_ok!(src)
      [phase | _] = doc.phases
      [week | _] = phase.weeks
      [day | _] = week.days
      [block | _] = day.blocks
      [activity | _] = block.activities
      assert match?(%WplAi.AST.Cardio{}, activity)
    end

    test "modality is `jogging`", %{src: src} do
      doc = parse_ok!(src)
      [phase | _] = doc.phases
      [week | _] = phase.weeks
      [day | _] = week.days
      [block | _] = day.blocks
      [activity | _] = block.activities
      assert activity.modality == "jogging"
    end

    test "total_duration.value is 10 and unit is minutes", %{src: src} do
      doc = parse_ok!(src)
      [phase | _] = doc.phases
      [week | _] = phase.weeks
      [day | _] = week.days
      [block | _] = day.blocks
      [activity | _] = block.activities
      assert activity.total_duration.value == 10
      assert activity.total_duration.unit == :minutes
    end

    test "does NOT produce a recovery activity", %{src: src} do
      doc = parse_ok!(src)
      [phase | _] = doc.phases
      [week | _] = phase.weeks
      [day | _] = week.days
      [block | _] = day.blocks
      [activity | _] = block.activities
      refute match?(%WplAi.AST.RecoveryExercise{}, activity)
    end

    test "compiled output type is `cardio`", %{src: src} do
      plan = compile_plan!(src)
      phase = hd(plan["phases"])
      week = hd(phase["weeks"])
      day = hd(week["days"])
      block = hd(day["blocks"])
      activities = block["activities"]
      assert length(activities) == 1
      assert hd(activities)["type"] == "cardio"
    end
  end
end
