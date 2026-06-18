defmodule WplAi.ExerciseMatcherTest do
  use ExUnit.Case, async: true

  alias WplAi.ExerciseMatcher

  # ---------------------------------------------------------------------------
  # known?/1
  # ---------------------------------------------------------------------------

  describe "known?/1" do
    test "returns true for an exact canonical reference" do
      assert ExerciseMatcher.known?("push_up") == true
    end

    test "returns true for another canonical exercise" do
      assert ExerciseMatcher.known?("bench_press") == true
    end

    test "returns true for a lower-body exercise" do
      assert ExerciseMatcher.known?("squat") == true
    end

    test "returns true for a full-body exercise" do
      assert ExerciseMatcher.known?("turkish_getup") == true
    end

    test "recognises the v1.13 vocabulary additions (rehab + variants)" do
      # Every entry below appeared as an unknown_exercise_ref in the
      # wpl-eval v0.2.0 corpus. Adding them removes the head-of-cascade
      # error for those trials and lets the orchestrator focus on real
      # structural issues rather than vocabulary gaps.
      v113_additions = ~w(
        inverted_row hangboard
        scapular_retraction external_rotation internal_rotation
        prone_T prone_Y prone_W
        pelvic_tilt diaphragmatic_breathing
      )

      for name <- v113_additions do
        assert ExerciseMatcher.known?(name) == true,
               "expected #{name} to be a known exercise"
      end
    end

    test "returns false for a spaced variant (not canonical)" do
      assert ExerciseMatcher.known?("push up") == false
    end

    test "returns false for a completely unknown reference" do
      assert ExerciseMatcher.known?("zxqwerty_exercise") == false
    end

    test "returns false for empty string" do
      assert ExerciseMatcher.known?("") == false
    end
  end

  # ---------------------------------------------------------------------------
  # suggest/1
  # ---------------------------------------------------------------------------

  describe "suggest/1" do
    test "suggests push_up for pushup (missing underscore)" do
      suggestions = ExerciseMatcher.suggest("pushup")
      assert "push_up" in suggestions
    end

    test "suggests squat for squats (plural)" do
      suggestions = ExerciseMatcher.suggest("squats")
      assert "squat" in suggestions
    end

    test "suggests bench_press for benchpress (missing underscore)" do
      suggestions = ExerciseMatcher.suggest("benchpress")
      assert "bench_press" in suggestions
    end

    test "returns empty list for completely nonsensical input" do
      assert ExerciseMatcher.suggest("xyzabc123nonsense") == []
    end

    test "returns at most 3 suggestions" do
      suggestions = ExerciseMatcher.suggest("squat")
      assert length(suggestions) <= 3
    end

    test "returns suggestions in descending similarity order" do
      # "squat" itself is known, so this tests suggest with a near-match
      suggestions = ExerciseMatcher.suggest("squats")
      # first suggestion should be the best match
      assert List.first(suggestions) == "squat"
    end
  end

  # ---------------------------------------------------------------------------
  # best_match/1
  # ---------------------------------------------------------------------------

  describe "best_match/1" do
    test "returns {:ok, push_up} for pushup (high similarity)" do
      assert {:ok, "push_up"} = ExerciseMatcher.best_match("pushup")
    end

    test "returns :no_match for nonsensical input" do
      assert ExerciseMatcher.best_match("xyz") == :no_match
    end

    test "returns {:ok, match} for close multi-word exercise" do
      # "benchpress" should match "bench_press" with > 0.85 similarity
      assert {:ok, "bench_press"} = ExerciseMatcher.best_match("benchpress")
    end

    test "returns :no_match for empty string" do
      assert ExerciseMatcher.best_match("") == :no_match
    end
  end

  # ---------------------------------------------------------------------------
  # validate/1
  # ---------------------------------------------------------------------------

  describe "validate/1" do
    test "returns :ok for a known exercise" do
      assert ExerciseMatcher.validate("push_up") == :ok
    end

    test "returns {:unknown, suggestions} for an unknown but close exercise" do
      result = ExerciseMatcher.validate("pushup")
      assert {:unknown, suggestions} = result
      assert "push_up" in suggestions
    end

    test "returns {:unknown, []} for completely unknown exercise with no close matches" do
      result = ExerciseMatcher.validate("zxqwerty_exercise")
      assert {:unknown, []} = result
    end

    test "returns :ok for front_squat" do
      assert ExerciseMatcher.validate("front_squat") == :ok
    end

    test "returns :ok for overhead_press" do
      assert ExerciseMatcher.validate("overhead_press") == :ok
    end
  end

  # ---------------------------------------------------------------------------
  # all_exercises/0 and exercises_by_category/0
  # ---------------------------------------------------------------------------

  describe "all_exercises/0" do
    test "returns a non-empty list" do
      exercises = ExerciseMatcher.all_exercises()
      assert length(exercises) > 0
    end

    test "contains canonical references without spaces" do
      exercises = ExerciseMatcher.all_exercises()

      Enum.each(exercises, fn ex ->
        refute String.contains?(ex, " "), "exercise #{ex} contains a space"
      end)
    end

    test "all exercises are strings" do
      exercises = ExerciseMatcher.all_exercises()

      Enum.each(exercises, fn ex ->
        assert is_binary(ex)
      end)
    end
  end

  describe "exercises_by_category/0" do
    test "returns a map with the expected category keys" do
      categories = ExerciseMatcher.exercises_by_category()
      assert Map.has_key?(categories, :upper_body)
      assert Map.has_key?(categories, :lower_body)
      assert Map.has_key?(categories, :core)
      assert Map.has_key?(categories, :cardio_warmup)
      assert Map.has_key?(categories, :stretching)
      assert Map.has_key?(categories, :full_body)
      assert Map.has_key?(categories, :rehab_mobility)
    end

    test "rehab_mobility category is non-empty and contains scapular_retraction" do
      categories = ExerciseMatcher.exercises_by_category()
      rehab = Map.fetch!(categories, :rehab_mobility)
      assert length(rehab) > 0
      assert "scapular_retraction" in rehab
    end

    test "each category list is non-empty" do
      categories = ExerciseMatcher.exercises_by_category()

      Enum.each(categories, fn {_category, exercises} ->
        assert length(exercises) > 0
      end)
    end

    test "union of all categories equals all_exercises" do
      by_cat = ExerciseMatcher.exercises_by_category()
      all_via_category = by_cat |> Map.values() |> List.flatten() |> Enum.sort()
      all_direct = ExerciseMatcher.all_exercises() |> Enum.sort()
      assert all_via_category == all_direct
    end
  end
end
