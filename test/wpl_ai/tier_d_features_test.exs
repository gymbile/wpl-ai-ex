defmodule WplAi.TierDFeaturesTest do
  use ExUnit.Case, async: true

  alias WplAi

  # ---------------------------------------------------------------------------
  # Feature 1: Phase.type enum
  # ---------------------------------------------------------------------------

  @phase_type_source ~S"""
  PLAN "Phase Type Test"
  TYPE workout

  PHASES
    PHASE "Cycle 1" intensification (2 weeks):
      WEEK 1:
        DAY Monday training 60m "Day 1":
          main straight_sets:
            squat 3x5 weight 80% rm
      WEEK 2:
        DAY Tuesday training 60m "Day 2":
          main straight_sets:
            deadlift 3x3 weight 85% rm
    PHASE "Recovery" deload (1 weeks):
      WEEK 1:
        DAY Wednesday training 30m "Light day":
          main straight_sets:
            squat 2x5 weight 50% rm
    PHASE "Base block" (2 weeks):
      WEEK 1:
        DAY Monday training 45m "Day 1":
          main straight_sets:
            squat 3x8 weight 60% rm
  """

  describe "Phase.type enum (Feature 1)" do
    test "emits phase.type when DSL specifies a periodization role" do
      assert {:ok, json} = WplAi.to_wpl(@phase_type_source)

      phases = json["plan"]["phases"]
      assert phases |> Enum.at(0) |> Map.get("type") == "intensification"
    end

    test "emits phase.type deload for deload phase" do
      assert {:ok, json} = WplAi.to_wpl(@phase_type_source)

      phases = json["plan"]["phases"]
      assert phases |> Enum.at(1) |> Map.get("type") == "deload"
    end

    test "omits phase.type when not specified in DSL" do
      assert {:ok, json} = WplAi.to_wpl(@phase_type_source)

      phases = json["plan"]["phases"]
      refute Map.has_key?(Enum.at(phases, 2), "type")
    end

    test "accepts all valid phase type tokens" do
      for phase_type <-
            ~w(accumulation intensification realization deload base build peak recovery transition) do
        source = """
        PLAN "Test"
        TYPE workout

        PHASES
          PHASE "P" #{phase_type} (1 weeks):
            WEEK 1:
              DAY Monday rest "D":
        """

        assert {:ok, json} = WplAi.to_wpl(source)
        phases = json["plan"]["phases"]
        assert hd(phases)["type"] == phase_type, "expected type #{phase_type}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Feature 2: Week.is_deload
  # ---------------------------------------------------------------------------

  @week_deload_source ~S"""
  PLAN "Week Deload Test"
  TYPE workout

  PHASES
    PHASE "Block 1" accumulation (4 weeks):
      WEEK 1 "Lead-in":
        DAY Monday training 60m "Day 1":
          main straight_sets:
            squat 4x6 weight 70% rm
      WEEK 4 deload "Deload":
        DAY Monday training 30m "Light day":
          main straight_sets:
            squat 2x5 weight 50% rm
  """

  describe "Week.is_deload (Feature 2)" do
    test "emits is_deload true when deload token present" do
      assert {:ok, json} = WplAi.to_wpl(@week_deload_source)

      weeks =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")

      assert Enum.at(weeks, 1)["is_deload"] == true
    end

    test "omits is_deload when deload token absent" do
      assert {:ok, json} = WplAi.to_wpl(@week_deload_source)

      weeks =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")

      refute Map.has_key?(Enum.at(weeks, 0), "is_deload")
    end

    test "deload token accepted before optional name string" do
      source = ~S"""
      PLAN "T"
      TYPE workout

      PHASES
        PHASE "P" (1 weeks):
          WEEK 1 deload:
            DAY Monday rest "D":
      """

      assert {:ok, json} = WplAi.to_wpl(source)
      week = json["plan"]["phases"] |> hd() |> Map.get("weeks") |> hd()
      assert week["is_deload"] == true
    end
  end

  # ---------------------------------------------------------------------------
  # Feature 3: SubPlanActivity
  # ---------------------------------------------------------------------------

  @sub_plan_source ~S"""
  PLAN "Sub Plan Test"
  TYPE workout

  PHASES
    PHASE "P1" (1 weeks):
      WEEK 1 "Week 1":
        DAY Monday training 60m "Squat day":
          warmup:
            subplan plan_warmup_full_body "Standard warmup"
          main straight_sets:
            squat 4x5 weight 80% rm rest 180 seconds
          cooldown:
            subplan plan_cooldown_mobility
  """

  describe "SubPlanActivity (Feature 3)" do
    test "emits sub_plan activity with sub_plan_ref and name in warmup" do
      assert {:ok, json} = WplAi.to_wpl(@sub_plan_source)

      warmup_block =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> Enum.find(&(&1["type"] == "warmup"))

      activity = warmup_block["activities"] |> hd()
      assert activity["type"] == "sub_plan"
      assert activity["sub_plan_ref"] == "plan_warmup_full_body"
      assert activity["name"] == "Standard warmup"
      assert Map.has_key?(activity, "id")
    end

    test "emits sub_plan activity without name when omitted in cooldown" do
      assert {:ok, json} = WplAi.to_wpl(@sub_plan_source)

      cooldown_block =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> Enum.find(&(&1["type"] == "cooldown"))

      activity = cooldown_block["activities"] |> hd()
      assert activity["type"] == "sub_plan"
      assert activity["sub_plan_ref"] == "plan_cooldown_mobility"
      refute Map.has_key?(activity, "name")
    end

    test "sub_plan id follows sub_plan_N pattern" do
      assert {:ok, json} = WplAi.to_wpl(@sub_plan_source)

      warmup_block =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> Enum.find(&(&1["type"] == "warmup"))

      activity = warmup_block["activities"] |> hd()
      assert String.starts_with?(activity["id"], "sub_plan_")
    end
  end
end
