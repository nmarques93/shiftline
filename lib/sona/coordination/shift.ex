defmodule Sona.Coordination.Shift do
  @moduledoc """
  A block of covered time belonging to a department.

  A shift is deliberately *not* one person's rostered slot. Who works it is a
  separate fact (`Sona.Coordination.ShiftAssignment`), because the two things
  this app already does need a shift to exist independently of its people:
  work can be posted to a shift nobody has claimed, and a coverage request is
  raised precisely when a shift has no one on it.

  `starts_at` / `ends_at` are UTC datetimes rather than a date plus a
  time-of-day, so a night audit running 22:00 to 06:00 is representable and
  sorts correctly.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @sources ~w(manual import)

  schema "shifts" do
    field :department, :string
    field :role, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :location, :string
    field :source, :string, default: "manual"
    field :external_id, :string

    has_many :assignments, Sona.Coordination.ShiftAssignment
    has_many :staff_members, through: [:assignments, :staff_member]

    timestamps(type: :utc_datetime)
  end

  def sources, do: @sources

  def changeset(shift, attrs) do
    shift
    |> cast(attrs, [
      :department,
      :role,
      :starts_at,
      :ends_at,
      :location,
      :source,
      :external_id
    ])
    |> validate_required([:department, :role, :starts_at, :ends_at])
    |> validate_inclusion(:source, @sources)
    |> validate_window()
    |> unique_constraint([:source, :external_id])
  end

  # Comparing datetimes rather than times of day is the whole reason for the
  # column types: this accepts a shift that crosses midnight and still rejects
  # one that ends before it starts.
  defp validate_window(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(ends_at, starts_at) != :gt do
      add_error(changeset, :ends_at, "must be after the start")
    else
      changeset
    end
  end

  @doc "Length of the shift in minutes."
  def duration_minutes(%__MODULE__{starts_at: starts_at, ends_at: ends_at}),
    do: DateTime.diff(ends_at, starts_at, :second) |> div(60)

  @doc "Whether `at` falls inside the shift, start inclusive and end exclusive."
  def covers?(%__MODULE__{starts_at: starts_at, ends_at: ends_at}, %DateTime{} = at) do
    DateTime.compare(at, starts_at) != :lt and DateTime.compare(at, ends_at) == :lt
  end
end
