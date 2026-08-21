defmodule Shiftline.Coordination.ActivityEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(created response question approved handoff team)

  schema "activity_events" do
    field :kind, :string
    field :body, :string

    belongs_to :coverage_request, Shiftline.Coordination.CoverageRequest
    belongs_to :actor, Shiftline.Coordination.StaffMember

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:kind, :body, :coverage_request_id, :actor_id])
    |> validate_required([:kind, :body, :coverage_request_id])
    |> validate_inclusion(:kind, @kinds)
  end
end
