defmodule WplAi.TierEFeaturesTest do
  use ExUnit.Case, async: true

  alias WplAi

  # ---------------------------------------------------------------------------
  # Shared DSL helpers
  # ---------------------------------------------------------------------------

  defp plan_header do
    """
    PLAN "Test Plan"
    TYPE workout
    """
  end

  defp phases_header do
    "PHASES\n  PHASE \"P1\" (1 weeks):\n    WEEK 1:\n      DAY Monday training 60m:\n"
  end

  defp with_requires(body),
    do: plan_header() <> "\nREQUIRES\n" <> body <> "\n\n" <> phases_header() <> "        main:\n"

  defp with_main_block(body),
    do: plan_header() <> "\n" <> phases_header() <> "        main:\n" <> body <> "\n"

  defp with_recovery_activity(exercise_line, pnf_line \\ nil) do
    pnf = if pnf_line, do: "            " <> pnf_line <> "\n", else: ""

    plan_header() <>
      "\n" <>
      phases_header() <>
      "        cooldown:\n" <>
      "          recovery stretching:\n" <>
      "            " <>
      exercise_line <>
      "\n" <>
      pnf
  end

  defp with_progress(body),
    do:
      plan_header() <>
        "\n" <>
        phases_header() <>
        "        main:\n          push_up 3x10\n\nPROGRESS\n" <>
        body <>
        "\n"

  defp get_first_activity(json, block_index \\ 0) do
    json["plan"]["phases"]
    |> List.first()
    |> Map.get("weeks")
    |> List.first()
    |> Map.get("days")
    |> List.first()
    |> Map.get("blocks")
    |> Enum.at(block_index)
    |> Map.get("activities")
    |> List.first()
  end

  # ---------------------------------------------------------------------------
  # Feature 1: Contraindication.severity + require_clearance action
  # ---------------------------------------------------------------------------

  describe "Feature 1 — Contraindication severity + require_clearance (DSL)" do
    test "parses severity high and require_clearance action from new DSL" do
      src =
        with_requires(
          "  contraindication high_blood_pressure severity high action require_clearance\n"
        )

      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      contraindications = json["plan"]["requirements"]["contraindications"]
      ci = List.first(contraindications)
      assert ci["condition"] == "high_blood_pressure"
      assert ci["severity"] == "high"
      assert ci["action"] == "require_clearance"
    end

    test "parses severity moderate with modify action" do
      src = with_requires("  contraindication knee_pain severity moderate action modify\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      contraindications = json["plan"]["requirements"]["contraindications"]
      ci = List.first(contraindications)
      assert ci["condition"] == "knee_pain"
      assert ci["severity"] == "moderate"
      assert ci["action"] == "modify"
    end

    test "parses severity low with exclude action" do
      src = with_requires("  contraindication mild_arthritis severity low action exclude\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      contraindications = json["plan"]["requirements"]["contraindications"]
      ci = List.first(contraindications)
      assert ci["condition"] == "mild_arthritis"
      assert ci["severity"] == "low"
      assert ci["action"] == "exclude"
    end

    test "back-compat: old arrow-style contraindication still works" do
      src = with_requires("  contraindication lower_back -> modify\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      contraindications = json["plan"]["requirements"]["contraindications"]
      ci = List.first(contraindications)
      assert ci["condition"] == "lower_back"
      assert ci["action"] == "modify"
      refute Map.has_key?(ci, "severity")
    end

    test "action-only (no severity) does not emit severity field" do
      src = with_requires("  contraindication heart_condition action require_clearance\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      contraindications = json["plan"]["requirements"]["contraindications"]
      ci = List.first(contraindications)
      assert ci["action"] == "require_clearance"
      refute Map.has_key?(ci, "severity")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature 2: Reps.amrap
  # ---------------------------------------------------------------------------

  describe "Feature 2 — Reps.amrap" do
    test "1xAMRAP emits reps.amrap: true with no target" do
      src = with_main_block("          push_up 1xAMRAP rpe 9\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      reps = act["prescription"]["reps"]
      assert reps["amrap"] == true
      refute Map.has_key?(reps, "target")
    end

    test "3xAMRAP emits sets=3 with reps.amrap: true" do
      src = with_main_block("          bench_press 3xAMRAP weight 80% rm\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      assert act["prescription"]["sets"] == 3
      assert act["prescription"]["reps"]["amrap"] == true
    end

    test "lowercase amrap token also works" do
      src = with_main_block("          squat 1x amrap\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      assert act["prescription"]["reps"]["amrap"] == true
    end

    test "normal reps (no amrap) do not emit amrap field" do
      src = with_main_block("          push_up 3x10\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      reps = act["prescription"]["reps"]
      refute Map.has_key?(reps, "amrap")
      assert reps["target"] == 10
    end
  end

  # ---------------------------------------------------------------------------
  # Feature 3: ExercisePrescription.to_failure
  # ---------------------------------------------------------------------------

  describe "Feature 3 — ExercisePrescription.to_failure" do
    test "emits to_failure: true when modifier is present" do
      src =
        with_main_block("          bench_press 3x6 weight 80% rm to_failure rest 120 seconds\n")

      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      assert act["prescription"]["to_failure"] == true
    end

    test "emits to_failure without any other modifiers" do
      src = with_main_block("          push_up 3x10 to_failure\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      assert act["prescription"]["to_failure"] == true
    end

    test "to_failure can appear before rpe" do
      src = with_main_block("          squat 4x8 to_failure rpe 9\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      assert act["prescription"]["to_failure"] == true
      assert act["target_rpe"] == 9
    end

    test "without to_failure the field is absent" do
      src = with_main_block("          push_up 3x10 rpe 7\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      refute Map.has_key?(act["prescription"], "to_failure")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature 4: Weight.metric qualifier
  # ---------------------------------------------------------------------------

  describe "Feature 4 — Weight.metric qualifier" do
    test "metric training_max is emitted" do
      src = with_main_block("          squat 3x5 weight 80% rm metric training_max\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      wt = act["prescription"]["weight"]
      assert wt["type"] == "percentage_1rm"
      assert wt["value"] == 80
      assert wt["metric"] == "training_max"
    end

    test "metric e1rm maps to canonical e1RM" do
      src = with_main_block("          deadlift 3x3 weight 90% rm metric e1rm\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      assert act["prescription"]["weight"]["metric"] == "e1RM"
    end

    test "metric 1rm maps to canonical 1RM" do
      src = with_main_block("          squat 5x5 weight 75% rm metric 1rm\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      assert act["prescription"]["weight"]["metric"] == "1RM"
    end

    test "metric daily_max is emitted verbatim" do
      src = with_main_block("          bench_press 3x3 weight 85% rm metric daily_max\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      assert act["prescription"]["weight"]["metric"] == "daily_max"
    end

    test "weight without metric does not emit metric field" do
      src = with_main_block("          squat 3x5 weight 80% rm\n")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      refute Map.has_key?(act["prescription"]["weight"], "metric")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature 5: RecoveryExercise extensions (modality, pnf, intensity_rpe, body_part)
  # ---------------------------------------------------------------------------

  describe "Feature 5 — RecoveryExercise modality/pnf/intensity_rpe/body_part" do
    test "parses modality static_stretch" do
      src = with_recovery_activity("hip_flexor_stretch 30s x2 sides both modality static_stretch")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      ex = List.first(act["prescription"]["exercises"])
      assert ex["modality"] == "static_stretch"
    end

    test "parses modality dynamic_stretch" do
      src = with_recovery_activity("leg_swing 10s x10 modality dynamic_stretch")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      ex = List.first(act["prescription"]["exercises"])
      assert ex["modality"] == "dynamic_stretch"
    end

    test "parses intensity_rpe from intensity keyword" do
      src = with_recovery_activity("hamstring_stretch 30s x3 modality static_stretch intensity 6")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      ex = List.first(act["prescription"]["exercises"])
      assert ex["intensity_rpe"] == 6
    end

    test "parses body_part from body keyword" do
      src = with_recovery_activity("pigeon_pose 45s x2 body hip_flexors")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      ex = List.first(act["prescription"]["exercises"])
      assert ex["body_part"] == "hip_flexors"
    end

    test "parses all modifiers together: modality pnf + intensity + body" do
      src =
        with_recovery_activity(
          "hip_flexor_stretch 30s x2 sides both modality pnf intensity 6 body hip_flexors"
        )

      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      ex = List.first(act["prescription"]["exercises"])
      assert ex["modality"] == "pnf"
      assert ex["intensity_rpe"] == 6
      assert ex["body_part"] == "hip_flexors"
    end

    test "parses pnf block continuation line" do
      src =
        with_recovery_activity(
          "hip_flexor_stretch 30s x2 sides both modality pnf intensity 6 body hip_flexors",
          "pnf 6s contract 20s relax 3 contractions"
        )

      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      ex = List.first(act["prescription"]["exercises"])
      pnf = ex["pnf"]
      assert pnf != nil
      assert pnf["contraction_seconds"] == 6
      assert pnf["relax_seconds"] == 20
      assert pnf["contractions"] == 3
    end

    test "back-compat: recovery exercise without new modifiers still works" do
      src = with_recovery_activity("hamstring_stretch 30s x2 sides both")
      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      ex = List.first(act["prescription"]["exercises"])
      refute Map.has_key?(ex, "modality")
      refute Map.has_key?(ex, "intensity_rpe")
      refute Map.has_key?(ex, "pnf")
      refute Map.has_key?(ex, "body_part")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature 6: Checkpoint typed MeasurementSpec
  # ---------------------------------------------------------------------------

  describe "Feature 6 — Checkpoint typed MeasurementSpec" do
    test "bare metric token emits typed MeasurementSpec map" do
      src =
        with_progress(
          "  CHECKPOINT \"Baseline\":\n    at 0 weeks\n    measure:\n      body_weight_kg\n"
        )

      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      cp = json["plan"]["progress"]["checkpoints"] |> List.first()
      m = cp["measurements"] |> List.first()
      assert m["metric"] == "body_weight_kg"
    end

    test "questionnaire metric with questionnaire field and note" do
      src =
        with_progress(
          "  CHECKPOINT \"Week 4\":\n    at 4 weeks\n    measure:\n      questionnaire_score questionnaire psqi note \"sleep quality\"\n"
        )

      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      cp = json["plan"]["progress"]["checkpoints"] |> List.first()
      m = cp["measurements"] |> List.first()
      assert m["metric"] == "questionnaire_score"
      assert m["questionnaire"] == "psqi"
      assert m["note"] == "sleep quality"
    end

    test "quoted string items preserved as plain strings (back-compat)" do
      src =
        with_progress(
          "  CHECKPOINT \"Baseline\":\n    at 0 weeks\n    measure:\n      \"photos\"\n      \"body_fat\"\n"
        )

      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      cp = json["plan"]["progress"]["checkpoints"] |> List.first()
      measurements = cp["measurements"]
      assert Enum.at(measurements, 0) == "photos"
      assert Enum.at(measurements, 1) == "body_fat"
    end

    test "mixes typed specs and plain strings" do
      src =
        with_progress(
          "  CHECKPOINT \"Mixed\":\n    at 4 weeks\n    measure:\n      body_weight_kg\n      \"photos\"\n      hrv_rmssd_ms\n"
        )

      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      cp = json["plan"]["progress"]["checkpoints"] |> List.first()
      measurements = cp["measurements"]
      assert length(measurements) == 3
      assert List.first(measurements)["metric"] == "body_weight_kg"
      assert Enum.at(measurements, 1) == "photos"
      assert Enum.at(measurements, 2)["metric"] == "hrv_rmssd_ms"
    end
  end

  # ---------------------------------------------------------------------------
  # Feature 7: Cardio intensity target min_bpm / max_bpm
  # ---------------------------------------------------------------------------

  describe "Feature 7 — Cardio intensity bpm min/max emission" do
    test "intensity bpm 150..170 emits target.min_bpm and target.max_bpm" do
      src =
        plan_header() <>
          "\n" <>
          phases_header() <>
          "        main:\n          cardio running continuous:\n            total 30 minutes\n            intensity bpm 150..170\n"

      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      intensity = act["prescription"]["intensity"]
      assert intensity != nil
      target = intensity["target"]
      assert target != nil
      assert target["min_bpm"] == 150
      assert target["max_bpm"] == 170
    end

    test "zone intensity does not emit target" do
      src =
        plan_header() <>
          "\n" <>
          phases_header() <>
          "        main:\n          cardio running continuous:\n            total 30 minutes\n            zone 2\n"

      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      intensity = act["prescription"]["intensity"]
      assert intensity["zone"] == 2
      refute Map.has_key?(intensity, "target")
    end

    test "intensity bpm 140..160 compiles to correct min/max values" do
      src =
        plan_header() <>
          "\n" <>
          phases_header() <>
          "        main:\n          cardio cycling continuous:\n            total 45 minutes\n            intensity bpm 140..160\n"

      assert {:ok, json, _repairs} = WplAi.to_wpl(src)
      act = get_first_activity(json)
      target = act["prescription"]["intensity"]["target"]
      assert target["min_bpm"] == 140
      assert target["max_bpm"] == 160
    end
  end
end
