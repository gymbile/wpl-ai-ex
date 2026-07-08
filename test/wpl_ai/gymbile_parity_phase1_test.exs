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

  # The corpus regression fixtures read from an ephemeral spike corpus that is
  # not vendored into the repo. Skip gracefully when absent (e.g. in CI) — the
  # same pattern used by gymbile_parity_phase1d_test.exs.
  defp load_spike(filename) do
    path = "/tmp/wplai_spike/#{filename}"
    if File.exists?(path), do: {:ok, File.read!(path)}, else: :skip
  end

  describe "corpus regression fixtures" do
    test "hybrid__43.wplai parses to 5 phases and 573 activities" do
      case load_spike("hybrid__43.wplai") do
        :skip ->
          IO.puts("SKIP: /tmp/wplai_spike/hybrid__43.wplai not present")

        {:ok, content} ->
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
    end

    test "hybrid__77.wplai parses to multiple phases" do
      case load_spike("hybrid__77.wplai") do
        :skip ->
          IO.puts("SKIP: /tmp/wplai_spike/hybrid__77.wplai not present")

        {:ok, content} ->
          assert {:ok, doc, _repairs} = WplAi.to_wpl(content)
          assert length(doc["plan"]["phases"]) > 1
      end
    end

    test "nutrition__110.wplai parses to multiple phases" do
      case load_spike("nutrition__110.wplai") do
        :skip ->
          IO.puts("SKIP: /tmp/wplai_spike/nutrition__110.wplai not present")

        {:ok, content} ->
          assert {:ok, doc, _repairs} = WplAi.to_wpl(content)
          assert length(doc["plan"]["phases"]) > 1
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Battle-test regression: inline named cardio inside a main block.
  #
  # Subagents emit steady-state cardio as `<modality> continuous:` with an
  # indented `total ... / zone ...` body inside a main straight_sets block.
  # Previously the lib parsed `brisk_walk` as a bare simple activity and then
  # leaked `continuous`, `total`, and `zone` out as three spurious simple
  # activities ("Continuous", "Total", "Zone"). Must now compile to a single
  # cardio activity that retains duration and zone.
  # ---------------------------------------------------------------------------

  describe "inline named cardio in main block" do
    @inline_cardio_plan """
    PLAN "Test Inline Cardio"
    TYPE workout
    LANGUAGE en

    REQUIRES
      AGE 40
      FITNESS beginner

    PHASES
      PHASE "Foundation" (1 weeks):
        WEEK 1:
          DAY Saturday training 45m "Cardio":
            warmup:
              high_knees 5m
            main straight_sets:
              brisk_walk continuous:
                total 30 minutes
                zone 2
    """

    defp cardio_main_activities(doc) do
      doc["plan"]["phases"]
      |> hd()
      |> get_in(["weeks"])
      |> hd()
      |> get_in(["days"])
      |> hd()
      |> get_in(["blocks"])
      |> Enum.find(&(&1["type"] == "main"))
      |> get_in(["activities"])
    end

    test "produces exactly one main activity (no spurious Continuous/Total/Zone)" do
      assert {:ok, doc, _repairs} = WplAi.to_wpl(@inline_cardio_plan)
      activities = cardio_main_activities(doc)
      assert length(activities) == 1

      names =
        activities
        |> Enum.map(&(&1["name"] || &1["exercise_ref"]))
        |> Enum.map(&String.downcase/1)

      refute Enum.any?(names, &(&1 in ["continuous", "total", "zone"]))
    end

    test "retains cardio duration and zone" do
      assert {:ok, doc, _repairs} = WplAi.to_wpl(@inline_cardio_plan)
      activity = doc |> cardio_main_activities() |> hd()

      assert activity["type"] == "cardio"
      assert get_in(activity, ["prescription", "duration", "value"]) == 30
      assert get_in(activity, ["prescription", "intensity", "zone"]) == 2
    end
  end
end
