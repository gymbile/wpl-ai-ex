defmodule WplAi.ParserTest do
  use ExUnit.Case, async: true

  alias WplAi.Parser
  alias WplAi.AST

  # Minimal valid plan header — used as a base for composing snippets.
  @minimal_header ~S"""
  PLAN "Test Plan"
  TYPE workout
  """

  defp parse!(source) do
    assert {:ok, doc, _repairs} = Parser.parse(source)
    doc
  end

  describe "parse/1 - minimal plan" do
    test "minimal plan returns a Document struct with header" do
      doc = parse!(@minimal_header)
      assert %AST.Document{} = doc
      assert %AST.Header{} = doc.header
      assert doc.header.name == "Test Plan"
      assert doc.header.type == :workout
    end

    test "phases defaults to empty list when omitted" do
      doc = parse!(@minimal_header)
      assert doc.phases == [] or is_nil(doc.phases)
    end

    test "optional sections are nil when omitted" do
      doc = parse!(@minimal_header)
      assert is_nil(doc.goals)
      assert is_nil(doc.personalization)
      assert is_nil(doc.athlete_thresholds)
    end
  end

  describe "parse/1 - plan header attributes" do
    test "parses visibility, difficulty, tags, and language" do
      source = ~S"""
      PLAN "Full Header"
      TYPE nutrition
      VISIBILITY public
      DIFFICULTY advanced
      TAGS fat_loss, cardio
      LANGUAGE en
      """

      doc = parse!(source)
      assert doc.header.visibility == :public
      assert doc.header.difficulty == :advanced
      assert doc.header.tags == ["fat_loss", "cardio"]
      assert doc.header.language == "en"
    end
  end

  describe "parse/1 - GOALS section" do
    test "parses a primary goal with a target" do
      source = ~S"""
      PLAN "Goals Plan"
      TYPE workout

      GOALS
        GOAL primary muscle_gain:
          target weight 5 kg absolute
      """

      doc = parse!(source)
      assert length(doc.goals) == 1
      [goal] = doc.goals
      assert goal.priority == :primary
      assert goal.category == "muscle_gain"
      assert goal.target.metric == "weight"
      assert goal.target.value == 5
      assert goal.target.unit == "kg"
      assert goal.target.measurement_type == :absolute
    end

    test "parses a secondary goal" do
      source = ~S"""
      PLAN "Multi Goals"
      TYPE workout

      GOALS
        GOAL primary strength:
          target weight 100 kg absolute
        GOAL secondary endurance:
          target duration 60 minutes relative
      """

      doc = parse!(source)
      assert length(doc.goals) == 2
      priorities = Enum.map(doc.goals, & &1.priority)
      assert :primary in priorities
      assert :secondary in priorities
    end
  end

  describe "parse/1 - PERSONALIZATION section" do
    test "parses a simple WHEN rule with a replace action" do
      source = ~S"""
      PLAN "Personalized"
      TYPE workout

      PERSONALIZATION
        RULES
          WHEN injury contains knee:
            replace squat -> wall_sit
      """

      doc = parse!(source)
      assert length(doc.personalization.rules) == 1
      [rule] = doc.personalization.rules
      assert rule.condition.type == :simple
      assert rule.condition.field == "injury"
      assert rule.condition.op == :contains
      assert rule.condition.value == "knee"
    end

    test "parses compound AND condition" do
      source = ~S"""
      PLAN "Compound Cond"
      TYPE workout

      PERSONALIZATION
        RULES
          WHEN age > 50 AND fitness == beginner:
            reduce reps 20%
      """

      doc = parse!(source)
      [rule] = doc.personalization.rules
      assert rule.condition.type == :compound
      assert rule.condition.operator == :and
      assert length(rule.condition.conditions) == 2
    end
  end

  describe "parse/1 - PHASES section" do
    test "parses a single phase with one week and one day" do
      source = ~S"""
      PLAN "Phased Plan"
      TYPE workout

      PHASES
        PHASE "Foundation" (2 weeks):
          WEEK 1:
            DAY Monday training 45m "Upper Body":
              main straight_sets:
                push_up 3x10
      """

      doc = parse!(source)
      assert length(doc.phases) == 1
      [phase] = doc.phases
      assert phase.name == "Foundation"
      assert length(phase.weeks) == 1
      [week] = phase.weeks
      assert week.number == 1
      assert length(week.days) == 1
    end

    test "parses multiple phases" do
      source = ~S"""
      PLAN "Multi Phase"
      TYPE workout

      PHASES
        PHASE "Foundation" (2 weeks):
          WEEK 1:
            DAY Monday training 30m "Day A":
              main straight_sets:
                push_up 3x10
        PHASE "Build" (4 weeks):
          WEEK 1:
            DAY Monday training 45m "Day B":
              main straight_sets:
                squat 4x8
      """

      doc = parse!(source)
      assert length(doc.phases) == 2
      names = Enum.map(doc.phases, & &1.name)
      assert "Foundation" in names
      assert "Build" in names
    end
  end

  describe "parse/1 - exercise activities" do
    test "parses sets x reps and RPE" do
      source = ~S"""
      PLAN "Exercise Plan"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Strength":
              main straight_sets:
                bench_press 3x8 rpe 8
      """

      doc = parse!(source)
      [phase] = doc.phases
      [week] = phase.weeks
      [day] = week.days
      [block] = day.blocks
      [exercise] = block.activities
      assert exercise.exercise_ref == "bench_press"
      assert exercise.sets == 3
      assert exercise.rpe == 8
    end

    test "parses rep range (reps as tuple)" do
      source = ~S"""
      PLAN "Rep Range"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day":
              main straight_sets:
                push_up 3x8..12
      """

      doc = parse!(source)
      [phase] = doc.phases
      [week] = phase.weeks
      [day] = week.days
      [block] = day.blocks
      [exercise] = block.activities
      assert exercise.sets == 3
      assert is_tuple(exercise.reps) or exercise.reps == {8, 12}
    end

    test "parses rest duration" do
      source = ~S"""
      PLAN "Rest Plan"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day":
              main straight_sets:
                squat 3x5 rest 90 seconds
      """

      doc = parse!(source)
      [phase] = doc.phases
      [week] = phase.weeks
      [day] = week.days
      [block] = day.blocks
      [exercise] = block.activities
      assert exercise.rest != nil
    end
  end

  describe "parse/1 - cardio activities" do
    test "parses continuous cardio with modality and zone" do
      source = ~S"""
      PLAN "Cardio Plan"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Cardio":
              main:
                cardio rowing continuous:
                  total 20 minutes
                  zone 2
      """

      doc = parse!(source)
      [phase] = doc.phases
      [week] = phase.weeks
      [day] = week.days
      [block] = day.blocks
      [activity] = block.activities
      assert %AST.Cardio{} = activity
      assert activity.modality == "rowing"
      assert activity.cardio_type == :continuous
      assert activity.total_duration.value == 20
      assert activity.zone == 2
    end
  end

  describe "parse/1 - warmup and cooldown blocks" do
    test "parses warmup and cooldown in the same day" do
      source = ~S"""
      PLAN "Full Day"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 60m "Full":
              warmup:
                jumping_jack 5m
              main straight_sets:
                squat 3x10
              cooldown:
                hamstring_stretch 30s x2
      """

      doc = parse!(source)
      [phase] = doc.phases
      [week] = phase.weeks
      [day] = week.days
      block_types = Enum.map(day.blocks, & &1.type)
      assert :warmup in block_types
      assert :main in block_types
      assert :cooldown in block_types
    end
  end

  describe "parse/1 - ATHLETE_THRESHOLDS section" do
    test "parses athlete thresholds" do
      source = ~S"""
      PLAN "Athlete Plan"
      TYPE workout

      ATHLETE_THRESHOLDS
        hr_max 185
        ftp 280 watts
        body_weight 80 kg
      """

      doc = parse!(source)
      assert %AST.AthleteThresholds{} = doc.athlete_thresholds
      assert doc.athlete_thresholds.hr_max_bpm == 185
      assert doc.athlete_thresholds.ftp_watts == 280
      assert doc.athlete_thresholds.body_weight_kg == 80.0
    end
  end

  describe "parse/1 - comments inside DSL" do
    test "comments are ignored and do not affect parsing" do
      source = ~S"""
      # This is a plan-level comment
      PLAN "Comment Plan"
      TYPE workout
      # Another comment
      """

      doc = parse!(source)
      assert doc.header.name == "Comment Plan"
    end
  end

  describe "parse/1 - quoted strings" do
    test "plan name with spaces parses correctly" do
      doc =
        parse!(~S"""
        PLAN "My Strength Plan 2024"
        TYPE workout
        """)

      assert doc.header.name == "My Strength Plan 2024"
    end
  end

  describe "parse/1 - error handling" do
    test "missing TYPE returns an error" do
      assert {:error, _errors} =
               Parser.parse(~S"""
               PLAN "No Type"
               """)
    end

    test "missing PLAN keyword returns an error" do
      assert {:error, _errors} =
               Parser.parse(~S"""
               TYPE workout
               """)
    end

    # Common LLM mistake (surfaced by wpl-eval's truncation analysis): the
    # model writes a "summary" version of a plan where each WEEK has
    # one-line entries like `Monday: ...` instead of full DAY blocks.
    # Pre-parity with TS 1.11.0 this was silently discarded; we now flag
    # it with a repair_hint so an agentic loop can regenerate the
    # offending week.
    test "WEEK with inline-summary content emits :week_has_no_valid_days with repair_hint" do
      source = ~S"""
      PLAN "Trunc"
      TYPE workout

      PHASES
        PHASE "Foundation" (4 weeks):
          WEEK 1:
            DAY Monday training 45m "Real day":
              main:
                push_up 3x10
          WEEK 2:
            Monday: walk/run intervals (slightly longer)
            Wednesday: walk/run intervals (slightly longer)
          WEEK 3:
            DAY Tuesday training 45m "Recovers":
              main:
                push_up 3x10
      """

      assert {:error, errors} = Parser.parse(source)
      day_err = Enum.find(errors, &(&1.type == :week_has_no_valid_days))
      assert day_err != nil
      assert day_err.message =~ "WEEK 2"
      assert day_err.message =~ "DAY"
      assert day_err.repair_hint != nil
      assert day_err.repair_hint.action == :add_days
      assert day_err.repair_hint.parent_name == "Week 2"
      assert day_err.repair_hint.context_dsl_example =~ "DAY Monday"
    end

    test "legitimately empty WEEK (placeholder week) parses without error" do
      # Periodisation scaffolds commonly declare empty weeks. The next
      # top-level keyword (WEEK / PHASE) signals end-of-body without any
      # erroneous inline content; the parser must accept this.
      source = ~S"""
      PLAN "Empty weeks"
      TYPE workout

      PHASES
        PHASE "Foundation" (3 weeks):
          WEEK 1:
            DAY Monday training 45m "Real":
              main:
                push_up 3x10
          WEEK 2:
          WEEK 3:
      """

      doc = parse!(source)
      [phase] = doc.phases
      assert length(phase.weeks) == 3
      assert Enum.at(phase.weeks, 1).days == []
      assert Enum.at(phase.weeks, 2).days == []
    end
  end

  # ==========================================================================
  # A2 — Fail-closed safety sections
  # ==========================================================================

  describe "parse/1 - fail-closed safety sections" do
    test "REQUIREMENTS: typo is a hard parse error, not a silent skip" do
      source = ~S"""
      PLAN "Bad Plan"
      TYPE workout
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day 1":
              main straight_sets:
                push_up 3x10
      REQUIREMENTS:
        contraindication knee_pain -> exclude
      """

      assert {:error, errors} = Parser.parse(source)

      assert Enum.any?(errors, fn e ->
               message = if is_map(e), do: Map.get(e, :message) || "", else: ""
               String.contains?(message, "REQUIREMENTS")
             end)
    end

    test "CONTRAINDICATIONS: typo is a hard parse error" do
      source = ~S"""
      PLAN "Bad Plan"
      TYPE workout
      CONTRAINDICATIONS:
        knee_pain -> exclude
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day 1":
              main straight_sets:
                push_up 3x10
      """

      assert {:error, _errors} = Parser.parse(source)
    end

    test "SAFETY_NOTES: is a hard parse error (safety-adjacent prefix)" do
      source = ~S"""
      PLAN "Bad Plan"
      TYPE workout
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day 1":
              main straight_sets:
                push_up 3x10
      SAFETY_NOTES:
        Some notes.
      """

      assert {:error, _errors} = Parser.parse(source)
    end

    test "NOTES: (non-safety) is silently skipped with a repair" do
      source = ~S"""
      PLAN "Clean Plan"
      TYPE workout
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day 1":
              main straight_sets:
                push_up 3x10
      NOTES:
        Some prose.
      """

      assert {:ok, _doc, repairs} = Parser.parse(source)
      assert Enum.any?(repairs, &(&1.type == :skipped_section))
    end
  end

  # ==========================================================================
  # A2 — Strict contraindications
  # ==========================================================================

  describe "parse/1 - strict contraindications" do
    test "unknown contraindication severity is a hard parse error" do
      source = ~S"""
      PLAN "Bad Plan"
      TYPE workout
      REQUIRES
        contraindication knee_pain severity extreme action exclude
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day 1":
              main straight_sets:
                push_up 3x10
      """

      assert {:error, errors} = Parser.parse(source)
      assert length(errors) >= 1
    end

    test "unknown contraindication action is a hard parse error" do
      source = ~S"""
      PLAN "Bad Plan"
      TYPE workout
      REQUIRES
        contraindication knee_pain action banish
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day 1":
              main straight_sets:
                push_up 3x10
      """

      assert {:error, errors} = Parser.parse(source)
      assert length(errors) >= 1
    end

    test "valid contraindication with known severity and action parses cleanly" do
      source = ~S"""
      PLAN "Good Plan"
      TYPE workout
      REQUIRES
        contraindication knee_pain severity high action modify
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day 1":
              main straight_sets:
                push_up 3x10
      """

      assert {:ok, doc, _repairs} = Parser.parse(source)
      contra = doc.requirements.contraindications |> hd()
      assert contra.severity == :high
      assert contra.action == :modify
    end

    test "unknown action in legacy arrow form is a hard parse error" do
      source = ~S"""
      PLAN "Bad Plan"
      TYPE workout
      REQUIRES
        contraindication knee_pain -> smash
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day 1":
              main straight_sets:
                push_up 3x10
      """

      assert {:error, errors} = Parser.parse(source)
      assert length(errors) >= 1
    end

    test "valid action in legacy arrow form parses cleanly" do
      source = ~S"""
      PLAN "Good Plan"
      TYPE workout
      REQUIRES
        contraindication knee_pain -> exclude
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day 1":
              main straight_sets:
                push_up 3x10
      """

      assert {:ok, doc, _repairs} = Parser.parse(source)
      contra = doc.requirements.contraindications |> hd()
      assert contra.action == :exclude
    end
  end
end
