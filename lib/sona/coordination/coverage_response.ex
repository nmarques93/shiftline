defmodule Sona.Coordination.CoverageResponse do
  use Ecto.Schema
  import Ecto.Changeset

  # "pending" marks a staff member who has viewed the request but not answered
  # yet, so seen/responded/acknowledged remain three distinct states.
  # Questions are not answers — they are activity events, so that asking one
  # never overwrites an offer (see `Sona.Coordination.ask_question/3`).
  @response_types ~w(pending accepted partial declined)

  schema "coverage_responses" do
    field :response_type, :string
    field :note, :string
    field :cover_start_time, :time
    field :cover_end_time, :time
    field :viewed_at, :utc_datetime
    field :acknowledged_at, :utc_datetime

    belongs_to :coverage_request, Sona.Coordination.CoverageRequest
    belongs_to :staff_member, Sona.Coordination.StaffMember

    timestamps(type: :utc_datetime)
  end

  def response_types, do: @response_types

  def changeset(response, attrs) do
    response
    |> cast(attrs, [
      :response_type,
      :note,
      :cover_start_time,
      :cover_end_time,
      :viewed_at,
      :acknowledged_at,
      :coverage_request_id,
      :staff_member_id
    ])
    |> validate_required([:response_type, :coverage_request_id, :staff_member_id])
    |> validate_inclusion(:response_type, @response_types)
    |> unique_constraint([:coverage_request_id, :staff_member_id])
  end
end
