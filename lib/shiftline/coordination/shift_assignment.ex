defmodule Shiftline.Coordination.ShiftAssignment do
  @moduledoc """
  Who is working a shift, and in what state.

  `scheduled` is the ordinary case. `absent` is what a supervisor records when
  someone cannot make it — the fact a coverage request is raised from, rather
  than a name typed into a form. `covering` marks a replacement who took the
  shift on.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(scheduled absent covering)

  schema "shift_assignments" do
    field :status, :string, default: "scheduled"

    belongs_to :shift, Shiftline.Coordination.Shift
    belongs_to :staff_member, Shiftline.Coordination.StaffMember

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:shift_id, :staff_member_id, :status])
    |> validate_required([:shift_id, :staff_member_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:shift_id, :staff_member_id])
    |> foreign_key_constraint(:shift_id)
    |> foreign_key_constraint(:staff_member_id)
  end
end
