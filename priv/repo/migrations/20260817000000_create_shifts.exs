defmodule Sona.Repo.Migrations.CreateShifts do
  use Ecto.Migration

  def change do
    # A shift is the department's block of covered time, not one person's
    # rostered slot. Assignment is a separate fact about it (see below), so a
    # shift can exist with nobody on it — which is exactly the state a coverage
    # request is raised against.
    create table(:shifts) do
      add :department, :string, null: false
      add :role, :string, null: false

      # Datetimes rather than date + time: the roster includes a night audit,
      # and a 22:00-06:00 shift is either unrepresentable or silently wrong
      # under a date-plus-time-of-day model.
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false

      add :location, :string

      # Sona reads rotas rather than authoring them: shifts are expected to
      # arrive from a workforce system, with manual entry as the fallback for
      # customers who have none.
      add :source, :string, null: false, default: "manual"
      add :external_id, :string

      timestamps(type: :utc_datetime)
    end

    create index(:shifts, [:department, :starts_at])

    # An imported shift must not be duplicated by a re-sync. Partial, because
    # manually created shifts have no external id and many may be null.
    create unique_index(:shifts, [:source, :external_id], where: "external_id IS NOT NULL")

    create table(:shift_assignments) do
      add :shift_id, references(:shifts, on_delete: :delete_all), null: false
      add :staff_member_id, references(:staff_members, on_delete: :delete_all), null: false

      # "absent" is how an absence becomes a fact the system can reason about,
      # rather than a name typed into a coverage request.
      add :status, :string, null: false, default: "scheduled"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shift_assignments, [:shift_id, :staff_member_id])
    create index(:shift_assignments, [:staff_member_id])
  end
end
