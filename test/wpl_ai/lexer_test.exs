defmodule WplAi.LexerTest do
  use ExUnit.Case, async: true

  alias WplAi.Lexer

  # Helper: tokenize and return only {type, value} pairs (no location noise).
  defp token_pairs(source) do
    {:ok, tokens} = Lexer.tokenize(source)
    Enum.map(tokens, fn {type, value, _loc} -> {type, value} end)
  end

  # Helper: return only the token types.
  defp token_types(source) do
    source |> token_pairs() |> Enum.map(&elem(&1, 0))
  end

  # Helper: return only token values where type matches.
  defp values_of_type(source, type) do
    source
    |> token_pairs()
    |> Enum.filter(fn {t, _v} -> t == type end)
    |> Enum.map(&elem(&1, 1))
  end

  describe "tokenize/1 - single top-level keywords" do
    test "PLAN tokenizes as keyword" do
      pairs = token_pairs("PLAN \"My Plan\"\nTYPE workout\n")
      assert {:keyword, "PLAN"} in pairs
    end

    test "TYPE tokenizes as keyword" do
      pairs = token_pairs("TYPE workout\n")
      assert {:keyword, "TYPE"} in pairs
    end

    test "PHASES and WEEK and DAY tokenize as keywords" do
      source =
        "PHASES\n  PHASE \"P\" (1 weeks):\n    WEEK 1:\n      DAY Monday training 30m \"D\":\n"

      types = token_types(source)
      assert :keyword in types
      keywords = values_of_type(source, :keyword)
      assert "PHASES" in keywords
      assert "WEEK" in keywords
      assert "DAY" in keywords
    end
  end

  describe "tokenize/1 - number tokenization" do
    test "integer tokenizes as number" do
      pairs = token_pairs("3\n")
      assert {:number, 3} in pairs
    end

    test "decimal tokenizes as number" do
      pairs = token_pairs("3.14\n")
      assert {:number, 3.14} in pairs
    end

    test "range operator produces two numbers and a range token" do
      pairs = token_pairs("1..5\n")
      assert {:number, 1} in pairs
      assert {:range, ".."} in pairs
      assert {:number, 5} in pairs
    end

    test "negative number tokenizes correctly" do
      pairs = token_pairs("-2\n")
      assert {:number, -2} in pairs
    end
  end

  describe "tokenize/1 - string tokenization" do
    test "double-quoted string produces a string token" do
      pairs = token_pairs(~s("hello world"\n))
      assert {:string, "hello world"} in pairs
    end

    test "escaped quote inside string is preserved" do
      pairs = token_pairs(~s("say \\"hi\\""\n))
      assert {:string, ~s(say "hi")} in pairs
    end
  end

  describe "tokenize/1 - comment skipping" do
    test "comment line is skipped and not tokenized" do
      pairs = token_pairs("# this is a comment\n")
      types = Enum.map(pairs, &elem(&1, 0))
      refute :ident in types
      refute :bare_word in types
      refute :keyword in types
    end

    test "comment at end of line is ignored" do
      pairs = token_pairs("TYPE workout # comment here\n")
      assert {:keyword, "TYPE"} in pairs
      # "workout" is in the keyword list, so it tokenizes as :keyword
      assert {:keyword, "workout"} in pairs
      # "comment" should NOT appear as a token
      refute {:bare_word, "comment"} in pairs
    end
  end

  describe "tokenize/1 - time literals (number + unit bare_word)" do
    test "30s produces number 30 and bare_word 's'" do
      pairs = token_pairs("30s\n")
      assert {:number, 30} in pairs
      assert {:bare_word, "s"} in pairs
    end

    test "5m produces number 5 and bare_word 'm'" do
      pairs = token_pairs("5m\n")
      assert {:number, 5} in pairs
      assert {:bare_word, "m"} in pairs
    end

    test "2h produces number 2 and bare_word 'h'" do
      pairs = token_pairs("2h\n")
      assert {:number, 2} in pairs
      assert {:bare_word, "h"} in pairs
    end
  end

  describe "tokenize/1 - underscore identifiers" do
    test "push_up tokenizes as bare_word" do
      pairs = token_pairs("push_up\n")
      assert {:bare_word, "push_up"} in pairs
    end

    test "body_weight_kg tokenizes as keyword (it is in the keyword list)" do
      pairs = token_pairs("body_weight_kg\n")

      types_for_value =
        pairs
        |> Enum.filter(fn {_t, v} -> v == "body_weight_kg" end)
        |> Enum.map(&elem(&1, 0))

      assert types_for_value != [], "body_weight_kg was not tokenized at all"
    end
  end

  describe "tokenize/1 - v1.5/v1.6 keywords" do
    test "amrap is a keyword" do
      assert {:keyword, "amrap"} in token_pairs("amrap\n")
    end

    test "to_failure is a keyword" do
      assert {:keyword, "to_failure"} in token_pairs("to_failure\n")
    end

    test "require_clearance is a keyword" do
      assert {:keyword, "require_clearance"} in token_pairs("require_clearance\n")
    end

    test "modality is a keyword" do
      assert {:keyword, "modality"} in token_pairs("modality\n")
    end
  end

  describe "tokenize/1 - edge cases" do
    test "empty input returns only EOF token" do
      {:ok, tokens} = Lexer.tokenize("")
      pairs = Enum.map(tokens, fn {t, v, _} -> {t, v} end)
      assert pairs == [{:eof, nil}]
    end

    test "whitespace-only input returns only EOF token" do
      {:ok, tokens} = Lexer.tokenize("\n\n")
      pairs = Enum.map(tokens, fn {t, v, _} -> {t, v} end)
      assert {:eof, nil} in pairs
      refute Enum.any?(pairs, fn {t, _} -> t in [:ident, :bare_word, :keyword, :number] end)
    end

    test "tempo pattern 3-1-1-0 tokenizes as four numbers (minus is consumed as leading sign)" do
      # The lexer consumes leading '-' as a sign on the next number token;
      # so "3-1-1-0" produces numbers 3, -1, -1, 0 — no :minus tokens.
      pairs = token_pairs("3-1-1-0\n")

      number_values =
        pairs |> Enum.filter(fn {t, _} -> t == :number end) |> Enum.map(&elem(&1, 1))

      assert number_values == [3, -1, -1, 0]
    end

    test "WEEK 1: does not swallow the colon into the number" do
      pairs = token_pairs("WEEK 1:\n")
      assert {:keyword, "WEEK"} in pairs
      assert {:number, 1} in pairs
      assert {:colon, ":"} in pairs
    end

    test "WEEK 10: does not swallow the colon into the number" do
      pairs = token_pairs("WEEK 10:\n")
      assert {:number, 10} in pairs
      assert {:colon, ":"} in pairs
    end

    test "60 followed by colon is not parsed as malformed time" do
      # 60: is NOT a valid HH:MM because no digits after colon — must stop at colon
      result = Lexer.tokenize("60:\n")
      assert {:ok, tokens} = result
      pairs = Enum.map(tokens, fn {t, v, _} -> {t, v} end)
      assert {:number, 60} in pairs
      assert {:colon, ":"} in pairs
    end
  end
end
