defmodule Sona.Coordination.ShiftsTest do
  @moduledoc """
  The shift roster: who is on, when, and who may say so.

  The cases worth having are the ones a date-plus-time-of-day model would get
  wrong (a shift crossing midnight) and the ones a trusting context would get
  wrong (rostering another department's staff).
  """
  use Sona.DataCase, async: true

  alias Sona.Coordination.{Shift, ShiftAssignment, Shifts, StaffMember}
  alias Sona.Demo
  alias Sona.Repo

  setup do
    Demo.seed_demo()

    %{
      maya: Demo.supervisor_persona(),
      luis: Demo.frontline_persona(),
      rosa: Repo.get_by!(StaffMember, name: "Rosa Iglesias"),
      mei: Repo.get_by!(StaffMember, name: "Mei Tanaka"),
      dana: Repo.get_by!(StaffMember, name: "Dana Kim"),
      theo: Repo.get_by!(StaffMember, name: "Theo Martin")
    }
  end

  defp attrs(overrides \\ %{}) do
    today = Date.utc_today()

    Map.merge(
      %{
        "role" => "Front Desk Agent",
        "starts_at" => DateTime.new!(today, ~T[09:00:00], "Etc/UTC"),
        "ends_at" => DateTime.new!(today, ~T[17:00:00], "Etc/UTC"),
        "location" => "Lobby front desk"
      },
      overrides
    )
  end

  describe "create/2" do
    test "a supervisor can add a shift to their own department", %{maya: maya} do
      assert {:ok, shift} = Shifts.create(maya.id, attrs())

      assert shift.department == "Front Office"
      assert shift.source == "manual"
    end

    test "frontline staff cannot", %{luis: luis} do
      assert {:error, :not_supervisor} = Shifts.create(luis.id, attrs())
    end

    test "a shift may cross midnight", %{maya: maya} do
      today = Date.utc_today()

      assert {:ok, shift} =
               Shifts.create(
                 maya.id,
                 attrs(%{
                   "role" => "Night Auditor",
                   "starts_at" => DateTime.new!(today, ~T[22:00:00], "Etc/UTC"),
                   "ends_at" => DateTime.new!(Date.add(today, 1), ~T[06:00:00], "Etc/UTC")
                 })
               )

      # The reason the columns are datetimes: a date plus time-of-day model
      # would either reject this or record eight hours as minus sixteen.
      assert Shift.duration_minutes(shift) == 480
    end

    test "a shift cannot end before it starts", %{maya: maya} do
      today = Date.utc_today()

      assert {:error, changeset} =
               Shifts.create(
                 maya.id,
                 attrs(%{"ends_at" => DateTime.new!(today, ~T[08:00:00], "Etc/UTC")})
               )

      assert "must be after the start" in errors_on(changeset).ends_at
    end
  end

  describe "assignment" do
    setup %{maya: maya} do
      {:ok, shift} = Shifts.create(maya.id, attrs())
      %{shift: shift}
    end

    test "a supervisor rosters someone in their department", %{shift: s, maya: maya, luis: luis} do
      assert {:ok, assignment} = Shifts.assign(s.id, luis.id, maya.id)
      assert assignment.status == "scheduled"
    end

    test "assigning twice updates rather than duplicates", %{shift: s, maya: maya, luis: luis} do
      {:ok, _} = Shifts.assign(s.id, luis.id, maya.id)
      assert {:ok, updated} = Shifts.mark_absent(s.id, luis.id, maya.id)

      assert updated.status == "absent"
      assert length(Shifts.get!(s.id).assignments) == 1
    end

    test "another department's staff cannot be rostered", %{shift: s, maya: maya, mei: mei} do
      assert {:error, :wrong_department} = Shifts.assign(s.id, mei.id, maya.id)
    end

    test "another department's supervisor cannot roster this shift", %{
      shift: s,
      rosa: rosa,
      luis: luis
    } do
      assert {:error, :wrong_department} = Shifts.assign(s.id, luis.id, rosa.id)
    end

    test "frontline staff cannot roster anyone", %{shift: s, luis: luis} do
      assert {:error, :not_supervisor} = Shifts.assign(s.id, luis.id, luis.id)
    end

    test "unassigning removes the row", %{shift: s, maya: maya, luis: luis} do
      {:ok, _} = Shifts.assign(s.id, luis.id, maya.id)

      assert {:ok, _} = Shifts.unassign(s.id, luis.id, maya.id)
      assert Shifts.get!(s.id).assignments == []
      assert {:error, :not_assigned} = Shifts.unassign(s.id, luis.id, maya.id)
    end
  end

  describe "reads" do
    test "list/2 is scoped to the reader's department", %{luis: luis, mei: mei} do
      front_office = Shifts.list(luis)
      housekeeping = Shifts.list(mei)

      refute front_office == []
      assert Enum.all?(front_office, &(&1.department == "Front Office"))
      assert Enum.all?(housekeeping, &(&1.department == "Housekeeping"))
    end

    test "current_for/2 finds the shift covering a moment", %{dana: dana} do
      # Dana is seeded onto the night audit, which starts at 22:00 and runs
      # into tomorrow — the case that only works with datetimes.
      at = DateTime.new!(Date.add(Date.utc_today(), 1), ~T[02:00:00], "Etc/UTC")

      assert %Shift{role: "Night Auditor"} = Shifts.current_for(dana, at)
    end

    test "current_for/2 ignores a shift the person is absent from", %{maya: maya, theo: theo} do
      at = DateTime.new!(Date.utc_today(), ~T[15:00:00], "Etc/UTC")

      # Theo is seeded absent from the evening shift — the fact the seeded
      # coverage request exists because of.
      assert Shifts.current_for(theo, at) == nil
      assert %Shift{} = Shifts.current_for(maya, at)
    end

    test "uncovered/2 finds shifts nobody is working", %{maya: maya} do
      tomorrow = Date.add(Date.utc_today(), 1)

      {:ok, orphan} =
        Shifts.create(
          maya.id,
          attrs(%{
            "starts_at" => DateTime.new!(tomorrow, ~T[09:00:00], "Etc/UTC"),
            "ends_at" => DateTime.new!(tomorrow, ~T[17:00:00], "Etc/UTC")
          })
        )

      assert orphan.id in Enum.map(Shifts.uncovered("Front Office"), & &1.id)
    end
  end

  describe "update and delete" do
    setup %{maya: maya} do
      {:ok, shift} = Shifts.create(maya.id, attrs())
      %{shift: shift}
    end

    test "a supervisor can change the location", %{shift: s, maya: maya} do
      assert {:ok, updated} = Shifts.update(s.id, %{"location" => "Back office"}, maya.id)
      assert updated.location == "Back office"
    end

    test "deleting takes its assignments with it", %{shift: s, maya: maya, luis: luis} do
      {:ok, _} = Shifts.assign(s.id, luis.id, maya.id)

      assert {:ok, _} = Shifts.delete(s.id, maya.id)
      assert Repo.get(Shift, s.id) == nil
      assert Repo.get_by(ShiftAssignment, shift_id: s.id) == nil
    end

    test "another department's supervisor cannot delete it", %{shift: s, rosa: rosa} do
      assert {:error, :wrong_department} = Shifts.delete(s.id, rosa.id)
    end
  end
end
