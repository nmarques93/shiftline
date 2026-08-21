defmodule Shiftline.Repo.Migrations.AddNotificationPreferenceToStaffMembers do
  use Ecto.Migration

  def change do
    alter table(:staff_members) do
      # In-app alerts are the one delivery channel this prototype actually
      # has, so it is the one that is stored and honoured. Push and SMS are
      # shown in Profile as unavailable rather than as inert switches.
      add :notify_in_app, :boolean, null: false, default: true
    end
  end
end
