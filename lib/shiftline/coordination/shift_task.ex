defmodule Shiftline.Coordination.ShiftTask do
  @moduledoc """
  A unit of work on a shift, owned by exactly one person or by nobody yet.

  Named `ShiftTask` rather than `Task` so it does not shadow Elixir's `Task`,
  which the application uses for background translation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(todo in_progress done)

  schema "shift_tasks" do
    field :title, :string
    field :department, :string
    field :status, :string, default: "todo"
    field :shift_date, :date
    field :due_time, :time
    field :location, :string

    belongs_to :assignee, Shiftline.Coordination.StaffMember
    belongs_to :created_by, Shiftline.Coordination.StaffMember

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :department,
      :status,
      :shift_date,
      :due_time,
      :location,
      :assignee_id,
      :created_by_id
    ])
    |> validate_required([:title, :department, :status, :shift_date])
    |> validate_length(:title, min: 3, max: 140)
    |> validate_inclusion(:status, @statuses)
  end
end
