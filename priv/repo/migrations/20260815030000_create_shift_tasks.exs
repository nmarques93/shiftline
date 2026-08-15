defmodule Sona.Repo.Migrations.CreateShiftTasks do
  use Ecto.Migration

  def change do
    # Named shift_tasks rather than tasks so the schema module does not shadow
    # Elixir's own Task, which this app uses for background work.
    create table(:shift_tasks) do
      add :title, :string, null: false
      add :department, :string, null: false
      add :status, :string, null: false
      add :shift_date, :date, null: false
      add :due_time, :time
      add :location, :string

      # Unassigned tasks are a real state: work posted to a department that
      # nobody has picked up yet.
      add :assignee_id, references(:staff_members, on_delete: :nilify_all)
      add :created_by_id, references(:staff_members, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:shift_tasks, [:department, :shift_date])
    create index(:shift_tasks, [:assignee_id])
  end
end
