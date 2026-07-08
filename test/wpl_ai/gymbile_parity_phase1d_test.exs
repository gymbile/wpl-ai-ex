defmodule WplAi.GymbiParityPhase1dTest do
  @moduledoc """
  Regression tests for Phase 1d gymbile structural-equivalence fixes.

  Root causes fixed (parser.ex):
    A1 — Time-unit suffix (`seconds`) after reps not consumed when followed by
         an exercise qualifier word (`each`, `side`, `each_side`, …).
         e.g. `side_plank 3x20 seconds each side`
    A2 — Short `s` suffix after `target N` not in @target_units.
         e.g. `plank 3x30 target 30s rpe 6 rest 30 seconds`
    A3 — Short `s` suffix at end-of-line (newline/dedent) not consumed.
         e.g. `plank 3x20s` (nothing following)
    A4 — Compound qualifier tokens (`each_side`, `each_leg`) not in
         @exercise_qualifiers, so they leaked as spurious simple activities.
    B1 — `cooldown_cardio_pattern?` triggered for non-cardio recovery exercises
         (`breathing_4_7_8 30s`) because it didn't check the modality name.
    B2 — Bare `both`/`left`/`right` after reps in parse_recovery_exercise
         (no preceding `sides` keyword) leaked as a spurious recovery_exercise.
         e.g. `breathing_4_7_8 30s x1 both`

  Each test asserts the compiled output fingerprint matches the gymbile reference.
  Fingerprints computed from gymbile_backend's WPL-AI compiler (2026-07-08).
  """

  use ExUnit.Case, async: true

  @moduletag :skip_if_no_corpus

  # ---------------------------------------------------------------------------
  # Helper
  # ---------------------------------------------------------------------------

  defp fingerprint(json) do
    p = json["plan"] || json
    phases = p["phases"] || []
    weeks = Enum.flat_map(phases, &(&1["weeks"] || []))
    days = Enum.flat_map(weeks, &(&1["days"] || []))
    blocks = Enum.flat_map(days, &(&1["blocks"] || []))
    acts = Enum.flat_map(blocks, &(&1["activities"] || []))

    types =
      acts
      |> Enum.group_by(& &1["type"])
      |> Enum.map(fn {k, v} -> {k, length(v)} end)
      |> Enum.sort()

    exercise_refs =
      acts
      |> Enum.map(&(&1["exercise_ref"] || &1["exercise"]))
      |> Enum.reject(&is_nil/1)
      |> length()

    %{
      phases: length(phases),
      weeks: length(weeks),
      days: length(days),
      acts: length(acts),
      types: types,
      nex: exercise_refs
    }
  end

  defp load_corpus(filename) do
    path = "/tmp/wplai_spike/#{filename}"

    if File.exists?(path) do
      {:ok, File.read!(path)}
    else
      :skip
    end
  end

  # ---------------------------------------------------------------------------
  # Cause A — Spurious simple activities from unconsumed prescription tokens
  # ---------------------------------------------------------------------------

  describe "A1/A3 — side_plank 3x20 seconds each side (hybrid__112)" do
    test "no spurious Seconds/Each/Side activities; matches gymbile fingerprint" do
      case load_corpus("hybrid__112.wplai") do
        :skip ->
          IO.puts("SKIP: /tmp/wplai_spike/hybrid__112.wplai not present")

        {:ok, text} ->
          assert {:ok, json, _} = WplAi.to_wpl(text)
          fp = fingerprint(json)

          assert fp.phases == 4
          assert fp.weeks == 16
          assert fp.days == 100
          assert fp.acts == 368
          assert fp.nex == 96
          # No spurious simple from `seconds` / `each` / `side` tokens
          assert {"simple", 32} in fp.types
          assert {"recovery_exercise", 64} in fp.types
          assert {"exercise", 96} in fp.types
          # Ensure no activity named "Seconds", "Each", or "Side"
          acts =
            json["plan"]["phases"]
            |> Enum.flat_map(&(&1["weeks"] || []))
            |> Enum.flat_map(&(&1["days"] || []))
            |> Enum.flat_map(&(&1["blocks"] || []))
            |> Enum.flat_map(&(&1["activities"] || []))

          spurious_names = MapSet.new(["Seconds", "Each", "Side", "Each Side"])
          actual_names = acts |> Enum.map(& &1["name"]) |> Enum.reject(&is_nil/1) |> MapSet.new()

          assert MapSet.disjoint?(spurious_names, actual_names),
                 "Found spurious activity names: #{inspect(MapSet.intersection(spurious_names, actual_names))}"
      end
    end
  end

  describe "A1/A3 — side_plank 3x20s each side (hybrid__26)" do
    test "no spurious Seconds/Each/Side activities; matches gymbile fingerprint" do
      case load_corpus("hybrid__26.wplai") do
        :skip ->
          IO.puts("SKIP: /tmp/wplai_spike/hybrid__26.wplai not present")

        {:ok, text} ->
          assert {:ok, json, _} = WplAi.to_wpl(text)
          fp = fingerprint(json)

          assert fp.phases == 4
          assert fp.weeks == 16
          assert fp.days == 97
          assert fp.acts == 356
          assert fp.nex == 96
          assert {"simple", 32} in fp.types
          assert {"recovery_exercise", 64} in fp.types
      end
    end
  end

  describe "A2/A3 — plank 3x30 target 30s and each_side qualifier (hybrid__94)" do
    test "no spurious S/Each Side activities; matches gymbile fingerprint" do
      case load_corpus("hybrid__94.wplai") do
        :skip ->
          IO.puts("SKIP: /tmp/wplai_spike/hybrid__94.wplai not present")

        {:ok, text} ->
          assert {:ok, json, _} = WplAi.to_wpl(text)
          fp = fingerprint(json)

          assert fp.phases == 4
          assert fp.weeks == 16
          assert fp.days == 112
          assert fp.acts == 368
          assert fp.nex == 72
          assert {"simple", 24} in fp.types
          assert {"recovery_exercise", 48} in fp.types
          # No spurious "S" or "Each Side"
          acts =
            json["plan"]["phases"]
            |> Enum.flat_map(&(&1["weeks"] || []))
            |> Enum.flat_map(&(&1["days"] || []))
            |> Enum.flat_map(&(&1["blocks"] || []))
            |> Enum.flat_map(&(&1["activities"] || []))

          refute Enum.any?(acts, fn a -> a["name"] in ["S", "Each Side"] end)
      end
    end
  end

  describe "A2 — plank target 30s + B2 bare both (hybrid__66)" do
    test "no spurious S/RPE/both activities; matches gymbile fingerprint" do
      case load_corpus("hybrid__66.wplai") do
        :skip ->
          IO.puts("SKIP: /tmp/wplai_spike/hybrid__66.wplai not present")

        {:ok, text} ->
          assert {:ok, json, _} = WplAi.to_wpl(text)
          fp = fingerprint(json)

          assert fp.phases == 4
          assert fp.weeks == 16
          assert fp.days == 109
          assert fp.acts == 404
          assert fp.nex == 96
          assert {"simple", 32} in fp.types
          assert {"recovery_exercise", 64} in fp.types
          # No spurious "both" recovery_exercise
          acts =
            json["plan"]["phases"]
            |> Enum.flat_map(&(&1["weeks"] || []))
            |> Enum.flat_map(&(&1["days"] || []))
            |> Enum.flat_map(&(&1["blocks"] || []))
            |> Enum.flat_map(&(&1["activities"] || []))

          refute Enum.any?(acts, fn a ->
                   a["type"] == "recovery_exercise" and a["name"] == "both"
                 end)
      end
    end
  end

  describe "B2 — bare both without sides keyword (hybrid__93)" do
    test "no spurious both recovery_exercise; matches gymbile fingerprint" do
      case load_corpus("hybrid__93.wplai") do
        :skip ->
          IO.puts("SKIP: /tmp/wplai_spike/hybrid__93.wplai not present")

        {:ok, text} ->
          assert {:ok, json, _} = WplAi.to_wpl(text)
          fp = fingerprint(json)

          assert fp.phases == 6
          assert fp.weeks == 16
          assert fp.days == 94
          assert fp.acts == 344
          assert fp.nex == 96
          assert {"simple", 32} in fp.types
          assert {"recovery_exercise", 64} in fp.types
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Cause B — Activity classification mismatch
  # ---------------------------------------------------------------------------

  describe "B1 — breathing_4_7_8 in cooldown not parsed as cardio (hybrid__119)" do
    test "breathing exercises are recovery_exercise not cardio; matches gymbile fingerprint" do
      case load_corpus("hybrid__119.wplai") do
        :skip ->
          IO.puts("SKIP: /tmp/wplai_spike/hybrid__119.wplai not present")

        {:ok, text} ->
          assert {:ok, json, _} = WplAi.to_wpl(text)
          fp = fingerprint(json)

          assert fp.phases == 6
          assert fp.weeks == 20
          assert fp.days == 118
          assert fp.acts == 446
          assert fp.nex == 130
          # No cardio activities — breathing is recovery_exercise
          refute Enum.any?(fp.types, fn {t, _} -> t == "cardio" end)
          assert {"recovery_exercise", 80} in fp.types
          assert {"simple", 40} in fp.types
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Unit-level regression: parser patterns
  # ---------------------------------------------------------------------------

  describe "unit parsing: time suffix at end of line consumed" do
    @plan_with_timed_sets """
    PLAN "Timed Sets"
    TYPE workout

    PHASES
      PHASE "P1" (1 weeks):
        WEEK 1:
          DAY Monday training "Day":
            main tabata:
              plank 3x30s
              push_up 3x20s
    """

    test "produces 2 exercises with no spurious S simple activities" do
      assert {:ok, json, _} = WplAi.to_wpl(@plan_with_timed_sets)

      acts =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> hd()
        |> Map.get("activities")

      assert length(acts) == 2
      assert Enum.all?(acts, fn a -> a["type"] == "exercise" end)
      refute Enum.any?(acts, fn a -> a["name"] == "S" end)
    end
  end

  describe "unit parsing: each_side compound qualifier consumed" do
    @plan_with_each_side """
    PLAN "Each Side"
    TYPE workout

    PHASES
      PHASE "P1" (1 weeks):
        WEEK 1:
          DAY Monday training "Day":
            main circuit:
              dead_bug 3x10 each_side
              mountain_climber 3x12 each_side
    """

    test "produces 2 exercises with no spurious Each Side simple activities" do
      assert {:ok, json, _} = WplAi.to_wpl(@plan_with_each_side)

      acts =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> hd()
        |> Map.get("activities")

      assert length(acts) == 2
      assert Enum.all?(acts, fn a -> a["type"] == "exercise" end)
      refute Enum.any?(acts, fn a -> a["name"] == "Each Side" end)
    end
  end

  describe "unit parsing: time suffix before exercise qualifiers consumed" do
    @plan_with_seconds_each_side """
    PLAN "Seconds Each Side"
    TYPE workout

    PHASES
      PHASE "P1" (1 weeks):
        WEEK 1:
          DAY Monday training "Day":
            main straight_sets:
              side_plank 3x20 seconds each side
    """

    test "produces 1 exercise with no spurious Seconds/Each/Side simple activities" do
      assert {:ok, json, _} = WplAi.to_wpl(@plan_with_seconds_each_side)

      acts =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> hd()
        |> Map.get("activities")

      assert length(acts) == 1
      assert hd(acts)["type"] == "exercise"
      assert hd(acts)["exercise_ref"] == "side_plank"
    end
  end

  describe "unit parsing: bare both/left/right after reps in recovery_exercise" do
    @plan_with_bare_both """
    PLAN "Bare Both"
    TYPE workout

    PHASES
      PHASE "P1" (1 weeks):
        WEEK 1:
          DAY Monday training "Day":
            cooldown:
              breathing_4_7_8 30s x1 both
              chest_stretch 30s x2 sides both
    """

    test "produces 2 recovery_exercises with no spurious both activity" do
      assert {:ok, json, _} = WplAi.to_wpl(@plan_with_bare_both)

      acts =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> hd()
        |> Map.get("activities")

      assert length(acts) == 2
      assert Enum.all?(acts, fn a -> a["type"] == "recovery_exercise" end)
      refute Enum.any?(acts, fn a -> a["name"] == "both" end)
    end
  end

  describe "unit parsing: breathing_4_7_8 in cooldown is recovery_exercise not cardio" do
    @plan_with_breathing """
    PLAN "Breathing Cooldown"
    TYPE workout

    PHASES
      PHASE "P1" (1 weeks):
        WEEK 1:
          DAY Monday training "Day":
            cooldown:
              breathing_4_7_8 30s
    """

    test "breathing_4_7_8 compiles as recovery_exercise" do
      assert {:ok, json, _} = WplAi.to_wpl(@plan_with_breathing)

      acts =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> hd()
        |> Map.get("activities")

      assert length(acts) == 1
      assert hd(acts)["type"] == "recovery_exercise"
      refute hd(acts)["type"] == "cardio"
    end
  end

  describe "unit parsing: jogging in cooldown is still cardio (Bug 7 regression)" do
    @plan_with_jogging """
    PLAN "Jogging Cooldown"
    TYPE workout

    PHASES
      PHASE "P1" (1 weeks):
        WEEK 1:
          DAY Monday training "Day":
            cooldown:
              jogging 10m
    """

    test "jogging 10m in cooldown compiles as cardio (Bug 7 preserved)" do
      assert {:ok, json, _} = WplAi.to_wpl(@plan_with_jogging)

      acts =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> hd()
        |> Map.get("activities")

      assert length(acts) == 1
      assert hd(acts)["type"] == "cardio"
    end
  end
end
