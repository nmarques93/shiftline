defmodule Shiftline.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :body, :text, null: false
      add :sender_id, references(:staff_members, on_delete: :delete_all), null: false
      # A message is addressed to exactly one audience: a department channel
      # or a single person. The check constraint below is the guard — an
      # ambiguous row is a message that could be delivered to the wrong people.
      add :department, :string
      add :recipient_id, references(:staff_members, on_delete: :delete_all)
      add :urgent, :boolean, null: false, default: false
      add :pinned, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:messages, :one_audience,
             check: """
             (department IS NOT NULL AND recipient_id IS NULL) OR
             (department IS NULL AND recipient_id IS NOT NULL)
             """
           )

    create index(:messages, [:department, :inserted_at])
    create index(:messages, [:recipient_id])
    create index(:messages, [:sender_id])

    # Read and acknowledgement status, one row per person per message. Same
    # shape as `coverage_responses`: viewed and acknowledged are separate
    # facts, because "I saw it" and "I will do it" are separate promises.
    create table(:message_reads) do
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :staff_member_id, references(:staff_members, on_delete: :delete_all), null: false
      add :viewed_at, :utc_datetime
      add :acknowledged_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:message_reads, [:message_id, :staff_member_id])
  end
end
