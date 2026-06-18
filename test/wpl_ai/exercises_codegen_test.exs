defmodule WplAi.ExercisesCodegenTest do
  use ExUnit.Case, async: true

  @root File.cwd!()

  test "committed exercises_data.ex equals a fresh codegen run (no manual drift)" do
    path = Path.join(@root, "lib/wpl_ai/exercises_data.ex")
    before = File.read!(path)

    {_, 0} =
      System.cmd("mix", ["run", "scripts/gen_exercises.exs"],
        cd: @root,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert File.read!(path) == before
  end

  test "generated catalog has 152 unique names matching the vendored JSON" do
    json = Path.join(@root, "priv/data/exercises.json") |> File.read!() |> Jason.decode!()
    flat = json["categories"] |> Map.values() |> List.flatten()
    assert length(flat) == 152
    assert flat |> Enum.uniq() |> length() == 152
    assert Enum.sort(WplAi.ExercisesData.all()) == Enum.sort(flat)
  end

  test "collapses skater_jump and drops split tokens" do
    all = WplAi.ExercisesData.all()
    assert "skater_jump" in all
    refute "skater" in all
    refute "jump" in all
  end

  test "by_category includes rehab_mobility" do
    rehab = WplAi.ExercisesData.by_category()[:rehab_mobility]
    assert "scapular_retraction" in rehab
    assert "diaphragmatic_breathing" in rehab
  end
end
