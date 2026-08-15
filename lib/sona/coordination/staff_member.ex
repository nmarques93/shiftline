defmodule Sona.Coordination.StaffMember do
  use Ecto.Schema
  import Ecto.Changeset

  @languages ~w(English Spanish French)

  schema "staff_members" do
    field :name, :string
    field :role, :string
    field :department, :string
    field :language, :string
    field :is_supervisor, :boolean, default: false
    field :notify_in_app, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def languages, do: @languages

  def changeset(staff_member, attrs) do
    staff_member
    |> cast(attrs, [:name, :role, :department, :language, :is_supervisor, :notify_in_app])
    |> validate_required([:name, :role, :department, :language])
    |> validate_inclusion(:language, @languages)
  end

  @doc """
  Changeset for the settings a staff member controls themselves.

  Name, role, department and supervisor status are deliberately absent:
  in a workforce product those are operator-controlled, and since
  `Sona.Coordination.approve/3` gates on `is_supervisor`, a self-service
  form that could cast it would be a privilege escalation. The cast list
  is the guard — a crafted form submission cannot reach those fields.
  """
  def settings_changeset(staff_member, attrs) do
    staff_member
    |> cast(attrs, [:language, :notify_in_app])
    |> validate_required([:language])
    |> validate_inclusion(:language, @languages)
  end
end
