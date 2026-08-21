defmodule Shiftline.Repo.Migrations.AddCoverWindowToCoverageResponses do
  use Ecto.Migration

  def change do
    alter table(:coverage_responses) do
      # Partial offers carry the structured window they cover, so the
      # remaining gap can be computed instead of implied by free text.
      add :cover_start_time, :time
      add :cover_end_time, :time
    end
  end
end
