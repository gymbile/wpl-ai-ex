defmodule WplAi.SafetyInvariantTest do
  use ExUnit.Case, async: false

  # This test verifies the end-to-end safety contract:
  # a contraindicated exercise compiled via WplAi.to_wpl/1 cannot survive
  # a call to WPL.Enforce.enforce/4.

  # Valid WPL-AI DSL with push_up (singular). The contraindication in REQUIRES
  # is compiled into the plan JSON; the enforce rules below are applied separately
  # as a ClientContext-driven safety pass.
  @source ~S"""
  PLAN "Safety Invariant"
  TYPE workout
  REQUIRES
    contraindication shoulder_impingement severity high action exclude
  PHASES
    PHASE "P1" (1 weeks):
      WEEK 1:
        DAY Monday training 45m "Upper":
          main straight_sets:
            push_up 3x10
            squat 3x10
  """

  # Same plan but with push_ups (plural) — compiler will fuzzy-correct to push_up.
  @source_plural ~S"""
  PLAN "Plural Safety Invariant"
  TYPE workout
  REQUIRES
    contraindication shoulder_impingement severity high action exclude
  PHASES
    PHASE "P1" (1 weeks):
      WEEK 1:
        DAY Monday training 45m "Upper":
          main straight_sets:
            push_ups 3x10
            squat 3x10
  """

  test "a contraindicated exercise is stripped by enforce() after compilation" do
    {:ok, json, _repairs} = WplAi.to_wpl(@source)

    rules = [
      %{
        "id" => "no_shoulder_push",
        "condition" => %{
          "field" => "injuries",
          "op" => "contains",
          "value" => "shoulder_impingement"
        },
        "actions" => [%{"type" => "forbid_exercise", "exercise" => "push_up"}]
      }
    ]

    ctx = %{injuries: ["shoulder_impingement"]}

    result = WPL.Enforce.enforce(json, ctx, rules)

    stripped_names = Enum.map(result.stripped, & &1.exercise)

    assert "push_up" in stripped_names,
           "Expected push_up to be stripped; stripped: #{inspect(stripped_names)}"

    surviving = collect_refs(result.plan)

    refute "push_up" in surviving,
           "push_up must not survive enforce(); surviving: #{inspect(surviving)}"

    assert "squat" in surviving, "squat must survive"
  end

  test "plural variant push_ups is stripped by enforce() (compound plural fix)" do
    {:ok, json, _repairs} = WplAi.to_wpl(@source_plural)

    # Diagnose: what exercise_ref did the compiler emit for push_ups?
    # push_ups is unknown → best_match("push_ups") scores 0.95 Jaro-Winkler vs "push_up"
    # → fuzzy-corrected to push_up at compile time. So json has "push_up" and enforce
    # strips it trivially via exact match.
    IO.inspect(json, label: "compiled json for push_ups source")

    rules = [
      %{
        "id" => "no_shoulder_push",
        "condition" => %{
          "field" => "injuries",
          "op" => "contains",
          "value" => "shoulder_impingement"
        },
        "actions" => [%{"type" => "forbid_exercise", "exercise" => "push_up"}]
      }
    ]

    ctx = %{injuries: ["shoulder_impingement"]}

    result = WPL.Enforce.enforce(json, ctx, rules)

    # push_ups (plural) must collide with push_up forbid:
    # either fuzzy-corrected at compile → push_up in json (trivially stripped), or
    # kept verbatim → enforce's Matcher.normalize("push_ups") == "push_up" strips it.
    assert length(result.stripped) >= 1,
           "Expected push_ups to be stripped; stripped was empty"

    assert "squat" in collect_refs(result.plan), "squat must survive"
  end

  defp collect_refs(plan) when is_map(plan) do
    (plan["plan"]["phases"] || [])
    |> Enum.flat_map(fn phase ->
      (phase["weeks"] || [])
      |> Enum.flat_map(fn week ->
        (week["days"] || [])
        |> Enum.flat_map(fn day ->
          (day["blocks"] || [])
          |> Enum.flat_map(fn block ->
            (block["activities"] || [])
            |> Enum.flat_map(fn act ->
              [act["exercise_ref"], act["name"]] |> Enum.filter(&is_binary/1)
            end)
          end)
        end)
      end)
    end)
  end
end
