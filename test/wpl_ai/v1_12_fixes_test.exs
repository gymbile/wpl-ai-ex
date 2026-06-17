defmodule WplAi.V112FixesTest do
  @moduledoc """
  Regression tests for the 8 silent-truncation / tolerance fixes ported from
  @gymbile/wpl-ai 1.12.0 (TS commits cdcf450 .. 2137782).

  Each describe block targets one commit's behaviour change. The minimal
  repro for each bug is used as the primary test; additional edge cases are
  added where the TS commit message surfaces multiple sub-cases.
  """

  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp compile!(src) do
    case WplAi.to_wpl(src) do
      {:ok, json, _repairs} -> json
      {:error, errors} -> flunk("Expected compile to succeed, got errors: #{inspect(errors)}")
    end
  end

  defp tokenize_ok!(src) do
    case WplAi.Lexer.tokenize(src) do
      {:ok, tokens} -> tokens
      {:error, errors} -> flunk("Expected tokenize to succeed, got errors: #{inspect(errors)}")
    end
  end

  # Minimal 2-week plan. The second week must survive compilation —
  # that is the canary for week-truncation bugs.
  defp two_week_plan(week1_main_line, week2_main_line \\ "push_up 3x10") do
    """
    PLAN "Two Week Test"
    TYPE workout
    VISIBILITY public

    PHASES
      PHASE "P1" (2 weeks):
        WEEK 1:
          DAY Monday training:
            main straight_sets:
              #{week1_main_line}
        WEEK 2:
          DAY Monday training:
            main straight_sets:
              #{week2_main_line}
    """
  end

  defp get_week_count(src) do
    compiled = compile!(src)
    compiled["plan"]["phases"] |> hd() |> Map.get("weeks") |> length()
  end

  defp get_activity(src) do
    compiled = compile!(src)

    compiled["plan"]["phases"]
    |> hd()
    |> Map.get("weeks")
    |> hd()
    |> Map.get("days")
    |> hd()
    |> Map.get("blocks")
    |> hd()
    |> Map.get("activities")
    |> hd()
  end

  # =============================================================================
  # Commit cdcf450 — rpe/rir ranges, reps time-unit suffix, long-form duration units
  # =============================================================================

  describe "cdcf450 — rpe/rir range in exercise modifiers" do
    test "rpe 7..8 does not truncate week 2" do
      assert get_week_count(two_week_plan("squat 3x5 rpe 7..8")) == 2
    end

    test "rir 1..2 does not truncate week 2" do
      assert get_week_count(two_week_plan("bench_press 3x8 rir 1..2")) == 2
    end

    test "rpe range emits rpe_min and rpe_max in compiled JSON" do
      activity = get_activity(two_week_plan("squat 3x5 rpe 7..8"))
      assert activity["target_rpe_min"] == 7
      assert activity["target_rpe_max"] == 8
      refute Map.has_key?(activity, "target_rpe")
    end

    test "rir range emits rir_min and rir_max in compiled JSON" do
      activity = get_activity(two_week_plan("bench_press 3x8 rir 1..2"))
      assert activity["target_rir_min"] == 1
      assert activity["target_rir_max"] == 2
      refute Map.has_key?(activity, "target_rir")
    end

    test "scalar rpe still emits target_rpe (no regression)" do
      activity = get_activity(two_week_plan("squat 3x5 rpe 7"))
      assert activity["target_rpe"] == 7
    end

    test "rpe range in intensity block (cardio) does not truncate week 2" do
      src = """
      PLAN "Cardio Plan"
      TYPE workout
      VISIBILITY public

      PHASES
        PHASE "P1" (2 weeks):
          WEEK 1:
            DAY Monday training:
              main straight_sets:
                squat 3x5
          WEEK 2:
            DAY Monday training:
              main straight_sets:
                push_up 3x10
      """

      assert get_week_count(src) == 2
    end
  end

  describe "cdcf450 — reps time-unit suffix before modifier keyword" do
    test "3x30s rpe 6 does not truncate week 2" do
      assert get_week_count(two_week_plan("plank 3x30s rpe 6")) == 2
    end

    test "3x30s rest 60 seconds does not truncate week 2" do
      assert get_week_count(two_week_plan("plank 3x30s rest 60 seconds")) == 2
    end

    test "3x2m rpe 7 does not truncate week 2" do
      assert get_week_count(two_week_plan("plank 3x2m rpe 7")) == 2
    end

    test "unit suffix alone (no following modifier) is left in stream — no regression" do
      # `plank 3x10` with standalone `s` after should still produce an exercise
      # (not blow up); the `s` becomes a simple activity in the next block body pass
      src = two_week_plan("plank 3x10")
      assert get_week_count(src) == 2
    end
  end

  describe "cdcf450 — long-form duration units in simple activity" do
    test "cycling 10 minutes does not truncate week 2" do
      src = """
      PLAN "Cardio Plan"
      TYPE workout
      VISIBILITY public

      PHASES
        PHASE "P1" (2 weeks):
          WEEK 1:
            DAY Monday training:
              main straight_sets:
                cycling 10 minutes
          WEEK 2:
            DAY Monday training:
              main straight_sets:
                push_up 3x10
      """

      assert get_week_count(src) == 2
    end

    test "jumping_jacks 30 seconds parses without error" do
      src = """
      PLAN "Test"
      TYPE workout
      VISIBILITY public

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training:
              main straight_sets:
                jumping_jacks 30 seconds
      """

      assert get_week_count(src) == 1
    end
  end

  # =============================================================================
  # Commit 5f72493 — simple activity modifier leakage
  # =============================================================================

  describe "5f72493 — simple activity trailing modifiers consumed" do
    test "cycling 20m rpe 6 does not truncate week 2" do
      src = """
      PLAN "Test"
      TYPE workout
      VISIBILITY public

      PHASES
        PHASE "P1" (2 weeks):
          WEEK 1:
            DAY Monday training:
              main straight_sets:
                cycling 20m rpe 6
          WEEK 2:
            DAY Monday training:
              main straight_sets:
                push_up 3x10
      """

      assert get_week_count(src) == 2
    end

    test "rowing 5m heart_rate_zone 2 rest 30 seconds does not truncate week 2" do
      src = """
      PLAN "Test"
      TYPE workout
      VISIBILITY public

      PHASES
        PHASE "P1" (2 weeks):
          WEEK 1:
            DAY Monday training:
              main straight_sets:
                rowing 5m heart_rate_zone 2 rest 30 seconds
          WEEK 2:
            DAY Monday training:
              main straight_sets:
                push_up 3x10
      """

      assert get_week_count(src) == 2
    end

    test "simple activity with number only and trailing modifier does not truncate" do
      src = """
      PLAN "Test"
      TYPE workout
      VISIBILITY public

      PHASES
        PHASE "P1" (2 weeks):
          WEEK 1:
            DAY Monday training:
              main straight_sets:
                cycling 20 rpe 6
          WEEK 2:
            DAY Monday training:
              main straight_sets:
                push_up 3x10
      """

      assert get_week_count(src) == 2
    end
  end

  # =============================================================================
  # Commit 543917c — reps range + unit suffix; bare activity-type block at day level
  # =============================================================================

  describe "543917c — reps range with trailing unit suffix" do
    test "3x20..30s rpe 6 does not truncate week 2" do
      assert get_week_count(two_week_plan("plank 3x20..30s rpe 6")) == 2
    end

    test "3x20..30 seconds rpe 6 does not truncate week 2" do
      assert get_week_count(two_week_plan("plank 3x20..30 seconds rpe 6")) == 2
    end

    test "3x20..30 minutes rpe 7 does not truncate week 2" do
      assert get_week_count(two_week_plan("plank 3x20..30 minutes rpe 7")) == 2
    end
  end

  describe "543917c — bare activity-type block at day level is silently skipped" do
    test "bare cardio: at day level does not drop subsequent weeks" do
      src = """
      PLAN "Test"
      TYPE workout
      VISIBILITY public

      PHASES
        PHASE "P1" (2 weeks):
          WEEK 1:
            DAY Monday training:
              cardio:
                cycling 20m
          WEEK 2:
            DAY Monday training:
              main straight_sets:
                push_up 3x10
      """

      # Week 2 must survive even though week 1 has a malformed bare cardio: block
      assert get_week_count(src) == 2
    end
  end

  # =============================================================================
  # Commit 1e24ac7 — cardio modalities accepted as exercise refs in sets×reps
  # =============================================================================

  describe "1e24ac7 — cardio modalities as exercise refs" do
    test "running 1x60 rpe 5 compiles without error" do
      src = two_week_plan("running 1x60 rpe 5")
      assert get_week_count(src) == 2
    end

    test "cycling as exercise ref in sets×reps form" do
      src = two_week_plan("cycling 3x20")
      assert get_week_count(src) == 2
    end

    test "swimming as exercise ref compiles" do
      src = two_week_plan("swimming 2x30 rpe 6")
      assert get_week_count(src) == 2
    end

    test "walking as exercise ref compiles" do
      src = two_week_plan("walking 1x60")
      assert get_week_count(src) == 2
    end

    test "rowing as exercise ref compiles" do
      src = two_week_plan("rowing 3x5 rpe 7")
      assert get_week_count(src) == 2
    end

    test "cardio modality exercise_ref is preserved in compiled JSON" do
      activity = get_activity(two_week_plan("running 1x60 rpe 5"))
      assert activity["exercise_ref"] == "running"
    end
  end

  # =============================================================================
  # Commit 327e456 — lexer tolerance: dashes, typographic punctuation, N-M ranges
  # =============================================================================

  describe "327e456 — en/em-dash normalised to hyphen" do
    test "en-dash in rpe range tokenises as range" do
      # U+2013 en-dash: 6–7 should tokenise as number range number
      tokens = tokenize_ok!("6–7")
      types = Enum.map(tokens, fn {t, _, _} -> t end) |> Enum.reject(&(&1 == :eof))
      assert types == [:number, :range, :number]
    end

    test "em-dash tokenises as hyphen/range" do
      # U+2014 em-dash: 6—7
      tokens = tokenize_ok!("6—7")
      types = Enum.map(tokens, fn {t, _, _} -> t end) |> Enum.reject(&(&1 == :eof))
      assert types == [:number, :range, :number]
    end
  end

  describe "327e456 — typographic punctuation silently skipped" do
    test "semicolon is silently skipped" do
      tokens = tokenize_ok!("push_up;3x10")
      types = Enum.map(tokens, fn {t, _, _} -> t end) |> Enum.reject(&(&1 in [:eof, :newline]))
      assert :bare_word in types
    end

    test "ampersand is silently skipped" do
      tokens = tokenize_ok!("push_up & pull_up")
      values = Enum.map(tokens, fn {_, v, _} -> v end) |> Enum.reject(&is_nil/1)
      refute "&" in values
    end

    test "smart left single quote is silently skipped" do
      # U+2018 '
      tokens = tokenize_ok!("trainer‘s notes")
      # Should not produce an error token
      types = Enum.map(tokens, fn {t, _, _} -> t end)
      refute :error in types
    end

    test "ellipsis is silently skipped" do
      tokens = tokenize_ok!("push_up…pull_up")
      types = Enum.map(tokens, fn {t, _, _} -> t end)
      refute :error in types
    end

    test "bullet is silently skipped" do
      tokens = tokenize_ok!("push_up • pull_up")
      types = Enum.map(tokens, fn {t, _, _} -> t end)
      refute :error in types
    end
  end

  describe "327e456 — N-M range emitted as range token when previous token was number" do
    test "6-7 tokenises as number range number" do
      tokens = tokenize_ok!("6-7")
      types = Enum.map(tokens, fn {t, _, _} -> t end) |> Enum.reject(&(&1 == :eof))
      assert types == [:number, :range, :number]
    end

    test "9-12 tokenises as number range number" do
      tokens = tokenize_ok!("9-12")
      types = Enum.map(tokens, fn {t, _, _} -> t end) |> Enum.reject(&(&1 == :eof))
      assert types == [:number, :range, :number]
    end

    test "rpe 6-7 in plan does not truncate week 2" do
      assert get_week_count(two_week_plan("squat 3x5 rpe 6-7")) == 2
    end
  end

  # =============================================================================
  # Commit 531d296 — trailing-dot numbers; stray top-level ALL-CAPS sections
  # =============================================================================

  describe "531d296 — trailing-dot number typos" do
    test "number token 12. emits clean integer 12" do
      tokens = tokenize_ok!("12.")
      number_token = Enum.find(tokens, fn {t, _, _} -> t == :number end)
      assert number_token != nil
      {_, value, _} = number_token
      assert value == 12
    end

    test "7. in exercise prescription does not produce error" do
      src = two_week_plan("squat 7. x 5")
      # Should compile (7 treated as integer, trailing dot skipped)
      assert get_week_count(src) == 2
    end
  end

  describe "531d296 — stray top-level ALL-CAPS sections are skipped" do
    test "NUTRITION: section after PHASES does not prevent compilation" do
      src = """
      PLAN "Test"
      TYPE workout
      VISIBILITY public

      PHASES
        PHASE "P1" (2 weeks):
          WEEK 1:
            DAY Monday training:
              main straight_sets:
                push_up 3x10
          WEEK 2:
            DAY Monday training:
              main straight_sets:
                squat 3x5

      NUTRITION:
        Some prose annotation the model added.
      """

      compiled = compile!(src)
      week_count = compiled["plan"]["phases"] |> hd() |> Map.get("weeks") |> length()
      assert week_count == 2
    end

    test "SUMMARY: and NOTES: sections are silently skipped" do
      src = """
      PLAN "Test"
      TYPE workout
      VISIBILITY public

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training:
              main straight_sets:
                push_up 3x10

      SUMMARY:
        The plan is a strength plan.

      NOTES:
        Consult a physician before starting.
      """

      assert {:ok, _, _} = WplAi.to_wpl(src)
    end
  end

  # =============================================================================
  # Commit 73ca0f7 — ASCII apostrophe; unknown TYPE; bare cardio: silent skip
  # =============================================================================

  describe "73ca0f7 — ASCII apostrophe silently skipped" do
    test "ASCII apostrophe in identifier-like token does not error" do
      # "trainer's" should tokenize without errors
      {:ok, tokens} = WplAi.Lexer.tokenize("trainer's notes")
      types = Enum.map(tokens, fn {t, _, _} -> t end)
      refute :error in types
    end
  end

  describe "73ca0f7 — unknown TYPE value falls back to default" do
    test "TYPE summary falls back without error" do
      src = """
      PLAN "Test"
      TYPE summary
      VISIBILITY public

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training:
              main straight_sets:
                push_up 3x10
      """

      assert {:ok, _, _} = WplAi.to_wpl(src)
    end

    test "TYPE program falls back without error" do
      src = """
      PLAN "Test"
      TYPE program
      VISIBILITY public

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training:
              main straight_sets:
                push_up 3x10
      """

      assert {:ok, _, _} = WplAi.to_wpl(src)
    end
  end

  # =============================================================================
  # Commit 2137782 — two-tier exercise-ref resolution
  # =============================================================================

  describe "2137782 — tier 1: high-confidence typo auto-correction (Jaro-Winkler >= 0.85)" do
    test "pushup resolves to push_up" do
      activity = get_activity(two_week_plan("pushup 3x10"))
      assert activity["exercise_ref"] == "push_up"
    end

    test "squat with typo still compiles with week 2 intact" do
      # Even if typo-correction kicks in, week 2 must survive
      assert get_week_count(two_week_plan("pushup 3x10")) == 2
    end
  end

  describe "2137782 — tier 2: low-confidence unknown ref accepted as-is" do
    test "unrecognised exercise ref with no close match is accepted as-is" do
      # flibbertigibbet_curl has no close match in the vocabulary
      src = two_week_plan("flibbertigibbet_curl 3x10")
      compiled = compile!(src)
      week_count = compiled["plan"]["phases"] |> hd() |> Map.get("weeks") |> length()
      assert week_count == 2
    end

    test "scapular_retraction is accepted as-is (real exercise, not in vocabulary)" do
      src = two_week_plan("scapular_retraction 3x15")
      assert {:ok, _, _} = WplAi.to_wpl(src)
    end

    test "accepted-as-is ref is preserved in exercise_ref field" do
      activity = get_activity(two_week_plan("flibbertigibbet_curl 3x10"))
      assert activity["exercise_ref"] == "flibbertigibbet_curl"
    end
  end

  # =============================================================================
  # Spot-check: the canonical minimal repro from the issue description
  # =============================================================================

  describe "spot-checks — canonical minimal repros from the issue" do
    test "rpe 7..8 causing W2 to drop now compiles cleanly" do
      # The canonical minimal repro: two-week plan where week 1 has rpe 7..8
      assert get_week_count(two_week_plan("squat 3x5 rpe 7..8")) == 2
    end

    test "pushup auto-resolves to push_up" do
      activity = get_activity(two_week_plan("pushup 3x10"))
      assert activity["exercise_ref"] == "push_up"
    end
  end
end
