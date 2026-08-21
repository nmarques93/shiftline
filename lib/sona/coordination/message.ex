defmodule Sona.Coordination.Message do
  @moduledoc """
  One thing a person said, addressed either to a department channel or to a
  single colleague.

  Exactly one of `department` and `recipient_id` is set; the database enforces
  it with a check constraint, because a message with both would be readable by
  an audience nobody chose.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :body, :string
    field :department, :string
    field :urgent, :boolean, default: false
    field :pinned, :boolean, default: false

    belongs_to :sender, Sona.Coordination.StaffMember
    belongs_to :recipient, Sona.Coordination.StaffMember

    has_many :reads, Sona.Coordination.MessageRead

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body, :department, :recipient_id, :sender_id, :urgent, :pinned])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body, :sender_id])
    |> validate_length(:body, min: 1, max: 2000)
    |> validate_audience()
    |> check_constraint(:department, name: :one_audience)
  end

  defp validate_audience(changeset) do
    department = get_field(changeset, :department)
    recipient_id = get_field(changeset, :recipient_id)

    case {department, recipient_id} do
      {nil, nil} ->
        add_error(changeset, :department, "needs a department or a recipient")

      {dept, id} when not is_nil(dept) and not is_nil(id) ->
        add_error(changeset, :department, "cannot be both a channel and a direct message")

      _one ->
        changeset
    end
  end
end
