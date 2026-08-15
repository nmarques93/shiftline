defmodule Sona.Coordination.CoverageRequest do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(open contacting claimed approved resolved)
  @urgencies ~w(Urgent High Normal)

  schema "coverage_requests" do
    field :absent_name, :string
    field :department, :string
    field :role, :string
    field :shift_date, :date
    field :start_time, :time
    field :end_time, :time
    field :location, :string
    field :urgency, :string
    field :reason, :string
    field :handoff_note, :string
    field :status, :string
    field :handoff_acknowledged_at, :utc_datetime

    belongs_to :selected_replacement, Sona.Coordination.StaffMember
    has_many :responses, Sona.Coordination.CoverageResponse
    has_many :activity_events, Sona.Coordination.ActivityEvent

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :absent_name,
      :department,
      :role,
      :shift_date,
      :start_time,
      :end_time,
      :location,
      :urgency,
      :reason,
      :handoff_note,
      :status,
      :selected_replacement_id,
      :handoff_acknowledged_at
    ])
    |> validate_required([
      :absent_name,
      :department,
      :role,
      :shift_date,
      :start_time,
      :end_time,
      :location,
      :reason,
      :status
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:urgency, @urgencies)
    |> validate_shift_window()
  end

  def urgencies, do: @urgencies

  defp validate_shift_window(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && Time.compare(start_time, end_time) != :lt do
      add_error(changeset, :end_time, "must be after the start time")
    else
      changeset
    end
  end
end
