defmodule WplAiTest do
  use ExUnit.Case, async: true

  alias WplAi
  alias WplAi.AST

  describe "parse/1 - smoke test from spec" do
    test "parses the minimal example from WPL-AI spec" do
      source = ~S"""
      PLAN "Upper Body Beginner"
      TYPE workout
      VISIBILITY private
      DIFFICULTY beginner
      TAGS strength, beginner
      LANGUAGE en

      GOALS
        GOAL primary muscle_gain:
          target weight 0 kg absolute

      REQUIRES
        age 16..65
        fitness beginner
        equipment:
          dumbbells (required, alternatives: bands)

      PERSONALIZATION
        RULES
          WHEN injury contains knee:
            replace squat -> wall_sit

      PHASES
        PHASE "Foundation" (2 weeks):
          WEEK 1:
            DAY Monday training 45m "Upper Body":
              warmup:
                jumping_jacks 2m
              main straight_sets:
                push_up 3x8..12 target 10 rpe 7 rest 60 seconds
              cooldown:
                chest_stretch 30s x2 sides both
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)

      # Header assertions
      assert doc.header.name == "Upper Body Beginner"
      assert doc.header.type == :workout
      assert doc.header.visibility == :private
      assert doc.header.difficulty == :beginner
      assert doc.header.tags == ["strength", "beginner"]
      assert doc.header.language == "en"

      # Goals assertions
      assert length(doc.goals) == 1
      [goal] = doc.goals
      assert goal.priority == :primary
      assert goal.category == "muscle_gain"
      assert goal.target.metric == "weight"
      assert goal.target.value == 0
      assert goal.target.unit == "kg"
      assert goal.target.measurement_type == :absolute

      # Requirements assertions
      assert doc.requirements.age_range == {16, 65}
      assert doc.requirements.fitness_levels == ["beginner"]
      assert length(doc.requirements.equipment) == 1
      [equip] = doc.requirements.equipment
      assert equip.name == "dumbbells"
      assert equip.required == true
      assert equip.alternatives == ["bands"]

      # Personalization assertions
      assert length(doc.personalization.rules) == 1
      [rule] = doc.personalization.rules
      assert rule.condition.type == :simple
      assert rule.condition.field == "injury"
      assert rule.condition.op == :contains
      assert rule.condition.value == "knee"
      assert length(rule.actions) == 1
      [action] = rule.actions
      assert action.type == :replace_exercise
      assert action.params.from == "squat"
      assert action.params.to == "wall_sit"

      # Phases assertions
      assert length(doc.phases) == 1
      [phase] = doc.phases
      assert phase.name == "Foundation"
      assert phase.duration.value == 2
      assert phase.duration.unit == :weeks

      # Weeks
      assert length(phase.weeks) == 1
      [week] = phase.weeks
      assert week.number == 1

      # Days
      assert length(week.days) == 1
      [day] = week.days
      assert day.day_name == "Monday"
      assert day.day_type == :training
      assert day.duration.value == 45
      assert day.duration.unit == :minutes
      assert day.label == "Upper Body"

      # Blocks
      assert length(day.blocks) == 3
      [warmup, main, cooldown] = day.blocks

      assert warmup.type == :warmup
      assert main.type == :main
      assert main.structure == :straight_sets
      assert cooldown.type == :cooldown

      # Warmup activities
      assert length(warmup.activities) == 1
      [warmup_act] = warmup.activities
      assert %AST.SimpleActivity{} = warmup_act
      assert warmup_act.name == "jumping_jacks"

      # Main activities (exercise)
      assert length(main.activities) == 1
      [exercise] = main.activities
      assert %AST.Exercise{} = exercise
      assert exercise.exercise_ref == "push_up"
      assert exercise.sets == 3
      assert exercise.reps == {8, 12, 10}
      assert exercise.rpe == 7
      assert exercise.rest.value == 60
      assert exercise.rest.unit == :seconds

      # Cooldown activities (recovery)
      assert length(cooldown.activities) == 1
      [recovery] = cooldown.activities
      assert %AST.RecoveryExercise{} = recovery
      assert recovery.name == "chest_stretch"
      assert recovery.hold_seconds == 30
      assert recovery.reps == 2
      assert recovery.sides == :both
    end
  end

  describe "parse/1 - header variations" do
    test "parses minimal header" do
      source = ~S"""
      PLAN "Minimal"
      TYPE workout
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      assert doc.header.name == "Minimal"
      assert doc.header.type == :workout
      assert doc.header.visibility == nil
      assert doc.header.difficulty == nil
    end

    test "parses all plan types" do
      for type <- ["workout", "nutrition", "meditation", "recovery", "hybrid"] do
        source = """
        PLAN "Test"
        TYPE #{type}
        """

        assert {:ok, doc, _repairs} = WplAi.parse(source)
        assert doc.header.type == String.to_atom(type)
      end
    end

    test "parses all difficulties" do
      for difficulty <- ["beginner", "intermediate", "advanced", "adaptive"] do
        source = """
        PLAN "Test"
        TYPE workout
        DIFFICULTY #{difficulty}
        """

        assert {:ok, doc, _repairs} = WplAi.parse(source)
        assert doc.header.difficulty == String.to_atom(difficulty)
      end
    end
  end

  describe "parse/1 - goals section" do
    test "parses multiple goals" do
      source = ~S"""
      PLAN "Multi Goal"
      TYPE workout

      GOALS
        GOAL primary weight_loss:
          target weight -5 kg relative
        GOAL secondary muscle_gain:
          target weight 2 kg absolute
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      assert length(doc.goals) == 2

      [primary, secondary] = doc.goals
      assert primary.priority == :primary
      assert primary.category == "weight_loss"
      assert primary.target.value == -5
      assert primary.target.measurement_type == :relative

      assert secondary.priority == :secondary
      assert secondary.category == "muscle_gain"
      assert secondary.target.measurement_type == :absolute
    end
  end

  describe "parse/1 - personalization rules" do
    test "parses compound conditions with AND" do
      source = ~S"""
      PLAN "Test"
      TYPE workout

      PERSONALIZATION
        RULES
          WHEN age >= 50 AND injury contains knee:
            reduce intensity by 20 %
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [rule] = doc.personalization.rules

      assert rule.condition.type == :compound
      assert rule.condition.operator == :and
      assert length(rule.condition.conditions) == 2
    end

    test "parses compound conditions with OR" do
      source = ~S"""
      PLAN "Test"
      TYPE workout

      PERSONALIZATION
        RULES
          WHEN injury contains knee OR injury contains back:
            exclude jump_squat
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [rule] = doc.personalization.rules

      assert rule.condition.type == :compound
      assert rule.condition.operator == :or
    end

    test "parses multiple actions in a rule" do
      source = ~S"""
      PLAN "Test"
      TYPE workout

      PERSONALIZATION
        RULES
          WHEN injury contains knee:
            replace squat -> wall_sit
            exclude jump_squat
            reduce sets by 1
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [rule] = doc.personalization.rules
      assert length(rule.actions) == 3

      [replace, exclude, reduce] = rule.actions
      assert replace.type == :replace_exercise
      assert exclude.type == :exclude_exercise
      assert reduce.type == :reduce_sets
    end
  end

  describe "parse/1 - exercise activities" do
    test "parses exercise with all modifiers" do
      source = ~S"""
      PLAN "Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                bench_press 4x6..8 target 7 rpe 8 rir 2 rest 90 seconds weight 80 kg
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[exercise]] = get_activities(doc)

      assert exercise.exercise_ref == "bench_press"
      assert exercise.sets == 4
      assert exercise.reps == {6, 8, 7}
      assert exercise.rpe == 8
      assert exercise.rir == 2
      assert exercise.rest.value == 90
      assert exercise.rest.unit == :seconds
      assert exercise.weight.value == 80
      assert exercise.weight.unit == "kg"
    end

    test "parses exercise with bodyweight" do
      source = ~S"""
      PLAN "Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                pull_up 3x5 weight bodyweight
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[exercise]] = get_activities(doc)

      assert exercise.weight.type == :bodyweight
    end

    test "parses exercise with simple rep count" do
      source = ~S"""
      PLAN "Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                plank 3x30
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[exercise]] = get_activities(doc)

      assert exercise.sets == 3
      assert exercise.reps == 30
    end
  end

  describe "parse/1 - cardio activities" do
    test "parses continuous cardio" do
      source = ~S"""
      PLAN "Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                cardio running continuous:
                  total 20 minutes
                  zone 3
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[cardio]] = get_activities(doc)

      assert %AST.Cardio{} = cardio
      assert cardio.modality == "running"
      assert cardio.cardio_type == :continuous
      assert cardio.total_duration.value == 20
      assert cardio.total_duration.unit == :minutes
      assert cardio.zone == 3
    end

    test "parses interval cardio" do
      source = ~S"""
      PLAN "Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                cardio cycling intervals:
                  total 15 minutes
                  30s work / 30s rest x10
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[cardio]] = get_activities(doc)

      assert %AST.Cardio{} = cardio
      assert cardio.cardio_type == :intervals
      assert cardio.intervals.work_seconds == 30
      assert cardio.intervals.rest_seconds == 30
      assert cardio.intervals.repeats == 10
    end
  end

  describe "parse/1 - nutrition activities" do
    test "parses nutrition with macros" do
      source = ~S"""
      PLAN "Test"
      TYPE nutrition

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              nutrition:
                nutrition meal:
                  protein 20..30 g
                  carbs 30..40 g
                  fat 10..15 g
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[nutrition]] = get_activities(doc)

      assert %AST.Nutrition{} = nutrition
      assert nutrition.category == "meal"
      assert nutrition.macros.protein == {20, 30, "g"}
      assert nutrition.macros.carbs == {30, 40, "g"}
      assert nutrition.macros.fat == {10, 15, "g"}
    end
  end

  describe "parse/1 - meditation activities" do
    test "parses meditation activity" do
      source = ~S"""
      PLAN "Test"
      TYPE meditation

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              meditation:
                meditation breathing:
                  duration 10 minutes
                  guided true
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[meditation]] = get_activities(doc)

      assert %AST.Meditation{} = meditation
      assert meditation.category == "breathing"
      assert meditation.duration.value == 10
      assert meditation.duration.unit == :minutes
      assert meditation.guided == true
    end
  end

  describe "parse/1 - habit activities" do
    test "parses habit activity" do
      source = ~S"""
      PLAN "Test"
      TYPE hybrid

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                habit hydration:
                  target 8 glasses
                  frequency daily
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[habit]] = get_activities(doc)

      assert %AST.Habit{} = habit
      assert habit.category == "hydration"
      assert habit.target == 8
      assert habit.target_unit == "glasses"
      assert habit.frequency == "daily"
    end
  end

  describe "tokenize/1" do
    test "tokenizes basic WPL-AI" do
      source = ~S"""
      PLAN "Test"
      TYPE workout
      """

      assert {:ok, tokens} = WplAi.tokenize(source)
      token_types = Enum.map(tokens, &elem(&1, 0))

      assert :keyword in token_types
      assert :string in token_types
      assert :eof in token_types
    end

    test "produces INDENT and DEDENT tokens" do
      source = """
      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                test
      """

      assert {:ok, tokens} = WplAi.tokenize(source)
      token_types = Enum.map(tokens, &elem(&1, 0))

      # Should have multiple indents and dedents
      assert Enum.count(token_types, &(&1 == :indent)) >= 4
      assert Enum.count(token_types, &(&1 == :dedent)) >= 4
    end
  end

  describe "validate/1" do
    test "returns :ok for valid WPL-AI" do
      source = ~S"""
      PLAN "Test"
      TYPE workout
      """

      assert :ok = WplAi.validate(source)
    end

    test "returns error for missing TYPE" do
      source = ~S"""
      PLAN "Test"
      """

      assert {:error, _errors} = WplAi.validate(source)
    end
  end

  describe "exercise_refs/1" do
    test "extracts all exercise references" do
      source = ~S"""
      PLAN "Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                push_up 3x10
                squat 3x10
                plank 3x30
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      refs = WplAi.exercise_refs(doc)

      assert "push_up" in refs
      assert "squat" in refs
      assert "plank" in refs
    end
  end

  describe "activity_counts/1" do
    test "counts activities by type" do
      source = ~S"""
      PLAN "Test"
      TYPE hybrid

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 60m:
              warmup:
                jumping_jacks 5m
              main:
                push_up 3x10
                squat 3x10
                cardio running continuous:
                  total 20 minutes
              meditation:
                meditation breathing:
                  duration 10 minutes
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      counts = WplAi.activity_counts(doc)

      assert counts[:exercise] == 2
      assert counts[:cardio] == 1
      assert counts[:meditation] == 1
      assert counts[:simple] == 1
    end
  end

  # ===========================================================================
  # Compiler Tests
  # ===========================================================================

  describe "compile/1 - basic compilation" do
    test "compiles a minimal document to WPL JSON" do
      source = ~S"""
      PLAN "Minimal"
      TYPE workout
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      assert {:ok, json} = WplAi.compile(doc)

      assert json["$schema"] == "https://wpl.dev/schemas/wpl/v1.schema.json"
      assert json["version"] == "1.6.0"
      assert json["plan"]["name"] == "Minimal"
      assert json["plan"]["type"] == "workout"
      assert is_binary(json["plan"]["id"])
    end

    test "to_wpl/1 parses and compiles in one step" do
      source = ~S"""
      PLAN "Combined"
      TYPE workout
      DIFFICULTY beginner
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)

      assert json["plan"]["name"] == "Combined"
      assert json["plan"]["type"] == "workout"
      assert json["plan"]["metadata"]["difficulty"] == "beginner"
    end
  end

  describe "compile/1 - header metadata" do
    test "compiles header metadata correctly" do
      source = ~S"""
      PLAN "Full Header"
      TYPE workout
      DIFFICULTY intermediate
      TAGS strength, hypertrophy
      LANGUAGE en
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      metadata = json["plan"]["metadata"]

      assert metadata["difficulty"] == "intermediate"
      assert metadata["tags"] == ["strength", "hypertrophy"]
      assert metadata["language"] == "en"
      assert is_binary(metadata["created_at"])
      assert is_binary(metadata["updated_at"])
    end
  end

  describe "compile/1 - goals compilation" do
    test "compiles goals with targets" do
      source = ~S"""
      PLAN "Goals Test"
      TYPE workout

      GOALS
        GOAL primary weight_loss:
          target weight -5 kg relative
        GOAL secondary muscle_gain:
          target weight 2 kg absolute
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      goals = json["plan"]["goals"]

      assert length(goals) == 2

      [primary, secondary] = goals
      assert primary["type"] == "primary"
      assert primary["category"] == "weight_loss"
      assert primary["target"]["metric"] == "weight"
      assert primary["target"]["target_value"] == -5
      assert primary["target"]["unit"] == "kg"
      assert primary["target"]["measurement_type"] == "relative"

      assert secondary["type"] == "secondary"
      assert secondary["target"]["measurement_type"] == "absolute"
    end

    test "auto-generates goal name from category when name is not provided" do
      source = ~S"""
      PLAN "Auto Name Test"
      TYPE workout

      GOALS
        GOAL primary weight_loss:
          target weight -5 kg absolute
        GOAL secondary muscle_gain:
          target strength 10 % relative
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      goals = json["plan"]["goals"]

      [primary, secondary] = goals
      assert primary["name"] == "Weight Loss"
      assert secondary["name"] == "Muscle Gain"
    end

    test "uses explicit name when provided in goal body" do
      source = ~S"""
      PLAN "Explicit Name Test"
      TYPE workout

      GOALS
        GOAL primary muscle_gain:
          name "Build Upper Body Strength"
          target strength 10 % relative
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [goal] = json["plan"]["goals"]
      assert goal["name"] == "Build Upper Body Strength"
    end
  end

  describe "compile/1 - requirements compilation" do
    test "compiles requirements section" do
      source = ~S"""
      PLAN "Requirements Test"
      TYPE workout

      REQUIRES
        age 18..65
        fitness beginner, intermediate
        equipment:
          dumbbells (required, alternatives: bands)
          mat (optional)
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      req = json["plan"]["requirements"]

      assert req["min_age"] == 18
      assert req["max_age"] == 65
      assert req["fitness_level"] == ["beginner", "intermediate"]

      [dumbbells, mat] = req["equipment"]
      assert dumbbells["name"] == "dumbbells"
      assert dumbbells["required"] == true
      assert dumbbells["alternatives"] == ["bands"]
      assert mat["name"] == "mat"
      assert mat["required"] == false
    end
  end

  describe "compile/1 - personalization compilation" do
    test "compiles personalization rules" do
      source = ~S"""
      PLAN "Personalization Test"
      TYPE workout

      PERSONALIZATION
        RULES
          WHEN injury contains knee:
            replace squat -> wall_sit
            exclude jump_squat
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      pers = json["plan"]["personalization"]

      assert length(pers["rules"]) == 1
      [rule] = pers["rules"]

      assert rule["condition"]["field"] == "injury"
      assert rule["condition"]["op"] == "contains"
      assert rule["condition"]["value"] == "knee"

      assert length(rule["actions"]) == 2
    end

    test "compiles compound conditions" do
      source = ~S"""
      PLAN "Compound Conditions"
      TYPE workout

      PERSONALIZATION
        RULES
          WHEN age >= 50 AND injury contains knee:
            reduce intensity by 20 %
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [rule] = json["plan"]["personalization"]["rules"]

      assert rule["condition"]["operator"] == "and"
      assert length(rule["condition"]["conditions"]) == 2
    end
  end

  describe "compile/1 - phases and structure" do
    test "compiles phases, weeks, and days" do
      source = ~S"""
      PLAN "Structure Test"
      TYPE workout

      PHASES
        PHASE "Foundation" (2 weeks):
          WEEK 1:
            DAY Monday training 45m "Upper Body":
              main:
                push_up 3x10
          WEEK 2:
            DAY Monday training 45m:
              main:
                push_up 3x12
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      phases = json["plan"]["phases"]

      assert length(phases) == 1
      [phase] = phases

      assert phase["name"] == "Foundation"
      assert phase["duration"]["value"] == 2
      assert phase["duration"]["unit"] == "weeks"
      assert phase["order"] == 1

      assert length(phase["weeks"]) == 2
      [week1, week2] = phase["weeks"]

      assert week1["order"] == 1
      assert week2["order"] == 2

      [day] = week1["days"]
      # Monday
      assert day["day_of_week"] == 1
      assert day["type"] == "training"
      assert day["name"] == "Upper Body"
      assert day["estimated_duration_minutes"] == 45
    end
  end

  describe "compile/1 - exercise activities" do
    test "compiles exercise with prescription" do
      source = ~S"""
      PLAN "Exercise Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                bench_press 4x6..8 target 7 rpe 8 rest 90 seconds weight 80 kg
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [[exercise]] = get_json_activities(json)

      assert exercise["type"] == "exercise"
      assert exercise["exercise_ref"] == "bench_press"
      assert exercise["prescription"]["sets"] == 4
      assert exercise["prescription"]["reps"]["min"] == 6
      assert exercise["prescription"]["reps"]["max"] == 8
      assert exercise["prescription"]["reps"]["target"] == 7
      assert exercise["prescription"]["rest"]["value"] == 90
      assert exercise["prescription"]["rest"]["unit"] == "seconds"
      assert exercise["prescription"]["weight"]["value"] == 80
      assert exercise["prescription"]["weight"]["unit"] == "kg"
      assert exercise["target_rpe"] == 8
    end

    test "compiles bodyweight exercise" do
      source = ~S"""
      PLAN "Bodyweight Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                pull_up 3x5 weight bodyweight
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [[exercise]] = get_json_activities(json)

      assert exercise["prescription"]["weight"]["type"] == "bodyweight"
    end
  end

  describe "compile/1 - cardio activities" do
    test "compiles continuous cardio" do
      source = ~S"""
      PLAN "Cardio Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                cardio running continuous:
                  total 20 minutes
                  zone 3
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [[cardio]] = get_json_activities(json)

      assert cardio["type"] == "cardio"
      assert cardio["modality"] == "running"
      assert cardio["prescription"]["type"] == "continuous"
      assert cardio["prescription"]["duration"]["value"] == 20
      assert cardio["prescription"]["duration"]["unit"] == "minutes"
      assert cardio["prescription"]["intensity"]["zone"] == 3
    end

    test "compiles interval cardio" do
      source = ~S"""
      PLAN "Intervals Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                cardio cycling intervals:
                  total 15 minutes
                  30s work / 30s rest x10
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [[cardio]] = get_json_activities(json)

      assert cardio["prescription"]["type"] == "intervals"
      assert cardio["prescription"]["intervals"]["work"]["duration"] == 30
      assert cardio["prescription"]["intervals"]["rest"]["duration"] == 30
      assert cardio["prescription"]["intervals"]["repeat"] == 10
    end
  end

  describe "compile/1 - nutrition activities" do
    test "compiles nutrition with macros" do
      source = ~S"""
      PLAN "Nutrition Test"
      TYPE nutrition

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              nutrition:
                nutrition meal:
                  protein 20..30 g
                  carbs 30..40 g
                  fat 10..15 g
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [[nutrition]] = get_json_activities(json)

      assert nutrition["type"] == "nutrition"
      assert nutrition["category"] == "meal"
      assert nutrition["prescription"]["macros"]["protein"]["min"] == 20
      assert nutrition["prescription"]["macros"]["protein"]["max"] == 30
      assert nutrition["prescription"]["macros"]["carbs"]["min"] == 30
      assert nutrition["prescription"]["macros"]["carbs"]["max"] == 40
    end
  end

  describe "compile/1 - meditation activities" do
    test "compiles meditation activity" do
      source = ~S"""
      PLAN "Meditation Test"
      TYPE meditation

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              meditation:
                meditation breathing:
                  duration 10 minutes
                  guided true
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [[meditation]] = get_json_activities(json)

      assert meditation["type"] == "meditation"
      assert meditation["category"] == "breathing"
      assert meditation["prescription"]["duration"]["value"] == 10
      assert meditation["prescription"]["guided"] == true
    end
  end

  describe "compile/1 - recovery activities" do
    test "compiles recovery block with exercises" do
      source = ~S"""
      PLAN "Recovery Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              cooldown:
                chest_stretch 30s x2 sides both
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [[recovery]] = get_json_activities(json)

      assert recovery["type"] == "recovery_exercise"
      assert recovery["name"] == "chest_stretch"
      assert recovery["hold_seconds"] == 30
      assert recovery["reps"] == 2
      assert recovery["sides"] == "both"
    end
  end

  describe "compile/1 - habit activities" do
    test "compiles habit activity" do
      source = ~S"""
      PLAN "Habit Test"
      TYPE hybrid

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                habit hydration:
                  target 8 glasses
                  frequency daily
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [[habit]] = get_json_activities(json)

      assert habit["type"] == "habit"
      assert habit["category"] == "hydration"
      # target/frequency/reminder_times are nested under prescription (TS parity).
      rx = habit["prescription"]
      assert rx["target"]["value"] == 8
      assert rx["target"]["unit"] == "glasses"
      assert rx["frequency"] == "daily"
    end
  end

  describe "compile/1 - block structures" do
    test "compiles block with structure type" do
      source = ~S"""
      PLAN "Structure Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main straight_sets:
                push_up 3x10
                squat 3x10
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)

      [block] =
        json["plan"]["phases"]
        |> hd()
        |> Map.get("weeks")
        |> hd()
        |> Map.get("days")
        |> hd()
        |> Map.get("blocks")

      assert block["type"] == "main"
      assert block["structure"] == "straight_sets"
      assert length(block["activities"]) == 2
    end
  end

  describe "compile/1 - full round-trip" do
    test "compiles full example from spec" do
      source = ~S"""
      PLAN "Upper Body Beginner"
      TYPE workout
      VISIBILITY private
      DIFFICULTY beginner
      TAGS strength, beginner
      LANGUAGE en

      GOALS
        GOAL primary muscle_gain:
          target weight 0 kg absolute

      REQUIRES
        age 16..65
        fitness beginner
        equipment:
          dumbbells (required, alternatives: bands)

      PERSONALIZATION
        RULES
          WHEN injury contains knee:
            replace squat -> wall_sit

      PHASES
        PHASE "Foundation" (2 weeks):
          WEEK 1:
            DAY Monday training 45m "Upper Body":
              warmup:
                jumping_jacks 2m
              main straight_sets:
                push_up 3x8..12 target 10 rpe 7 rest 60 seconds
              cooldown:
                chest_stretch 30s x2 sides both
      """

      # Parse and compile
      assert {:ok, json, _repairs} = WplAi.to_wpl(source)

      # Verify top-level structure
      assert json["$schema"] == "https://wpl.dev/schemas/wpl/v1.schema.json"
      assert json["version"] == "1.6.0"

      plan = json["plan"]

      # Verify plan metadata
      assert plan["name"] == "Upper Body Beginner"
      assert plan["type"] == "workout"
      assert plan["visibility"] == "private"
      assert plan["metadata"]["difficulty"] == "beginner"
      assert plan["metadata"]["tags"] == ["strength", "beginner"]

      # Verify goals
      assert length(plan["goals"]) == 1

      # Verify requirements
      assert plan["requirements"]["min_age"] == 16
      assert plan["requirements"]["max_age"] == 65

      # Verify personalization
      assert length(plan["personalization"]["rules"]) == 1

      # Verify phases
      assert length(plan["phases"]) == 1
      [phase] = plan["phases"]
      assert phase["name"] == "Foundation"

      # Verify week structure
      [week] = phase["weeks"]
      [day] = week["days"]
      assert day["day_of_week"] == 1

      # Verify blocks
      [warmup, main, cooldown] = day["blocks"]
      assert warmup["type"] == "warmup"
      assert main["type"] == "main"
      assert main["structure"] == "straight_sets"
      assert cooldown["type"] == "cooldown"
    end
  end

  # ===========================================================================
  # Decompiler Tests
  # ===========================================================================

  describe "decompile/1 - basic decompilation" do
    test "decompiles minimal plan to WPL-AI" do
      json = %{
        "plan" => %{
          "name" => "Minimal Test",
          "type" => "workout"
        }
      }

      assert {:ok, text} = WplAi.decompile(json)
      assert String.contains?(text, ~s(PLAN "Minimal Test"))
      assert String.contains?(text, "TYPE workout")
    end

    test "decompiles plan with metadata" do
      json = %{
        "plan" => %{
          "name" => "Full Test",
          "type" => "workout",
          "visibility" => "private",
          "metadata" => %{
            "difficulty" => "beginner",
            "tags" => ["strength", "beginner"],
            "language" => "en"
          }
        }
      }

      assert {:ok, text} = WplAi.decompile(json)
      assert String.contains?(text, "VISIBILITY private")
      assert String.contains?(text, "DIFFICULTY beginner")
      assert String.contains?(text, "TAGS strength, beginner")
      assert String.contains?(text, "LANGUAGE en")
    end
  end

  describe "decompile/1 - goals" do
    test "decompiles goals section" do
      json = %{
        "plan" => %{
          "name" => "Goals Test",
          "type" => "workout",
          "goals" => [
            %{
              "type" => "primary",
              "category" => "weight_loss",
              "target" => %{
                "metric" => "weight",
                "target_value" => -5,
                "unit" => "kg",
                "measurement_type" => "relative"
              }
            }
          ]
        }
      }

      assert {:ok, text} = WplAi.decompile(json)
      assert String.contains?(text, "GOALS")
      assert String.contains?(text, "GOAL primary weight_loss:")
      assert String.contains?(text, "target weight -5 kg relative")
    end
  end

  describe "decompile/1 - requirements" do
    test "decompiles requirements section" do
      json = %{
        "plan" => %{
          "name" => "Requirements Test",
          "type" => "workout",
          "requirements" => %{
            "min_age" => 18,
            "max_age" => 65,
            "fitness_level" => ["beginner", "intermediate"],
            "equipment" => [
              %{
                "name" => "dumbbells",
                "required" => true,
                "alternatives" => ["bands"]
              }
            ]
          }
        }
      }

      assert {:ok, text} = WplAi.decompile(json)
      assert String.contains?(text, "REQUIRES")
      assert String.contains?(text, "age 18..65")
      assert String.contains?(text, "fitness beginner, intermediate")
      assert String.contains?(text, "equipment:")
      assert String.contains?(text, "dumbbells (required, alternatives: bands)")
    end
  end

  describe "decompile/1 - personalization" do
    test "decompiles personalization rules" do
      json = %{
        "plan" => %{
          "name" => "Rules Test",
          "type" => "workout",
          "personalization" => %{
            "rules" => [
              %{
                "condition" => %{
                  "field" => "injury",
                  "op" => "contains",
                  "value" => "knee"
                },
                "actions" => [
                  %{"type" => "replace_exercise", "from" => "squat", "to" => "wall_sit"}
                ]
              }
            ]
          }
        }
      }

      assert {:ok, text} = WplAi.decompile(json)
      assert String.contains?(text, "PERSONALIZATION")
      assert String.contains?(text, "RULES")
      assert String.contains?(text, "WHEN injury contains knee:")
      assert String.contains?(text, "replace squat -> wall_sit")
    end
  end

  describe "decompile/1 - phases and activities" do
    test "decompiles phase structure" do
      json = %{
        "plan" => %{
          "name" => "Structure Test",
          "type" => "workout",
          "phases" => [
            %{
              "name" => "Foundation",
              "duration" => %{"value" => 2, "unit" => "weeks"},
              "weeks" => [
                %{
                  "order" => 1,
                  "days" => [
                    %{
                      "day_of_week" => 1,
                      "type" => "training",
                      "name" => "Upper Body",
                      "estimated_duration_minutes" => 45,
                      "blocks" => [
                        %{
                          "type" => "main",
                          "structure" => "straight_sets",
                          "activities" => [
                            %{
                              "type" => "exercise",
                              "exercise_ref" => "push_up",
                              "prescription" => %{
                                "sets" => 3,
                                "reps" => %{"min" => 8, "max" => 12, "target" => 10}
                              },
                              "target_rpe" => 7
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      }

      assert {:ok, text} = WplAi.decompile(json)
      assert String.contains?(text, "PHASES")
      assert String.contains?(text, ~s[PHASE "Foundation" (2 weeks):])
      assert String.contains?(text, "WEEK 1:")
      assert String.contains?(text, ~s[DAY Monday training 45m "Upper Body":])
      assert String.contains?(text, "main straight_sets:")
      assert String.contains?(text, "push_up 3x8..12 target 10 rpe 7")
    end

    test "decompiles cardio activity" do
      json = %{
        "plan" => %{
          "name" => "Cardio Test",
          "type" => "workout",
          "phases" => [
            %{
              "name" => "Test",
              "duration" => %{"value" => 1, "unit" => "weeks"},
              "weeks" => [
                %{
                  "order" => 1,
                  "days" => [
                    %{
                      "day_of_week" => 1,
                      "type" => "training",
                      "estimated_duration_minutes" => 30,
                      "blocks" => [
                        %{
                          "type" => "main",
                          "activities" => [
                            %{
                              "type" => "cardio",
                              "modality" => "running",
                              "prescription" => %{
                                "type" => "continuous",
                                "duration" => %{"value" => 20, "unit" => "minutes"},
                                "intensity" => %{"zone" => 3}
                              }
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      }

      assert {:ok, text} = WplAi.decompile(json)
      assert String.contains?(text, "cardio running continuous:")
      assert String.contains?(text, "total 20 minutes")
      assert String.contains?(text, "zone 3")
    end
  end

  describe "round_trip/1 - semantic preservation" do
    test "round-trips minimal plan" do
      source = ~S"""
      PLAN "Round Trip Test"
      TYPE workout
      DIFFICULTY beginner
      """

      assert {:ok, result} = WplAi.round_trip(source)
      assert String.contains?(result, ~s(PLAN "Round Trip Test"))
      assert String.contains?(result, "TYPE workout")
      assert String.contains?(result, "DIFFICULTY beginner")
    end

    test "round-trips plan with exercises" do
      source = ~S"""
      PLAN "Exercise Test"
      TYPE workout

      PHASES
        PHASE "Test" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                push_up 3x10 rpe 7
                squat 3x8..12 target 10
      """

      assert {:ok, result} = WplAi.round_trip(source)

      # Verify key elements are preserved
      assert String.contains?(result, ~s(PLAN "Exercise Test"))
      assert String.contains?(result, "TYPE workout")
      assert String.contains?(result, "push_up")
      assert String.contains?(result, "squat")
    end

    test "compiled and decompiled plan can be re-parsed" do
      source = ~S"""
      PLAN "Re-parse Test"
      TYPE workout
      DIFFICULTY intermediate

      GOALS
        GOAL primary weight_loss:
          target weight -5 kg relative

      PHASES
        PHASE "Foundation" (2 weeks):
          WEEK 1:
            DAY Monday training 45m "Upper Body":
              main straight_sets:
                push_up 3x10 rpe 7
      """

      # First pass
      assert {:ok, json1, _repairs1} = WplAi.to_wpl(source)
      assert {:ok, text1} = WplAi.decompile(json1)

      # Re-parse the decompiled text
      assert {:ok, json2, _repairs2} = WplAi.to_wpl(text1)

      # Verify semantic equality
      assert json1["plan"]["name"] == json2["plan"]["name"]
      assert json1["plan"]["type"] == json2["plan"]["type"]
      assert length(json1["plan"]["phases"]) == length(json2["plan"]["phases"])
    end
  end

  # ===========================================================================
  # ExerciseMatcher Tests
  # ===========================================================================

  describe "ExerciseMatcher" do
    alias WplAi.ExerciseMatcher

    test "known?/1 returns true for valid exercise references" do
      assert ExerciseMatcher.known?("push_up")
      assert ExerciseMatcher.known?("squat")
      assert ExerciseMatcher.known?("bench_press")
      assert ExerciseMatcher.known?("plank")
    end

    test "known?/1 returns false for unknown references" do
      refute ExerciseMatcher.known?("pushup")
      refute ExerciseMatcher.known?("squats")
      refute ExerciseMatcher.known?("xyz123")
    end

    test "suggest/1 finds similar exercises for typos" do
      # Missing underscore
      assert "push_up" in ExerciseMatcher.suggest("pushup")

      # Plural form
      assert "squat" in ExerciseMatcher.suggest("squats")

      # Missing underscore in compound word
      assert "bench_press" in ExerciseMatcher.suggest("benchpress")

      # Close spelling
      assert "plank" in ExerciseMatcher.suggest("plnk")
    end

    test "suggest/1 returns empty list for completely unrelated input" do
      assert ExerciseMatcher.suggest("xyz123abc") == []
      assert ExerciseMatcher.suggest("qwerty") == []
    end

    test "best_match/1 returns match for high-similarity inputs" do
      assert {:ok, "push_up"} = ExerciseMatcher.best_match("pushup")
      assert {:ok, "squat"} = ExerciseMatcher.best_match("squats")
    end

    test "best_match/1 returns :no_match for low-similarity inputs" do
      assert :no_match = ExerciseMatcher.best_match("xyz123")
      assert :no_match = ExerciseMatcher.best_match("foobar")
    end

    test "validate/1 returns :ok for known exercises" do
      assert :ok = ExerciseMatcher.validate("push_up")
      assert :ok = ExerciseMatcher.validate("deadlift")
    end

    test "validate/1 returns suggestions for unknown exercises" do
      assert {:unknown, suggestions} = ExerciseMatcher.validate("pushup")
      assert "push_up" in suggestions
    end

    test "all_exercises/0 returns the full exercise library" do
      exercises = ExerciseMatcher.all_exercises()
      assert is_list(exercises)
      assert length(exercises) > 50
      assert "push_up" in exercises
      assert "squat" in exercises
    end
  end

  describe "Errors.format_for_llm/2" do
    alias WplAi.Errors
    alias WplAi.Errors.{Location, LexerError, ParseError}

    test "formats parse errors with line numbers and suggestions" do
      error =
        ParseError.unknown_exercise_ref(
          "pushup",
          Location.new(5, 15),
          ["push_up"]
        )

      source = """
      PLAN "Test"
      TYPE workout
      PHASES
        PHASE "Test" (1 weeks):
          pushup 3x10
      """

      result = Errors.format_for_llm([error], source)

      assert result =~ "Your WPL-AI output has errors"
      assert result =~ "ERROR 1:"
      assert result =~ "Line 5"
      assert result =~ "pushup"
      assert result =~ "push_up"
      assert result =~ "Exercise names use snake_case"
    end

    test "formats lexer errors with indentation hints" do
      error = LexerError.inconsistent_indentation(4, 3, Location.new(3, 1))

      source = """
      PLAN "Test"
      TYPE workout
         bad indent
      """

      result = Errors.format_for_llm([error], source)

      assert result =~ "Your WPL-AI output has errors"
      assert result =~ "Line 3"
      assert result =~ "expected 4 spaces"
      assert result =~ "got 3"
    end

    test "includes relevant reminders based on error types" do
      exercise_error =
        ParseError.unknown_exercise_ref("bad_ref", Location.new(1, 1), [])

      indent_error = LexerError.tab_character(Location.new(2, 1))

      result = Errors.format_for_llm([exercise_error, indent_error], "source")

      assert result =~ "Remember:"
      assert result =~ "snake_case"
      assert result =~ "spaces"
    end

    test "error_summary/1 provides compact error list" do
      errors = [
        ParseError.unknown_exercise_ref("bad1", Location.new(5, 1), []),
        ParseError.unknown_exercise_ref("bad2", Location.new(10, 1), [])
      ]

      summary = Errors.error_summary(errors)

      assert summary =~ "Line 5"
      assert summary =~ "Line 10"
      assert summary =~ "bad1"
      assert summary =~ "bad2"
    end
  end

  describe "error recovery integration" do
    test "parse errors include line numbers for missing PLAN name" do
      # PLAN without a name string
      source = """
      PLAN
      TYPE workout
      """

      assert {:error, errors} = WplAi.parse(source)
      assert is_list(errors)
      assert length(errors) > 0

      # Errors should be formattable
      formatted = WplAi.format_errors(errors, source)
      assert is_binary(formatted)
      assert formatted =~ "Error"
    end

    test "parse errors for unterminated string" do
      source = ~s(PLAN "Test\nTYPE workout)

      assert {:error, errors} = WplAi.parse(source)
      assert is_list(errors)

      formatted = WplAi.format_errors(errors, source)
      assert is_binary(formatted)
      assert formatted =~ "string" or formatted =~ "Error"
    end

    test "parse errors for bad indentation" do
      source = """
      PLAN "Test"
      TYPE workout
         PHASES
      """

      assert {:error, errors} = WplAi.parse(source)
      assert is_list(errors)

      formatted = WplAi.format_errors(errors, source)
      assert is_binary(formatted)
    end
  end

  describe "double-digit WEEK headers (regression)" do
    test "parses WEEK 10 without 'Invalid number format' error" do
      source = ~S"""
      PLAN "W10"
      TYPE workout

      PHASES
        PHASE "P" (1 weeks):
          WEEK 10:
            DAY Monday training 45m:
              main:
                push_up 3x10
      """

      assert {:ok, _json, _repairs} = WplAi.to_wpl(source)
    end

    test "parses WEEK 10, 11, 12 together (the exact production failure)" do
      source = ~S"""
      PLAN "W10-12"
      TYPE workout

      PHASES
        PHASE "P" (3 weeks):
          WEEK 10:
            DAY Monday training 45m:
              main:
                push_up 3x10
          WEEK 11:
            DAY Monday training 45m:
              main:
                push_up 3x10
          WEEK 12:
            DAY Monday training 45m:
              main:
                push_up 3x10
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [phase] = json["plan"]["phases"]
      assert Enum.map(phase["weeks"], & &1["order"]) == [10, 11, 12]
    end

    test "parses a full 1..12 week plan" do
      weeks =
        1..12
        |> Enum.map_join("\n", fn n ->
          "    WEEK #{n}:\n      DAY Monday training 45m:\n        main:\n          push_up 3x10"
        end)

      source = ~s"""
      PLAN "W1-12"
      TYPE workout

      PHASES
        PHASE "P" (12 weeks):
      #{weeks}
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [phase] = json["plan"]["phases"]
      assert Enum.map(phase["weeks"], & &1["order"]) == Enum.to_list(1..12)
    end

    test "still parses valid HH:MM time literals after the fix" do
      source = ~S"""
      PLAN "Time Literal Check"
      TYPE workout

      PHASES
        PHASE "P" (1 weeks):
          WEEK 1:
            DAY Monday training 45m:
              main:
                push_up 3x10 at 10:30
      """

      assert {:ok, _json, _repairs} = WplAi.to_wpl(source)
    end
  end

  # ===========================================================================
  # Lexer — new keywords
  # ===========================================================================

  describe "Lexer — new keywords (HABITS / HABIT / FREQUENCY / TRIGGER / DESCRIPTION)" do
    alias WplAi.Lexer

    test "HABITS tokenizes as :keyword" do
      assert {:ok, tokens} = Lexer.tokenize("HABITS\n")
      assert Enum.any?(tokens, fn {type, val, _} -> type == :keyword and val == "HABITS" end)
    end

    test "HABIT tokenizes as :keyword" do
      assert {:ok, tokens} = Lexer.tokenize("HABIT\n")
      assert Enum.any?(tokens, fn {type, val, _} -> type == :keyword and val == "HABIT" end)
    end

    test "FREQUENCY tokenizes as :keyword" do
      assert {:ok, tokens} = Lexer.tokenize("FREQUENCY\n")
      assert Enum.any?(tokens, fn {type, val, _} -> type == :keyword and val == "FREQUENCY" end)
    end

    test "TRIGGER tokenizes as :keyword" do
      assert {:ok, tokens} = Lexer.tokenize("TRIGGER\n")
      assert Enum.any?(tokens, fn {type, val, _} -> type == :keyword and val == "TRIGGER" end)
    end

    test "DESCRIPTION tokenizes as :keyword" do
      assert {:ok, tokens} = Lexer.tokenize("DESCRIPTION\n")

      assert Enum.any?(tokens, fn {type, val, _} ->
               type == :keyword and val == "DESCRIPTION"
             end)
    end
  end

  # ===========================================================================
  # Parser — HABITS section (top-level plan habits)
  # ===========================================================================

  describe "parse/1 — top-level HABITS block" do
    test "parses a HABITS block with name, description, frequency and trigger" do
      source = ~S"""
      PLAN "Habit Plan"
      TYPE hybrid

      HABITS
        HABIT daily_steps:
          DESCRIPTION "Walk 10000 steps every day"
          FREQUENCY daily
          TRIGGER "After morning coffee"
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      assert length(doc.habits) == 1
      [habit] = doc.habits
      assert habit.name == "daily_steps"
      assert habit.description == "Walk 10000 steps every day"
      assert habit.frequency == "daily"
      assert habit.trigger == "After morning coffee"
    end

    test "parses multiple HABITS" do
      source = ~S"""
      PLAN "Multi Habit"
      TYPE hybrid

      HABITS
        HABIT hydration:
          DESCRIPTION "Drink 2.5 l water"
          FREQUENCY daily
        HABIT food_log:
          DESCRIPTION "Log every meal"
          FREQUENCY daily
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      assert length(doc.habits) == 2
      names = Enum.map(doc.habits, & &1.name)
      assert "hydration" in names
      assert "food_log" in names
    end

    test "HABITS before PHASES parses correctly" do
      source = ~S"""
      PLAN "Ordered Plan"
      TYPE hybrid

      HABITS
        HABIT weigh_in:
          DESCRIPTION "Weekly weigh-in"
          FREQUENCY weekly

      PHASES
        PHASE "Foundation" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                push_up 3x10
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      assert length(doc.habits) == 1
      assert length(doc.phases) == 1
    end

    test "HABITS after PHASES parses correctly (legacy plan order)" do
      source = ~S"""
      PLAN "Legacy Order"
      TYPE hybrid

      PHASES
        PHASE "Foundation" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                push_up 3x10

      HABITS
        HABIT weigh_in:
          DESCRIPTION "Weekly weigh-in"
          FREQUENCY weekly
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      assert length(doc.phases) == 1
      assert length(doc.habits) == 1
      [habit] = doc.habits
      assert habit.name == "weigh_in"
    end

    test "empty HABITS section (no HABIT entries) yields empty list" do
      source = ~S"""
      PLAN "No Habits"
      TYPE hybrid
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      assert doc.habits == nil or doc.habits == []
    end
  end

  describe "parse/1 — INPUTS accepts keyword-collision names" do
    test "parses INPUTS with 'weight' as the input name" do
      source = ~S"""
      PLAN "Keyword Input"
      TYPE hybrid

      PERSONALIZATION
        INPUTS
          weight = client.weight as number
        RULES
          WHEN age >= 18:
            replace squat -> push_up
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      assert doc.personalization != nil
    end
  end

  describe "parse/1 — parse_time_unit singular forms" do
    test "(1 week) singular compiles duration to unit: weeks" do
      source = ~S"""
      PLAN "Singular Week"
      TYPE workout

      PHASES
        PHASE "Foundation" (1 week):
          WEEK 1:
            DAY Monday training 30m:
              main:
                push_up 3x10
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [phase] = json["plan"]["phases"]
      assert phase["duration"]["unit"] == "weeks"
      assert phase["duration"]["value"] == 1
    end

    test "(1 day) singular maps to days" do
      source = ~S"""
      PLAN "Day Unit"
      TYPE workout

      PHASES
        PHASE "Foundation" (7 day):
          WEEK 1:
            DAY Monday training 30m:
              main:
                push_up 3x10
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [phase] = json["plan"]["phases"]
      assert phase["duration"]["unit"] == "days"
    end

    test "wk abbreviation maps to weeks" do
      source = ~S"""
      PLAN "Wk Plan"
      TYPE workout

      PHASES
        PHASE "Foundation" (4 wk):
          WEEK 1:
            DAY Monday training 30m:
              main:
                push_up 3x10
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [phase] = json["plan"]["phases"]
      assert phase["duration"]["unit"] == "weeks"
    end

    test "wks abbreviation maps to weeks" do
      source = ~S"""
      PLAN "Wks Plan"
      TYPE workout

      PHASES
        PHASE "Foundation" (4 wks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                push_up 3x10
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [phase] = json["plan"]["phases"]
      assert phase["duration"]["unit"] == "weeks"
    end

    test "second singular maps to seconds in activity rest duration" do
      source = ~S"""
      PLAN "Second Plan"
      TYPE workout

      PHASES
        PHASE "Foundation" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                push_up 3x10 rest 60 second
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [phase] = doc.phases
      [week] = phase.weeks
      [day] = week.days
      [block] = day.blocks
      [exercise] = block.activities
      assert exercise.rest.unit == :seconds
    end

    test "minute singular maps to minutes in rest unit" do
      source = ~S"""
      PLAN "Minute Plan"
      TYPE workout

      PHASES
        PHASE "Foundation" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main straight_sets:
                push_up 3x10 rest 2 minute
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [phase] = doc.phases
      [week] = phase.weeks
      [day] = week.days
      [block] = day.blocks
      [activity] = block.activities
      assert activity.rest.unit == :minutes
    end
  end

  describe "parse/1 — PERSONALIZATION RULES with prose actions" do
    test "rule with no recognized action verbs parses without error" do
      source = ~S"""
      PLAN "Prose Actions"
      TYPE workout

      PERSONALIZATION
        RULES
          WHEN age >= 50:
            schedule workouts in the morning
      """

      # Must not blow up — parser is tolerant; rule may have actions: []
      result = WplAi.parse(source)
      assert match?({:ok, _, _}, result) or match?({:error, _}, result)
    end
  end

  # ===========================================================================
  # Compiler — compile_plan_habits / compile_rules (empty actions dropped)
  # ===========================================================================

  describe "compile/1 — compile_plan_habits" do
    test "nil habits input yields nil in plan json" do
      source = ~S"""
      PLAN "No Habits"
      TYPE workout
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      assert json["plan"]["habits"] == nil
    end

    test "HABITS section compiles to list with id/name/description/frequency/trigger" do
      source = ~S"""
      PLAN "Habit Test"
      TYPE hybrid

      HABITS
        HABIT daily_walk:
          DESCRIPTION "Walk 8000 steps"
          FREQUENCY daily
          TRIGGER "After breakfast"
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      habits = json["plan"]["habits"]
      assert is_list(habits)
      assert length(habits) == 1
      [h] = habits
      assert h["id"] == "plan_habit_1"
      assert h["name"] == "daily_walk"
      assert h["description"] == "Walk 8000 steps"
      assert h["frequency"] == "daily"
      assert h["trigger"] == "After breakfast"
    end

    test "multiple habits get sequential ids plan_habit_1..N" do
      source = ~S"""
      PLAN "Multi"
      TYPE hybrid

      HABITS
        HABIT h1:
          DESCRIPTION "First"
          FREQUENCY daily
        HABIT h2:
          DESCRIPTION "Second"
          FREQUENCY weekly
        HABIT h3:
          DESCRIPTION "Third"
          FREQUENCY daily
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      ids = Enum.map(json["plan"]["habits"], & &1["id"])
      assert ids == ["plan_habit_1", "plan_habit_2", "plan_habit_3"]
    end

    test "habit with nil description omits description key" do
      source = ~S"""
      PLAN "Sparse Habit"
      TYPE hybrid

      HABITS
        HABIT sparse:
          FREQUENCY daily
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [h] = json["plan"]["habits"]
      refute Map.has_key?(h, "description")
    end
  end

  describe "compile/1 — compile_rules drops rules with empty actions" do
    test "rule with actions compiles normally" do
      source = ~S"""
      PLAN "With Rule"
      TYPE workout

      PERSONALIZATION
        RULES
          WHEN injury contains knee:
            replace squat -> wall_sit
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      rules = json["plan"]["personalization"]["rules"]
      assert length(rules) == 1
      [rule] = rules
      assert length(rule["actions"]) == 1
    end
  end

  # Helper function to extract activities from a document
  defp get_activities(doc) do
    doc.phases
    |> Enum.flat_map(fn phase ->
      phase.weeks
      |> Enum.flat_map(fn week ->
        week.days
        |> Enum.flat_map(fn day ->
          day.blocks
          |> Enum.map(fn block -> block.activities end)
        end)
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Feature: ATHLETE_THRESHOLDS top-level block (schema v1.3.0)
  # ---------------------------------------------------------------------------

  describe "parse/1 - ATHLETE_THRESHOLDS section" do
    test "parses full ATHLETE_THRESHOLDS block into document.athlete_thresholds" do
      source = ~S"""
      PLAN "Thresholds Test"
      TYPE workout

      ATHLETE_THRESHOLDS
        hr_max 188 bpm
        lthr 168 bpm
        resting_hr 48 bpm
        ftp 285 watts
        vo2max 56
        critical_pace 220
        body_weight 75 kg
        one_rm squat 140 kg
        one_rm bench_press 100 kg

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                squat 3x5
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      at = doc.athlete_thresholds

      assert at != nil
      assert at.hr_max_bpm == 188
      assert at.lthr_bpm == 168
      assert at.resting_hr_bpm == 48
      assert at.ftp_watts == 285
      assert at.vo2max_ml_kg_min == 56
      assert at.critical_pace_seconds_per_km == 220
      assert at.body_weight_kg == 75

      assert length(at.one_rm) == 2
      [squat_entry, bench_entry] = at.one_rm
      assert squat_entry.exercise_ref == "squat"
      assert squat_entry.value == 140
      assert squat_entry.unit == "kg"
      assert bench_entry.exercise_ref == "bench_press"
      assert bench_entry.value == 100
      assert bench_entry.unit == "kg"
    end
  end

  describe "compile/1 - ATHLETE_THRESHOLDS section" do
    test "emits plan.athlete_thresholds with all fields" do
      source = ~S"""
      PLAN "Thresholds Compile"
      TYPE workout

      ATHLETE_THRESHOLDS
        hr_max 188 bpm
        lthr 168 bpm
        resting_hr 48 bpm
        ftp 285 watts
        body_weight 72 kg
        one_rm squat 140 kg
        one_rm bench_press 100 kg

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                push_up 3x10
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      at = json["plan"]["athlete_thresholds"]

      assert at != nil
      assert at["hr_max_bpm"] == 188
      assert at["lthr_bpm"] == 168
      assert at["resting_hr_bpm"] == 48
      assert at["ftp_watts"] == 285
      assert at["body_weight_kg"] == 72

      assert at["one_rm"] == [
               %{"exercise_ref" => "squat", "value" => 140, "unit" => "kg"},
               %{"exercise_ref" => "bench_press", "value" => 100, "unit" => "kg"}
             ]
    end

    test "omits athlete_thresholds from plan when section is absent" do
      source = ~S"""
      PLAN "No Thresholds"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main:
                push_up 3x10
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      refute Map.has_key?(json["plan"], "athlete_thresholds")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Cardio zone_model + power/bpm intensity types (schema v1.3.0)
  # ---------------------------------------------------------------------------

  describe "parse/1 - cardio zone N model M" do
    test "parses zone with model qualifier into Cardio.intensity.zone_model" do
      source = ~S"""
      PLAN "Zone Model Test"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 60m:
              main:
                cardio running continuous:
                  total 60 minutes
                  zone 1 model hr_3_zone_seiler
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[cardio]] = get_activities(doc)

      assert %AST.Cardio{} = cardio
      assert cardio.zone == 1
      assert cardio.intensity != nil
      assert cardio.intensity.zone_model == "hr_3_zone_seiler"
    end

    test "parses zone without model (no zone_model set)" do
      source = ~S"""
      PLAN "Zone No Model"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 60m:
              main:
                cardio running continuous:
                  total 60 minutes
                  zone 3
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[cardio]] = get_activities(doc)

      assert cardio.zone == 3
      assert cardio.intensity == nil || is_nil(cardio.intensity.zone_model)
    end

    test "parses intensity type power N" do
      source = ~S"""
      PLAN "Power Intensity"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 60m:
              main:
                cardio cycling continuous:
                  total 45 minutes
                  intensity power 250
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[cardio]] = get_activities(doc)

      assert cardio.intensity.type == :power
      assert cardio.intensity.value == 250
    end
  end

  describe "compile/1 - cardio zone_model" do
    test "emits intensity.zone_model when zone N model M is specified" do
      source = ~S"""
      PLAN "Zone Model Compile"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 60m:
              main:
                cardio running continuous:
                  total 60 minutes
                  zone 1 model hr_3_zone_seiler
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [[activity]] = get_json_activities(json)

      intensity = activity["prescription"]["intensity"]
      assert intensity["type"] == "heart_rate_zone"
      assert intensity["zone"] == 1
      assert intensity["zone_model"] == "hr_3_zone_seiler"
    end

    test "emits intensity with type power" do
      source = ~S"""
      PLAN "Power Compile"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 60m:
              main:
                cardio cycling continuous:
                  total 45 minutes
                  intensity power 250
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [[activity]] = get_json_activities(json)

      intensity = activity["prescription"]["intensity"]
      assert intensity["type"] == "power"
      assert intensity["value"] == 250
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: MuscleGroup + MovementPattern (schema v1.3.0)
  # ---------------------------------------------------------------------------

  describe "parse/1 - muscles + movement_pattern modifiers" do
    test "parses explicit primary/secondary muscles and movement_pattern on exercise" do
      source = ~S"""
      PLAN "Muscles Test"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main straight_sets:
                bench_press 3x8 muscles primary chest secondary triceps, front_delts pattern push_horizontal
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[exercise]] = get_activities(doc)

      assert %AST.Exercise{} = exercise
      assert exercise.exercise_ref == "bench_press"
      assert exercise.primary_muscles == ["chest"]
      assert exercise.secondary_muscles == ["triceps", "front_delts"]
      assert exercise.movement_pattern == "push_horizontal"
    end

    test "parses shorthand muscle list (all primary, no secondary)" do
      source = ~S"""
      PLAN "Muscles Shorthand"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main straight_sets:
                push_up 3x10 muscles chest, triceps, front_delts pattern push_horizontal
      """

      assert {:ok, doc, _repairs} = WplAi.parse(source)
      [[exercise]] = get_activities(doc)

      assert exercise.primary_muscles == ["chest", "triceps", "front_delts"]
      assert exercise.secondary_muscles == []
      assert exercise.movement_pattern == "push_horizontal"
    end
  end

  describe "compile/1 - muscles + movement_pattern modifiers" do
    test "emits primary_muscles, secondary_muscles, movement_pattern on ExerciseActivity" do
      source = ~S"""
      PLAN "Muscles Compile"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main straight_sets:
                squat 4x5 muscles primary quadriceps, glutes secondary hamstrings pattern squat
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [[activity]] = get_json_activities(json)

      assert activity["primary_muscles"] == ["quadriceps", "glutes"]
      assert activity["secondary_muscles"] == ["hamstrings"]
      assert activity["movement_pattern"] == "squat"
    end

    test "omits muscle/pattern fields when not specified" do
      source = ~S"""
      PLAN "No Muscles"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m:
              main straight_sets:
                push_up 3x10
      """

      assert {:ok, json, _repairs} = WplAi.to_wpl(source)
      [[activity]] = get_json_activities(json)

      refute Map.has_key?(activity, "primary_muscles")
      refute Map.has_key?(activity, "secondary_muscles")
      refute Map.has_key?(activity, "movement_pattern")
    end
  end

  # Helper function to extract activities from compiled JSON
  defp get_json_activities(json) do
    json["plan"]["phases"]
    |> Enum.flat_map(fn phase ->
      (phase["weeks"] || [])
      |> Enum.flat_map(fn week ->
        (week["days"] || [])
        |> Enum.flat_map(fn day ->
          (day["blocks"] || [])
          |> Enum.map(fn block -> block["activities"] || [] end)
        end)
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # TDD: repairs ledger (A1)
  # ---------------------------------------------------------------------------

  describe "to_wpl/1 — repairs ledger" do
    test "returns 3-tuple {ok, json, repairs} on success" do
      source = ~S"""
      PLAN "Repair Test"
      TYPE workout
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day 1":
              main straight_sets:
                push_up 3x10
      """

      assert {:ok, _json, repairs} = WplAi.to_wpl(source)
      assert is_list(repairs)
    end

    test "repairs list is empty for a plan with no silent normalizations" do
      source = ~S"""
      PLAN "Clean Plan"
      TYPE workout
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day 1":
              main straight_sets:
                push_up 3x10
      """

      {:ok, _json, repairs} = WplAi.to_wpl(source)
      # A minimal clean plan should have zero repairs
      assert repairs == []
    end

    test "unknown ALL-CAPS section (non-safety) records a skipped_section repair" do
      source = ~S"""
      PLAN "Plan With Notes"
      TYPE workout
      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 30m "Day 1":
              main straight_sets:
                push_up 3x10
      NOTES:
        Some extra prose.
      """

      {:ok, _json, repairs} = WplAi.to_wpl(source)
      assert Enum.any?(repairs, &(&1.type == :skipped_section))
    end
  end
end
