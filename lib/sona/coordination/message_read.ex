defmodule Sona.Coordination.MessageRead do
  @moduledoc """
  Who has seen a message, and who has acknowledged it.

  Deliberately the same two-timestamp shape as `Sona.Coordination.CoverageResponse`:
  opening a conversation records `viewed_at`, and pressing the button on an
  urgent message records `acknowledged_at`. A supervisor asking "did it land?"
  is asking about the second one.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "message_reads" do
    field :viewed_at, :utc_datetime
    field :acknowledged_at, :utc_datetime

    belongs_to :message, Sona.Coordination.Message
    belongs_to :staff_member, Sona.Coordination.StaffMember

    timestamps(type: :utc_datetime)
  end

  def changeset(read, attrs) do
    read
    |> cast(attrs, [:message_id, :staff_member_id, :viewed_at, :acknowledged_at])
    |> validate_required([:message_id, :staff_member_id])
    |> unique_constraint([:message_id, :staff_member_id])
  end
end
