defmodule WplAi.Validator do
  @moduledoc """
  Semantic validator for WPL-AI AST documents.

  Walks the AST after parsing and emits warnings (not errors) for values that
  don't match known WPL vocabulary. Plans with unknown values still compile, but
  this module flags them so the user gets actionable feedback.

  Mirrors the TypeScript `validateSemantics` function in `wpl-ai/src/validator.ts`.
  """

  alias WplAi.AST

  @type warning :: %{
          severity: :warning | :info,
          message: String.t()
        }

  # ---------------------------------------------------------------------------
  # Vocabulary lists (schema v1.6.0)
  # ---------------------------------------------------------------------------

  # Legacy measurement metrics (pre-1.6.0 — kept for back-compat in string items)
  @legacy_measurement_metrics ~w(
    weight body_fat bmi photos measurements
    chest waist hips arms thighs calves_circumference neck
    resting_heart_rate blood_pressure vo2_max 1rm
  )

  # Canonical MeasurementMetric enum values (schema v1.6.0, 24 values)
  @measurement_metric_enum ~w(
    body_weight_kg waist_cm hip_cm body_fat_pct lean_mass_kg
    resting_hr_bpm hrv_rmssd_ms blood_pressure_systolic_mmhg blood_pressure_diastolic_mmhg
    vo2max_ml_kg_min six_min_walk_m cooper_test_m
    one_rm_kg grip_strength_kg vertical_jump_cm
    sit_and_reach_cm shoulder_flexion_deg
    sleep_hours_avg session_rpe_avg
    questionnaire_score photo free_text
  )

  # Combined list for string-form items (back-compat + v1.6.0 enum), deduped
  @all_measurement_metrics Enum.uniq(@legacy_measurement_metrics ++ @measurement_metric_enum)

  @measurement_metric_set MapSet.new(@measurement_metric_enum)
  @all_measurement_metric_set MapSet.new(@all_measurement_metrics)

  # Questionnaire enum values (schema v1.6.0, 8 values)
  @questionnaire_values ~w(phq9 gad7 ipaq_short ipaq_long psqi pss10 borg_cr10 rpe_session)
  @questionnaire_set MapSet.new(@questionnaire_values)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Validate a parsed AST document, returning a list of semantic warnings.

  Warnings are produced for values that don't match known WPL vocabulary.
  The plan is still valid (warnings, not errors).

  ## Examples

      iex> {:ok, doc} = WplAi.parse(source)
      iex> warnings = WplAi.Validator.validate_semantics(doc)
      iex> Enum.filter(warnings, &String.contains?(&1.message, "measurement metric"))
      []

  """
  @spec validate_semantics(AST.Document.t()) :: [warning()]
  def validate_semantics(%AST.Document{} = doc) do
    []
    |> validate_progress(doc.progress)
  end

  # ---------------------------------------------------------------------------
  # Progress section — checkpoints and measurement metrics
  # ---------------------------------------------------------------------------

  defp validate_progress(warnings, nil), do: warnings

  defp validate_progress(warnings, %AST.Progress{} = progress) do
    checkpoint_warnings =
      (progress.checkpoints || [])
      |> Enum.flat_map(&validate_checkpoint/1)

    warnings ++ checkpoint_warnings
  end

  defp validate_checkpoint(%AST.Checkpoint{} = cp) do
    (cp.measurements || [])
    |> Enum.flat_map(&validate_measurement/1)
  end

  # String items: validate against combined legacy + v1.6.0 enum vocabulary
  defp validate_measurement(item) when is_binary(item) do
    check_vocabulary(item, "measurement metric", @all_measurement_metric_set, @all_measurement_metrics)
  end

  # Typed MeasurementSpec (v1.6.0+): validate metric and optionally questionnaire
  defp validate_measurement(%AST.MeasurementSpec{} = spec) do
    metric_warnings =
      check_vocabulary(spec.metric, "measurement metric", @measurement_metric_set, @measurement_metric_enum)

    questionnaire_warnings =
      if spec.metric == "questionnaire_score" && spec.questionnaire do
        check_vocabulary(spec.questionnaire, "questionnaire", @questionnaire_set, @questionnaire_values)
      else
        []
      end

    # spec.note and spec.unit are free strings per schema — no vocabulary check
    metric_warnings ++ questionnaire_warnings
  end

  # ---------------------------------------------------------------------------
  # Vocabulary check helper
  # ---------------------------------------------------------------------------

  defp check_vocabulary(value, field_name, known_set, all_values) do
    if MapSet.member?(known_set, value) do
      []
    else
      suggestions = find_suggestions(value, all_values)

      message =
        if suggestions != [] do
          "Unknown #{field_name} \"#{value}\". Did you mean: #{Enum.join(suggestions, ", ")}?"
        else
          "Unknown #{field_name} \"#{value}\". Expected: #{Enum.join(all_values, " | ")}."
        end

      [%{severity: :warning, message: message}]
    end
  end

  # ---------------------------------------------------------------------------
  # Fuzzy suggestion (simple Levenshtein-based, mirrors TS vocabulary-matcher)
  # ---------------------------------------------------------------------------

  defp find_suggestions(value, all_values) do
    value_lower = String.downcase(value)
    max_dist = max(2, div(String.length(value_lower), 3))

    all_values
    |> Enum.map(fn candidate -> {candidate, levenshtein(value_lower, String.downcase(candidate))} end)
    |> Enum.filter(fn {_candidate, dist} -> dist <= max_dist end)
    |> Enum.sort_by(fn {_candidate, dist} -> dist end)
    |> Enum.take(3)
    |> Enum.map(fn {candidate, _} -> candidate end)
  end

  # Iterative Levenshtein distance
  defp levenshtein(s, t) do
    s_len = String.length(s)
    t_len = String.length(t)

    cond do
      s_len == 0 -> t_len
      t_len == 0 -> s_len
      s == t -> 0
      true ->
        s_chars = String.graphemes(s)
        t_chars = String.graphemes(t)
        initial_row = Enum.to_list(0..t_len)

        Enum.with_index(s_chars, 1)
        |> Enum.reduce(initial_row, fn {sc, i}, prev_row ->
          new_row =
            Enum.with_index(t_chars, 1)
            |> Enum.reduce([i], fn {tc, j}, row_acc ->
              cost = if sc == tc, do: 0, else: 1
              val = Enum.min([
                List.last(row_acc) + 1,
                Enum.at(prev_row, j) + 1,
                Enum.at(prev_row, j - 1) + cost
              ])
              row_acc ++ [val]
            end)
          new_row
        end)
        |> List.last()
    end
  end
end
