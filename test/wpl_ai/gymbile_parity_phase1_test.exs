defmodule WplAi.GymbiParityPhase1Test do
  @moduledoc """
  Regression tests for Phase 1 gymbile parser-parity fixes.

  Fix A: Inline EQUIPMENT (no colon) in REQUIRES block.
  Fix B: Tolerant freeform RULE lines inside PERSONALIZATION.
  Fix C: Empty equipment: (colon, no indent) in REQUIRES block.

  Each of the 3 corpus fixtures that previously crashed the lib must now
  return {:ok, _, _} and produce a full multi-phase plan.
  """

  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Fix A: Inline EQUIPMENT
  # ---------------------------------------------------------------------------

  describe "inline EQUIPMENT in REQUIRES (no colon)" do
    @inline_equipment_plan """
    PLAN "Test Inline Equipment"
    TYPE workout
    LANGUAGE en

    REQUIRES
      AGE 30
      FITNESS intermediate
      EQUIPMENT dumbbells cables bodyweight

    PHASES
      PHASE "Phase 1" (1 weeks):
        WEEK 1:
          DAY Monday training 30m "Day":
            warmup:
              arm_circles 5m
            main straight_sets:
              push_up 3x10 rpe 7
    """

    test "parses inline EQUIPMENT list as required equipment" do
      assert {:ok, doc, _repairs} = WplAi.to_wpl(@inline_equipment_plan)
      equipment = doc["plan"]["requirements"]["equipment"]
      assert length(equipment) == 3
      names = Enum.map(equipment, & &1["name"])
      assert "dumbbells" in names
      assert "cables" in names
      assert "bodyweight" in names
      # All required: true (default for inline form)
      assert Enum.all?(equipment, & &1["required"])
    end

    test "emits a normalized_inline_equipment repair" do
      assert {:ok, _doc, repairs} = WplAi.to_wpl(@inline_equipment_plan)
      assert Enum.any?(repairs, &(&1[:type] == :normalized_inline_equipment))
    end

    test "plan still fully compiles (phases and activities present)" do
      assert {:ok, doc, _repairs} = WplAi.to_wpl(@inline_equipment_plan)
      phases = doc["plan"]["phases"]
      assert length(phases) == 1
      days = hd(phases)["weeks"] |> hd() |> Map.get("days")
      assert length(days) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Fix B: Freeform RULE lines in PERSONALIZATION
  # ---------------------------------------------------------------------------

  describe "freeform RULE lines directly in PERSONALIZATION" do
    @freeform_rules_plan """
    PLAN "Test Freeform Rules"
    TYPE hybrid
    LANGUAGE en

    REQUIRES
      AGE 35
      FITNESS beginner

    PERSONALIZATION
      RULE when sleep < 6 hours: RPE cap at 7
      RULE when traveling: use hotel gym equipment

    PHASES
      PHASE "Foundation" (1 weeks):
        WEEK 1:
          DAY Monday training 30m "Day":
            main straight_sets:
              push_up 3x8 rpe 6
    """

    test "parses without error despite freeform RULE lines" do
      assert {:ok, _doc, _repairs} = WplAi.to_wpl(@freeform_rules_plan)
    end

    test "emits skipped_rule repairs for each freeform RULE" do
      assert {:ok, _doc, repairs} = WplAi.to_wpl(@freeform_rules_plan)
      skipped = Enum.filter(repairs, &(&1[:type] == :skipped_rule))
      assert length(skipped) == 2
    end

    test "phases are still parsed after PERSONALIZATION with freeform RULE lines" do
      assert {:ok, doc, _repairs} = WplAi.to_wpl(@freeform_rules_plan)
      phases = doc["plan"]["phases"]
      assert length(phases) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Fix C: Empty equipment: block (colon, no indented entries)
  # ---------------------------------------------------------------------------

  describe "empty equipment: block in REQUIRES" do
    @empty_equipment_plan """
    PLAN "Test Empty Equipment"
    TYPE nutrition
    LANGUAGE en

    REQUIRES
      age 18..65
      fitness intermediate
      equipment:

    PHASES
      PHASE "Nutrition" (1 weeks):
        WEEK 1:
          DAY Monday nutrition 0m "Day":
            meals:
              MEAL BREAKFAST: oatmeal
                PROTEIN 20g
                CARBS 40g
                FAT 10g
                CALORIES 350kcal
    """

    test "parses empty equipment block without cascading to PERSONALIZATION" do
      assert {:ok, doc, _repairs} = WplAi.to_wpl(@empty_equipment_plan)
      requirements = doc["plan"]["requirements"]
      equipment = requirements["equipment"]
      assert equipment == [] or equipment == nil
    end

    test "phases parse correctly after empty equipment: block" do
      assert {:ok, doc, _repairs} = WplAi.to_wpl(@empty_equipment_plan)
      phases = doc["plan"]["phases"]
      assert length(phases) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Corpus regression: the 3 gymbile fixtures that previously hard-errored
  # ---------------------------------------------------------------------------

  describe "corpus regression fixtures" do
    test "hybrid__43.wplai parses to 5 phases and 573 activities" do
      content = File.read!("/tmp/wplai_spike/hybrid__43.wplai")
      assert {:ok, doc, _repairs} = WplAi.to_wpl(content)
      phases = doc["plan"]["phases"]
      assert length(phases) == 5

      total_activities =
        Enum.sum(
          Enum.map(phases, fn p ->
            Enum.sum(
              Enum.map(p["weeks"] || [], fn w ->
                Enum.sum(
                  Enum.map(w["days"] || [], fn d ->
                    Enum.sum(
                      Enum.map(d["blocks"] || [], fn b -> length(b["activities"] || []) end)
                    )
                  end)
                )
              end)
            )
          end)
        )

      assert total_activities == 573
    end

    test "hybrid__77.wplai parses to multiple phases" do
      content = File.read!("/tmp/wplai_spike/hybrid__77.wplai")
      assert {:ok, doc, _repairs} = WplAi.to_wpl(content)
      phases = doc["plan"]["phases"]
      assert length(phases) > 1
    end

    test "nutrition__110.wplai parses to multiple phases" do
      content = File.read!("/tmp/wplai_spike/nutrition__110.wplai")
      assert {:ok, doc, _repairs} = WplAi.to_wpl(content)
      phases = doc["plan"]["phases"]
      assert length(phases) > 1
    end
  end
end
