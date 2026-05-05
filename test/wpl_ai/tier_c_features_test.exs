defmodule WplAi.TierCFeaturesTest do
  use ExUnit.Case, async: true

  alias WplAi

  # ---------------------------------------------------------------------------
  # Feature 1: per-kg macros + kcal_per_kg + multiplier_of_tdee
  # ---------------------------------------------------------------------------

  @macros_per_kg_source ~S"""
  PLAN "Macro Test"
  TYPE nutrition

  PHASES
    PHASE "P1" (1 weeks):
      WEEK 1:
        DAY Monday rest "D1":
          nutrition:
            nutrition daily_target:
              protein 1.6 .. 2.2 g_per_kg
              carbs 4 .. 6 g_per_kg
              fat 0.7 .. 1.0 g_per_kg
              calories 0.95 .. 1.05 multiplier_of_tdee
  """

  @kcal_per_kg_source ~S"""
  PLAN "Kcal Per Kg Test"
  TYPE nutrition

  PHASES
    PHASE "P1" (1 weeks):
      WEEK 1:
        DAY Monday rest "D1":
          nutrition:
            nutrition daily_target:
              protein 150 .. 180 g
              calories 30 .. 35 kcal_per_kg
  """

  describe "per-kg macros (Feature 1)" do
    test "emits g_per_kg unit for protein, carbs, fat" do
      assert {:ok, json} = WplAi.to_wpl(@macros_per_kg_source)

      nutrition_block =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> Enum.find(&(&1["type"] == "nutrition"))

      act = nutrition_block["activities"] |> hd()
      macros = act["prescription"]["macros"]

      assert macros["protein"] == %{"min" => 1.6, "max" => 2.2, "unit" => "g_per_kg"}
      assert macros["carbs"] == %{"min" => 4.0, "max" => 6.0, "unit" => "g_per_kg"}
      assert macros["fat"] == %{"min" => 0.7, "max" => 1.0, "unit" => "g_per_kg"}
    end

    test "emits multiplier_of_tdee unit for calories" do
      assert {:ok, json} = WplAi.to_wpl(@macros_per_kg_source)

      nutrition_block =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> Enum.find(&(&1["type"] == "nutrition"))

      act = nutrition_block["activities"] |> hd()
      calories = act["prescription"]["calories"]

      assert calories == %{"min" => 0.95, "max" => 1.05, "unit" => "multiplier_of_tdee"}
    end

    test "emits kcal_per_kg unit for calories" do
      assert {:ok, json} = WplAi.to_wpl(@kcal_per_kg_source)

      nutrition_block =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> Enum.find(&(&1["type"] == "nutrition"))

      act = nutrition_block["activities"] |> hd()
      calories = act["prescription"]["calories"]

      assert calories == %{"min" => 30.0, "max" => 35.0, "unit" => "kcal_per_kg"}
    end

    test "keeps default g unit when no suffix given" do
      source = ~S"""
      PLAN "Default Units"
      TYPE nutrition

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday rest "D1":
              nutrition:
                nutrition daily_target:
                  protein 150 .. 180 g
                  carbs 200 .. 250 g
                  fat 50 .. 70 g
                  calories 2000 .. 2500
      """

      assert {:ok, json} = WplAi.to_wpl(source)

      nutrition_block =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> Enum.find(&(&1["type"] == "nutrition"))

      act = nutrition_block["activities"] |> hd()
      macros = act["prescription"]["macros"]
      calories = act["prescription"]["calories"]

      assert macros["protein"]["unit"] == "g"
      assert macros["carbs"]["unit"] == "g"
      assert macros["fat"]["unit"] == "g"
      assert calories["unit"] == "kcal"
    end
  end

  # ---------------------------------------------------------------------------
  # Feature 2: Weight.percentage_bodyweight
  # ---------------------------------------------------------------------------

  @percentage_bw_source ~S"""
  PLAN "BW Load Test"
  TYPE workout

  PHASES
    PHASE "P1" (1 weeks):
      WEEK 1:
        DAY Monday training "D1":
          main straight_sets:
            goblet_squat 3x12 weight 33% bw
  """

  @percentage_bodyweight_source ~S"""
  PLAN "BW Load Test 2"
  TYPE workout

  PHASES
    PHASE "P1" (1 weeks):
      WEEK 1:
        DAY Monday training "D1":
          main straight_sets:
            goblet_squat 3x12 weight 50% bodyweight
  """

  describe "Weight.percentage_bodyweight (Feature 2)" do
    test "emits percentage_bodyweight type for `weight N% bw`" do
      assert {:ok, json} = WplAi.to_wpl(@percentage_bw_source)

      main_block =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> Enum.find(&(&1["type"] == "main"))

      ex = main_block["activities"] |> hd()
      weight = ex["prescription"]["weight"]

      assert weight["type"] == "percentage_bodyweight"
      assert weight["value"] == 33
    end

    test "emits percentage_bodyweight type for `weight N% bodyweight`" do
      assert {:ok, json} = WplAi.to_wpl(@percentage_bodyweight_source)

      main_block =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> Enum.find(&(&1["type"] == "main"))

      ex = main_block["activities"] |> hd()
      weight = ex["prescription"]["weight"]

      assert weight["type"] == "percentage_bodyweight"
      assert weight["value"] == 50
    end

    test "existing weight forms still work" do
      source = ~S"""
      PLAN "Weight Forms"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training "D1":
              main straight_sets:
                bench_press 3x5 weight 80 kg
      """

      assert {:ok, json} = WplAi.to_wpl(source)

      main_block =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> Enum.find(&(&1["type"] == "main"))

      ex = main_block["activities"] |> hd()
      weight = ex["prescription"]["weight"]

      assert weight["type"] == "absolute"
      assert weight["value"] == 80
      assert weight["unit"] == "kg"
    end

    test "existing percentage_1rm form still works" do
      source = ~S"""
      PLAN "1RM Test"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training "D1":
              main straight_sets:
                squat 3x5 weight 85 percentage_1rm
      """

      assert {:ok, json} = WplAi.to_wpl(source)

      main_block =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")
        |> Enum.find(&(&1["type"] == "main"))

      ex = main_block["activities"] |> hd()
      weight = ex["prescription"]["weight"]

      assert weight["type"] == "percentage_1rm"
    end
  end
end
