defmodule Shiftline.Repo.Migrations.CreateDemoTables do
  use Ecto.Migration

  def change do
    create table(:staff_members) do
      add :name, :string, null: false
      add :role, :string, null: false
      add :department, :string, null: false
      add :language, :string, null: false, default: "English"
      add :is_supervisor, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create table(:coverage_requests) do
      add :absent_name, :string, null: false
      add :department, :string, null: false
      add :role, :string, null: false
      add :shift_date, :date, null: false
      add :start_time, :time, null: false
      add :end_time, :time, null: false
      add :location, :string, null: false
      add :urgency, :string, null: false, default: "Urgent"
      add :reason, :text, null: false
      add :handoff_note, :text
      add :status, :string, null: false, default: "open"
      add :selected_replacement_id, references(:staff_members, on_delete: :nilify_all)
      add :handoff_acknowledged_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create table(:coverage_responses) do
      add :coverage_request_id, references(:coverage_requests, on_delete: :delete_all),
        null: false

      add :staff_member_id, references(:staff_members, on_delete: :delete_all), null: false
      add :response_type, :string, null: false
      add :note, :text
      add :viewed_at, :utc_datetime
      add :acknowledged_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:coverage_responses, [:coverage_request_id, :staff_member_id])

    create table(:activity_events) do
      add :coverage_request_id, references(:coverage_requests, on_delete: :delete_all),
        null: false

      add :actor_id, references(:staff_members, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end
