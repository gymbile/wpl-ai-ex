defmodule WplAi.ExerciseMatcher do
  @moduledoc """
  Fuzzy matching for exercise references in WPL-AI.

  Provides "Did you mean?" suggestions when unknown exercise references
  are encountered during parsing. Uses Jaro-Winkler distance for similarity
  matching, which is effective for typo detection.

  ## Examples

      iex> ExerciseMatcher.suggest("pushup")
      ["push_up"]

      iex> ExerciseMatcher.suggest("squats")
      ["squat"]

      iex> ExerciseMatcher.suggest("benchpress")
      ["bench_press"]

  """

  # Exercise catalog — sourced from the generated data module.
  # To update the catalog, edit priv/data/exercises.json and re-run:
  #   MIX_ENV=test mix run scripts/gen_exercises.exs
  @all_exercises WplAi.ExercisesData.all()

  # MapSet for O(1) membership checks — placed after @all_exercises is fully defined.
  @exercise_set MapSet.new(@all_exercises)

  @doc """
  Get all known exercise references.
  """
  def all_exercises, do: @all_exercises

  @doc """
  Check if an exercise reference is known (O(1) MapSet lookup).

  ## Examples

      iex> ExerciseMatcher.known?("push_up")
      true

      iex> ExerciseMatcher.known?("pushup")
      false

  """
  @spec known?(String.t()) :: boolean()
  def known?(exercise_ref) when is_binary(exercise_ref) do
    MapSet.member?(@exercise_set, exercise_ref)
  end

  @doc """
  Suggest similar exercise references for an unknown reference.

  Returns up to 3 suggestions sorted by similarity (best match first).
  Only returns suggestions with similarity > 0.7 to avoid noise.

  ## Examples

      iex> ExerciseMatcher.suggest("pushup")
      ["push_up"]

      iex> ExerciseMatcher.suggest("squats")
      ["squat"]

      iex> ExerciseMatcher.suggest("xyz123")
      []

  """
  def suggest(unknown_ref) when is_binary(unknown_ref) do
    normalized = normalize(unknown_ref)

    @all_exercises
    |> Enum.map(fn known ->
      {known, similarity(normalized, normalize(known))}
    end)
    |> Enum.filter(fn {_ref, sim} -> sim > 0.7 end)
    |> Enum.sort_by(fn {_ref, sim} -> sim end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {ref, _sim} -> ref end)
  end

  @doc """
  Find the best match for an unknown reference, if similarity is high enough.

  Returns `{:ok, match}` if similarity > 0.85, otherwise `:no_match`.
  This is useful for auto-correction.

  ## Examples

      iex> ExerciseMatcher.best_match("pushup")
      {:ok, "push_up"}

      iex> ExerciseMatcher.best_match("xyz")
      :no_match

  """
  def best_match(unknown_ref) when is_binary(unknown_ref) do
    normalized = normalize(unknown_ref)

    result =
      @all_exercises
      |> Enum.map(fn known ->
        {known, similarity(normalized, normalize(known))}
      end)
      |> Enum.max_by(fn {_ref, sim} -> sim end, fn -> {nil, 0} end)

    case result do
      {match, sim} when sim > 0.85 -> {:ok, match}
      _ -> :no_match
    end
  end

  @doc """
  Validate an exercise reference, returning suggestions if unknown.

  Returns `:ok` if known, or `{:unknown, suggestions}` if not.

  ## Examples

      iex> ExerciseMatcher.validate("push_up")
      :ok

      iex> ExerciseMatcher.validate("pushup")
      {:unknown, ["push_up"]}

  """
  def validate(exercise_ref) when is_binary(exercise_ref) do
    if known?(exercise_ref) do
      :ok
    else
      {:unknown, suggest(exercise_ref)}
    end
  end

  @doc """
  Get exercises by category.
  """
  def exercises_by_category do
    WplAi.ExercisesData.by_category()
  end

  # Normalize for comparison - remove underscores, lowercase
  defp normalize(ref) do
    ref
    |> String.downcase()
    |> String.replace("_", "")
    |> String.replace("-", "")
  end

  # Jaro-Winkler similarity - good for typo detection
  defp similarity(s1, s2) when is_binary(s1) and is_binary(s2) do
    String.jaro_distance(s1, s2)
  end
end
