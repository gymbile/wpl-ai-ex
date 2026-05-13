defmodule WplAi.AST do
  @moduledoc """
  AST node definitions for WPL-AI parser.

  The AST represents the parsed structure of a WPL-AI document before
  compilation to WPL JSON.
  """

  # =============================================================================
  # Document Root
  # =============================================================================

  defmodule Document do
    @moduledoc "Root AST node representing a complete WPL-AI document"
    defstruct [
      :header,
      :goals,
      :requirements,
      :personalization,
      :phases,
      :habits,
      :progress,
      :notifications,
      :rendering,
      :athlete_thresholds,
      meta: %{}
    ]

    @type t :: %__MODULE__{
            header: Header.t(),
            goals: [Goal.t()] | nil,
            requirements: Requirements.t() | nil,
            personalization: Personalization.t() | nil,
            phases: [Phase.t()],
            habits: [PlanHabit.t()] | nil,
            progress: Progress.t() | nil,
            notifications: [Notification.t()] | nil,
            rendering: Rendering.t() | nil,
            athlete_thresholds: AthleteThresholds.t() | nil,
            meta: map()
          }
  end

  defmodule OneRMEntry do
    @moduledoc "One-rep-max entry for a specific exercise"
    defstruct [:exercise_ref, :value, :unit]

    @type t :: %__MODULE__{
            exercise_ref: String.t(),
            value: number(),
            unit: String.t()
          }
  end

  defmodule AthleteThresholds do
    @moduledoc "Athlete physiological thresholds (plan-level, schema v1.3.0+)"
    defstruct [
      :hr_max_bpm,
      :lthr_bpm,
      :resting_hr_bpm,
      :ftp_watts,
      :vo2max_ml_kg_min,
      :critical_pace_seconds_per_km,
      :body_weight_kg,
      :one_rm
    ]

    @type t :: %__MODULE__{
            hr_max_bpm: integer() | nil,
            lthr_bpm: integer() | nil,
            resting_hr_bpm: integer() | nil,
            ftp_watts: number() | nil,
            vo2max_ml_kg_min: number() | nil,
            critical_pace_seconds_per_km: number() | nil,
            body_weight_kg: number() | nil,
            one_rm: [OneRMEntry.t()] | nil
          }
  end

  defmodule PlanHabit do
    @moduledoc """
    Plan-level habit (top-level `HABITS` block). Distinct from the in-day
    `Habit` activity: this represents a coaching cue carried across the
    whole plan (e.g. weekly weigh-in, daily food log) rather than a
    measurable target dropped into a day's blocks.
    """
    defstruct [:name, :description, :frequency, :trigger, meta: %{}]

    @type t :: %__MODULE__{
            name: String.t(),
            description: String.t() | nil,
            frequency: String.t() | nil,
            trigger: String.t() | nil,
            meta: map()
          }
  end

  # =============================================================================
  # Plan Header
  # =============================================================================

  defmodule Header do
    @moduledoc "Plan header with name and attributes"
    defstruct [
      :name,
      :type,
      :visibility,
      :difficulty,
      :duration,
      :tags,
      :language,
      :min_app_version,
      :schema,
      meta: %{}
    ]

    @type plan_type :: :workout | :nutrition | :meditation | :recovery | :hybrid
    @type visibility :: :private | :public | :template
    @type difficulty :: :beginner | :intermediate | :advanced | :adaptive

    @type t :: %__MODULE__{
            name: String.t(),
            type: plan_type(),
            visibility: visibility() | nil,
            difficulty: difficulty() | nil,
            duration: Duration.t() | nil,
            tags: [String.t()] | nil,
            language: String.t() | nil,
            min_app_version: String.t() | nil,
            schema: String.t() | nil,
            meta: map()
          }
  end

  # =============================================================================
  # Goals
  # =============================================================================

  defmodule Goal do
    @moduledoc "A fitness/wellness goal"
    defstruct [
      :priority,
      :category,
      :name,
      :description,
      :target,
      :deadline,
      :milestones,
      meta: %{}
    ]

    @type priority :: :primary | :secondary

    @type t :: %__MODULE__{
            priority: priority(),
            category: String.t(),
            name: String.t() | nil,
            description: String.t() | nil,
            target: Target.t() | nil,
            deadline: Date.t() | nil,
            milestones: [Milestone.t()] | nil,
            meta: map()
          }
  end

  defmodule Target do
    @moduledoc "Goal target specification"
    defstruct [:metric, :value, :unit, :measurement_type]

    @type measurement_type :: :absolute | :relative | :percentage

    @type t :: %__MODULE__{
            metric: String.t(),
            value: number(),
            unit: String.t(),
            measurement_type: measurement_type()
          }
  end

  defmodule Milestone do
    @moduledoc "Goal milestone"
    defstruct [:name, :at_value, :at_unit, :reward_points, :badge]

    @type t :: %__MODULE__{
            name: String.t(),
            at_value: number(),
            at_unit: String.t(),
            reward_points: integer() | nil,
            badge: String.t() | nil
          }
  end

  # =============================================================================
  # Requirements
  # =============================================================================

  defmodule Requirements do
    @moduledoc "Plan requirements"
    defstruct [
      :age_range,
      :fitness_levels,
      :equipment,
      :contraindications,
      :time_commitment,
      meta: %{}
    ]

    @type t :: %__MODULE__{
            age_range: {integer(), integer()} | nil,
            fitness_levels: [String.t()] | nil,
            equipment: [Equipment.t()] | nil,
            contraindications: [Contraindication.t()] | nil,
            time_commitment: TimeCommitment.t() | nil,
            meta: map()
          }
  end

  defmodule Equipment do
    @moduledoc "Equipment requirement"
    defstruct [:name, :required, :alternatives]

    @type t :: %__MODULE__{
            name: String.t(),
            required: boolean(),
            alternatives: [String.t()] | nil
          }
  end

  defmodule Contraindication do
    @moduledoc "Medical contraindication"
    defstruct [:condition, :action, :severity, :affects]

    @type action :: :exclude | :modify | :require_clearance
    @type severity :: :low | :moderate | :high

    @type t :: %__MODULE__{
            condition: String.t(),
            action: action(),
            severity: severity() | nil,
            affects: [String.t()] | nil
          }
  end

  defmodule TimeCommitment do
    @moduledoc "Time commitment requirements"
    defstruct [:days_per_week, :minutes_per_day]

    @type t :: %__MODULE__{
            days_per_week: {integer(), integer()},
            minutes_per_day: {integer(), integer()}
          }
  end

  # =============================================================================
  # Personalization
  # =============================================================================

  defmodule Personalization do
    @moduledoc "Personalization rules section"
    defstruct [:inputs, :rules, meta: %{}]

    @type t :: %__MODULE__{
            inputs: [Input.t()] | nil,
            rules: [Rule.t()],
            meta: map()
          }
  end

  defmodule Input do
    @moduledoc "Personalization input definition"
    defstruct [:name, :source, :type, :options, :label]

    @type input_type :: :number | :string | :array | :enum | :boolean

    @type t :: %__MODULE__{
            name: String.t(),
            source: String.t(),
            type: input_type(),
            options: [String.t()] | nil,
            label: String.t() | nil
          }
  end

  defmodule Rule do
    @moduledoc "Personalization rule with condition and actions"
    defstruct [:condition, :actions, meta: %{}]

    @type t :: %__MODULE__{
            condition: Condition.t(),
            actions: [Action.t()],
            meta: map()
          }
  end

  defmodule Condition do
    @moduledoc "Rule condition (can be compound with AND/OR)"
    defstruct [:type, :operator, :field, :op, :value, :conditions]

    @type condition_type :: :simple | :compound
    @type logical_op :: :and | :or
    @type comparison_op :: :eq | :neq | :gt | :gte | :lt | :lte | :contains | :not_contains

    @type t :: %__MODULE__{
            type: condition_type(),
            operator: logical_op() | nil,
            field: String.t() | nil,
            op: comparison_op() | nil,
            value: any() | nil,
            conditions: [t()] | nil
          }
  end

  defmodule Action do
    @moduledoc "Personalization action"
    defstruct [:type, :params, :scope]

    @type action_type ::
            :modify_intensity
            | :add_warmup_time
            | :add_activity
            | :replace_exercise
            | :exclude_exercise
            | :reduce_sets
            | :reduce_reps
            | :increase_rest

    @type scope :: :activity | :block | :day | :week | :phase | :plan

    @type t :: %__MODULE__{
            type: action_type(),
            params: map(),
            scope: scope()
          }
  end

  # =============================================================================
  # Phases / Weeks / Days / Blocks
  # =============================================================================

  defmodule Phase do
    @moduledoc "Training phase"
    defstruct [:name, :type, :duration, :goals, :description, :weeks, meta: %{}]

    @type phase_type ::
            :accumulation
            | :intensification
            | :realization
            | :deload
            | :base
            | :build
            | :peak
            | :recovery
            | :transition

    @type t :: %__MODULE__{
            name: String.t(),
            type: phase_type() | nil,
            duration: Duration.t(),
            goals: [String.t()] | nil,
            description: String.t() | nil,
            weeks: [Week.t()],
            meta: map()
          }
  end

  defmodule Week do
    @moduledoc "Training week"
    defstruct [:number, :name, :is_deload, :days, meta: %{}]

    @type t :: %__MODULE__{
            number: integer(),
            name: String.t() | nil,
            is_deload: true | nil,
            days: [Day.t()],
            meta: map()
          }
  end

  defmodule Day do
    @moduledoc "Training day"
    defstruct [
      :day_name,
      :day_type,
      :duration,
      :label,
      :schedule,
      :blocks,
      :notes,
      meta: %{}
    ]

    @type day_type :: :training | :rest | :active_recovery | :assessment
    @type schedule_pref :: :morning | :afternoon | :evening | :any
    @type schedule_flex :: :strict | :flexible

    @type t :: %__MODULE__{
            day_name: String.t() | integer(),
            day_type: day_type(),
            duration: Duration.t(),
            label: String.t() | nil,
            schedule: {schedule_pref(), schedule_flex()} | nil,
            blocks: [Block.t()],
            notes: String.t() | nil,
            meta: map()
          }
  end

  defmodule Block do
    @moduledoc "Activity block within a day"
    defstruct [:type, :structure, :rounds, :rest_between_rounds, :activities, meta: %{}]

    @type block_type ::
            :warmup | :main | :cooldown | :nutrition | :meditation | :education | :assessment

    @type block_structure ::
            :circuit | :straight_sets | :superset | :emom | :amrap | :tabata | nil

    @type t :: %__MODULE__{
            type: block_type(),
            structure: block_structure(),
            rounds: integer() | nil,
            rest_between_rounds: Duration.t() | nil,
            activities: [activity()],
            meta: map()
          }

    @type activity ::
            Exercise.t()
            | Cardio.t()
            | Nutrition.t()
            | Meditation.t()
            | Recovery.t()
            | Habit.t()
            | SimpleActivity.t()
            | SubPlan.t()
  end

  # =============================================================================
  # Activities
  # =============================================================================

  defmodule Exercise do
    @moduledoc "Exercise activity"
    defstruct [
      :exercise_ref,
      :name,
      :sets,
      :reps,
      :rpe,
      :rpe_min,
      :rpe_max,
      :rir,
      :rir_min,
      :rir_max,
      :tempo,
      :rest,
      :weight,
      :to_failure,
      :primary_muscles,
      :secondary_muscles,
      :movement_pattern,
      meta: %{}
    ]

    @type reps_spec ::
            integer()
            | {integer(), integer()}
            | {integer(), integer(), integer()}
            | :amrap

    @type t :: %__MODULE__{
            exercise_ref: String.t(),
            name: String.t() | nil,
            sets: integer(),
            reps: reps_spec(),
            rpe: integer() | nil,
            rpe_min: integer() | nil,
            rpe_max: integer() | nil,
            rir: integer() | nil,
            rir_min: integer() | nil,
            rir_max: integer() | nil,
            tempo: String.t() | nil,
            rest: Duration.t() | nil,
            weight: Weight.t() | nil,
            to_failure: true | nil,
            primary_muscles: [String.t()] | nil,
            secondary_muscles: [String.t()] | nil,
            movement_pattern: String.t() | nil,
            meta: map()
          }
  end

  defmodule Weight do
    @moduledoc "Weight specification"
    defstruct [:type, :value, :unit, :metric]

    @type weight_type :: :bodyweight | :absolute | :percentage_1rm | :percentage_bodyweight
    @type metric :: String.t() | nil

    @type t :: %__MODULE__{
            type: weight_type(),
            value: number() | nil,
            unit: String.t() | nil,
            metric: metric()
          }
  end

  defmodule Cardio do
    @moduledoc "Cardio activity"
    defstruct [
      :modality,
      :cardio_type,
      :total_duration,
      :zone,
      :intensity,
      :intervals,
      meta: %{}
    ]

    @type cardio_type :: :continuous | :intervals | :fartlek

    @type t :: %__MODULE__{
            modality: String.t(),
            cardio_type: cardio_type(),
            total_duration: Duration.t(),
            zone: integer() | nil,
            intensity: Intensity.t() | nil,
            intervals: IntervalPattern.t() | nil,
            meta: map()
          }
  end

  defmodule Intensity do
    @moduledoc "Intensity specification"
    defstruct [:type, :value, :range, :zone_model]

    @type intensity_type :: :rpe | :heart_rate_zone | :bpm | :pace | :power

    @type t :: %__MODULE__{
            type: intensity_type(),
            value: number() | String.t() | nil,
            range: {number(), number()} | nil,
            zone_model: String.t() | nil
          }
  end

  defmodule IntervalPattern do
    @moduledoc "Interval pattern for cardio"
    defstruct [:work_seconds, :rest_seconds, :repeats]

    @type t :: %__MODULE__{
            work_seconds: integer(),
            rest_seconds: integer(),
            repeats: integer()
          }
  end

  defmodule Nutrition do
    @moduledoc "Nutrition activity"
    defstruct [:category, :name, :timing, :macros, :calories, :suggestions, meta: %{}]

    @type category :: :meal | :snack | :supplement | :hydration | String.t()

    @type t :: %__MODULE__{
            category: category(),
            name: String.t() | nil,
            timing: NutritionTiming.t() | nil,
            macros: Macros.t() | nil,
            calories: {number(), number(), String.t()} | nil,
            suggestions: [String.t()] | nil,
            meta: map()
          }
  end

  defmodule NutritionTiming do
    @moduledoc "Nutrition timing specification"
    defstruct [:type, :duration, :time]

    @type timing_type :: :after_workout | :before_workout | :at_time

    @type t :: %__MODULE__{
            type: timing_type(),
            duration: Duration.t() | nil,
            time: Time.t() | nil
          }
  end

  defmodule Macros do
    @moduledoc "Macronutrient targets"
    defstruct [:protein, :carbs, :fat]

    @type range :: {number(), number(), String.t()} | {:max, number(), String.t()}

    @type t :: %__MODULE__{
            protein: range() | nil,
            carbs: range() | nil,
            fat: range() | nil
          }
  end

  defmodule Meditation do
    @moduledoc "Meditation activity"
    defstruct [:category, :duration, :guided, :audio_id, meta: %{}]

    @type category ::
            :breathing | :mindfulness | :visualization | :body_scan | :sleep | String.t()

    @type t :: %__MODULE__{
            category: category(),
            duration: Duration.t(),
            guided: boolean() | nil,
            audio_id: String.t() | nil,
            meta: map()
          }
  end

  defmodule Recovery do
    @moduledoc "Recovery activity"
    defstruct [:category, :duration, :exercises, meta: %{}]

    @type category ::
            :stretching
            | :foam_rolling
            | :massage
            | :cold_therapy
            | :heat_therapy
            | :sleep
            | String.t()

    @type t :: %__MODULE__{
            category: category(),
            duration: Duration.t(),
            exercises: [RecoveryExercise.t()] | nil,
            meta: map()
          }
  end

  defmodule PnfSpec do
    @moduledoc "PNF stretching parameters (schema v1.6.0+)"
    defstruct [:contraction_seconds, :relax_seconds, :contractions]

    @type t :: %__MODULE__{
            contraction_seconds: integer(),
            relax_seconds: integer(),
            contractions: integer()
          }
  end

  defmodule RecoveryExercise do
    @moduledoc "Individual recovery exercise"
    defstruct [:name, :hold_seconds, :reps, :sides, :modality, :intensity_rpe, :body_part, :pnf]

    @type sides :: :both | :left | :right

    @type t :: %__MODULE__{
            name: String.t(),
            hold_seconds: integer(),
            reps: integer(),
            sides: sides() | nil,
            modality: String.t() | nil,
            intensity_rpe: integer() | nil,
            body_part: String.t() | nil,
            pnf: PnfSpec.t() | nil
          }
  end

  defmodule Habit do
    @moduledoc "Habit tracking activity"
    defstruct [:category, :target, :target_unit, :frequency, :reminders, meta: %{}]

    @type category :: :hydration | :sleep | :steps | :screen_time | :custom | String.t()

    @type t :: %__MODULE__{
            category: category(),
            target: number(),
            target_unit: String.t(),
            frequency: String.t() | nil,
            reminders: [Time.t()] | nil,
            meta: map()
          }
  end

  defmodule SimpleActivity do
    @moduledoc "Simple activity for warmups/cooldowns"
    defstruct [:name, :duration, :params, meta: %{}]

    @type t :: %__MODULE__{
            name: String.t(),
            duration: Duration.t() | nil,
            params: [String.t()] | nil,
            meta: map()
          }
  end

  defmodule SubPlan do
    @moduledoc "Sub-plan inclusion activity (schema v1.5.0+)"
    defstruct [:sub_plan_ref, :name, meta: %{}]

    @type t :: %__MODULE__{
            sub_plan_ref: String.t(),
            name: String.t() | nil,
            meta: map()
          }
  end

  # =============================================================================
  # Progress Section
  # =============================================================================

  defmodule Progress do
    @moduledoc "Progress tracking configuration"
    defstruct [:checkpoints, :points, :achievements, :streaks, meta: %{}]

    @type t :: %__MODULE__{
            checkpoints: [Checkpoint.t()] | nil,
            points: PointsConfig.t() | nil,
            achievements: [Achievement.t()] | nil,
            streaks: StreaksConfig.t() | nil,
            meta: map()
          }
  end

  defmodule MeasurementSpec do
    @moduledoc "Typed measurement specification (schema v1.6.0+)"
    defstruct [:metric, :questionnaire, :note]

    @type t :: %__MODULE__{
            metric: String.t(),
            questionnaire: String.t() | nil,
            note: String.t() | nil
          }
  end

  defmodule Checkpoint do
    @moduledoc "Progress checkpoint"
    defstruct [:name, :trigger, :measurements, :questions]

    @type trigger :: {:time, integer(), integer()} | :completion | :manual
    @type measurement :: String.t() | MeasurementSpec.t()

    @type t :: %__MODULE__{
            name: String.t(),
            trigger: trigger(),
            measurements: [measurement()] | nil,
            questions: [String.t()] | nil
          }
  end

  defmodule PointsConfig do
    @moduledoc "Points system configuration"
    defstruct [:enabled, :rules]

    @type t :: %__MODULE__{
            enabled: boolean(),
            rules: [{String.t(), integer()}] | nil
          }
  end

  defmodule Achievement do
    @moduledoc "Achievement definition"
    defstruct [:id, :name, :description, :condition, :condition_value, :points]

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            description: String.t(),
            condition: String.t(),
            condition_value: integer(),
            points: integer()
          }
  end

  defmodule StreaksConfig do
    @moduledoc "Streaks configuration"
    defstruct [:enabled, :types]

    @type t :: %__MODULE__{
            enabled: boolean(),
            types: [String.t()] | nil
          }
  end

  # =============================================================================
  # Notifications & Rendering
  # =============================================================================

  defmodule Notification do
    @moduledoc "Notification configuration"
    defstruct [:id, :enabled, :timing, :message]

    @type t :: %__MODULE__{
            id: String.t(),
            enabled: boolean(),
            timing: {Duration.t(), String.t()} | nil,
            message: String.t()
          }
  end

  defmodule Rendering do
    @moduledoc "Rendering/display configuration"
    defstruct [:primary_color, :secondary_color, :accent_color, :icons, :difficulty_colors]

    @type t :: %__MODULE__{
            primary_color: String.t() | nil,
            secondary_color: String.t() | nil,
            accent_color: String.t() | nil,
            icons: %{String.t() => String.t()} | nil,
            difficulty_colors: %{String.t() => String.t()} | nil
          }
  end

  # =============================================================================
  # Common Types
  # =============================================================================

  defmodule Duration do
    @moduledoc "Duration value with unit"
    defstruct [:value, :unit]

    @type time_unit :: :seconds | :minutes | :hours | :days | :weeks

    @type t :: %__MODULE__{
            value: number(),
            unit: time_unit()
          }
  end
end
