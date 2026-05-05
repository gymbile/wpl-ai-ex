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

  # Exercise library - canonical exercise references
  # Organized by category for maintainability
  @upper_body ~w(
    push_up pull_up chin_up dip
    bench_press incline_press decline_press dumbbell_press
    shoulder_press overhead_press military_press arnold_press
    dumbbell_row barbell_row bent_over_row cable_row seated_row
    lat_pulldown cable_pulldown
    bicep_curl hammer_curl concentration_curl preacher_curl
    tricep_dip tricep_extension tricep_pushdown skull_crusher
    face_pull rear_delt_fly lateral_raise front_raise
    dumbbell_fly cable_fly chest_fly pec_deck
    shrug upright_row
  )

  @lower_body ~w(
    squat front_squat goblet_squat sumo_squat split_squat
    lunge walking_lunge reverse_lunge lateral_lunge
    deadlift romanian_deadlift sumo_deadlift trap_bar_deadlift
    leg_press hack_squat
    leg_curl leg_extension
    calf_raise seated_calf_raise standing_calf_raise
    glute_bridge hip_thrust
    step_up box_jump jump_squat
    hip_abduction hip_adduction
    good_morning
  )

  @core ~w(
    plank side_plank plank_up
    crunch bicycle_crunch reverse_crunch
    sit_up v_up
    russian_twist wood_chop
    leg_raise hanging_leg_raise lying_leg_raise
    mountain_climber
    dead_bug bird_dog
    ab_wheel ab_rollout
    hollow_hold hollow_rock
    toe_touch
    pallof_press
    superman back_extension
  )

  @cardio_warmup ~w(
    jumping_jack jump_rope high_knees butt_kicks
    burpee squat_jump tuck_jump
    arm_circles leg_swings hip_circles ankle_circles
    jog_in_place marching
    jumping_lunge box_step
    skater jump
    bear_crawl crab_walk
    inchworm
  )

  @stretching ~w(
    hamstring_stretch quad_stretch hip_flexor_stretch
    calf_stretch achilles_stretch
    chest_stretch shoulder_stretch tricep_stretch
    lat_stretch back_stretch spinal_twist
    neck_stretch neck_roll
    butterfly_stretch frog_stretch pigeon_pose
    child_pose cat_cow
    forward_fold standing_forward_fold
    figure_four_stretch
    wrist_circles ankle_rolls
  )

  @full_body ~w(
    turkish_getup clean clean_and_press
    snatch kettlebell_swing
    thrusters wall_ball
    farmers_walk suitcase_carry
    battle_ropes rowing
  )

  @all_exercises @upper_body ++
                   @lower_body ++
                   @core ++
                   @cardio_warmup ++
                   @stretching ++
                   @full_body

  @doc """
  Get all known exercise references.
  """
  def all_exercises, do: @all_exercises

  @doc """
  Check if an exercise reference is known.

  ## Examples

      iex> ExerciseMatcher.known?("push_up")
      true

      iex> ExerciseMatcher.known?("pushup")
      false

  """
  def known?(exercise_ref) when is_binary(exercise_ref) do
    exercise_ref in @all_exercises
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
    %{
      upper_body: @upper_body,
      lower_body: @lower_body,
      core: @core,
      cardio_warmup: @cardio_warmup,
      stretching: @stretching,
      full_body: @full_body
    }
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
