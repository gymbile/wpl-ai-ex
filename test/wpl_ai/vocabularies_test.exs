defmodule WplAi.VocabulariesTest do
  use ExUnit.Case, async: true

  # Vocabulary in the Elixir implementation is inlined into the parser
  # (not a separate module). These tests exercise the canonical enum values
  # that the parser normalises, using small DSL snippets driven through
  # WplAi.Parser.parse/1 or WplAi.to_wpl/1.

  alias WplAi.Parser
  alias WplAi.AST

  @minimal_header ~S"""
  PLAN "V Test"
  TYPE workout
  """

  defp parse!(source) do
    assert {:ok, doc} = Parser.parse(source)
    doc
  end

  # ---------------------------------------------------------------------------
  # Plan-type vocabulary
  # ---------------------------------------------------------------------------

  describe "plan type vocabulary" do
    test "workout maps to :workout atom" do
      doc = parse!(@minimal_header)
      assert doc.header.type == :workout
    end

    test "nutrition maps to :nutrition atom" do
      doc = parse!("PLAN \"N\"\nTYPE nutrition\n")
      assert doc.header.type == :nutrition
    end

    test "recovery maps to :recovery atom" do
      doc = parse!("PLAN \"R\"\nTYPE recovery\n")
      assert doc.header.type == :recovery
    end

    test "hybrid maps to :hybrid atom" do
      doc = parse!("PLAN \"H\"\nTYPE hybrid\n")
      assert doc.header.type == :hybrid
    end
  end

  # ---------------------------------------------------------------------------
  # Contraindication action vocabulary
  # ---------------------------------------------------------------------------

  describe "contraindication action vocabulary" do
    test "exclude action parses to :exclude" do
      source = @minimal_header <> "\nREQUIRES\n  contraindication knee_pain action exclude\n"
      doc = parse!(source)
      [contra] = doc.requirements.contraindications
      assert contra.action == :exclude
    end

    test "modify action parses to :modify" do
      source = @minimal_header <> "\nREQUIRES\n  contraindication back_pain action modify\n"
      doc = parse!(source)
      [contra] = doc.requirements.contraindications
      assert contra.action == :modify
    end

    test "require_clearance action parses to :require_clearance" do
      source =
        @minimal_header <>
          "\nREQUIRES\n  contraindication osteoporosis action require_clearance\n"

      doc = parse!(source)
      [contra] = doc.requirements.contraindications
      assert contra.action == :require_clearance
    end
  end

  # ---------------------------------------------------------------------------
  # Severity vocabulary
  # ---------------------------------------------------------------------------

  describe "severity vocabulary" do
    test "severity high parses to :high" do
      source = @minimal_header <> "\nREQUIRES\n  contraindication arthritis severity high\n"
      doc = parse!(source)
      [contra] = doc.requirements.contraindications
      assert contra.severity == :high
    end

    test "severity moderate parses to :moderate" do
      source = @minimal_header <> "\nREQUIRES\n  contraindication back_pain severity moderate\n"
      doc = parse!(source)
      [contra] = doc.requirements.contraindications
      assert contra.severity == :moderate
    end

    test "severity low parses to :low" do
      source = @minimal_header <> "\nREQUIRES\n  contraindication shin_splints severity low\n"
      doc = parse!(source)
      [contra] = doc.requirements.contraindications
      assert contra.severity == :low
    end
  end

  # ---------------------------------------------------------------------------
  # Difficulty vocabulary
  # ---------------------------------------------------------------------------

  describe "difficulty vocabulary" do
    test "beginner parses to :beginner" do
      doc = parse!("PLAN \"B\"\nTYPE workout\nDIFFICULTY beginner\n")
      assert doc.header.difficulty == :beginner
    end

    test "intermediate parses to :intermediate" do
      doc = parse!("PLAN \"I\"\nTYPE workout\nDIFFICULTY intermediate\n")
      assert doc.header.difficulty == :intermediate
    end

    test "advanced parses to :advanced" do
      doc = parse!("PLAN \"A\"\nTYPE workout\nDIFFICULTY advanced\n")
      assert doc.header.difficulty == :advanced
    end

    test "adaptive parses to :adaptive" do
      doc = parse!("PLAN \"Ad\"\nTYPE workout\nDIFFICULTY adaptive\n")
      assert doc.header.difficulty == :adaptive
    end
  end

  # ---------------------------------------------------------------------------
  # Recovery modality vocabulary (v1.6)
  # ---------------------------------------------------------------------------

  describe "recovery modality vocabulary" do
    test "smr_foam_roll is a valid keyword in the lexer keyword list" do
      {:ok, tokens} = WplAi.Lexer.tokenize("smr_foam_roll\n")
      pairs = Enum.map(tokens, fn {t, v, _} -> {t, v} end)
      assert {:keyword, "smr_foam_roll"} in pairs
    end

    test "static_stretch is a valid keyword in the lexer keyword list" do
      {:ok, tokens} = WplAi.Lexer.tokenize("static_stretch\n")
      pairs = Enum.map(tokens, fn {t, v, _} -> {t, v} end)
      assert {:keyword, "static_stretch"} in pairs
    end

    test "recovery exercise modality parses through cooldown block" do
      source = ~S"""
      PLAN "Recovery V"
      TYPE workout

      PHASES
        PHASE "P1" (1 weeks):
          WEEK 1:
            DAY Monday training 45m "Day":
              cooldown:
                hip_flexor_stretch 30 x2 modality static_stretch
      """

      doc = parse!(source)
      [phase] = doc.phases
      [week] = phase.weeks
      [day] = week.days
      cooldown_block = Enum.find(day.blocks, fn b -> b.type == :cooldown end)
      assert cooldown_block != nil
      [exercise] = cooldown_block.activities
      assert %AST.RecoveryExercise{} = exercise
      assert exercise.modality == "static_stretch"
    end
  end

  # ---------------------------------------------------------------------------
  # Questionnaire vocabulary (v1.5)
  # ---------------------------------------------------------------------------

  describe "questionnaire vocabulary" do
    test "phq9 is a lexer keyword" do
      {:ok, tokens} = WplAi.Lexer.tokenize("phq9\n")
      pairs = Enum.map(tokens, fn {t, v, _} -> {t, v} end)
      assert {:keyword, "phq9"} in pairs
    end

    test "gad7 is a lexer keyword" do
      {:ok, tokens} = WplAi.Lexer.tokenize("gad7\n")
      pairs = Enum.map(tokens, fn {t, v, _} -> {t, v} end)
      assert {:keyword, "gad7"} in pairs
    end
  end
end
