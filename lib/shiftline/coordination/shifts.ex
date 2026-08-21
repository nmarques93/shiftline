defmodule Shiftline.Coordination.Shifts do
  @moduledoc """
  Shifts and who is assigned to them.

  Shiftline reads rotas rather than authoring them — the product sits on top of a
  workforce system rather than replacing it — so this is deliberately thin:
  enough CRUD to hold a schedule that arrived from somewhere else, plus manual
  entry for customers with no such system. There is no availability, no
  recurrence, no labour cost and no auto-assignment, and adding them here would
  be the wrong direction.

  Guards match `Shiftline.Coordination.Tasks`: writes are supervisor-only and
  department-scoped, and the actor is always an explicit id that gets checked
  rather than trusted.
  """

  import Ecto.Query

  alias Shiftline.Coordination.{Notifier, Shift, ShiftAssignment, StaffMember}
  alias Shiftline.Repo

  ## Reads

  @doc """
  Shifts for a staff member's department, earliest first.

  `:from` and `:to` bound the window and both default to a day either side of
  now, which is the range a frontline view cares about.
  """
  def list(%StaffMember{} = staff, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    from_at = Keyword.get(opts, :from, DateTime.add(now, -1, :day))
    to_at = Keyword.get(opts, :to, DateTime.add(now, 1, :day))

    Repo.all(
      from shift in Shift,
        where: shift.department == ^staff.department,
        where: shift.starts_at < ^to_at and shift.ends_at > ^from_at,
        order_by: [asc: shift.starts_at, asc: shift.id],
        preload: [assignments: :staff_member]
    )
  end

  def get!(id), do: Shift |> Repo.get!(id) |> Repo.preload(assignments: :staff_member)

  @doc """
  The shift this person is on at `at`, or `nil`.

  This is what the Today strip should read instead of hardcoded times.
  """
  def current_for(%StaffMember{} = staff, at \\ DateTime.utc_now()) do
    Repo.one(
      from shift in Shift,
        join: assignment in ShiftAssignment,
        on: assignment.shift_id == shift.id,
        where: assignment.staff_member_id == ^staff.id,
        where: assignment.status != "absent",
        where: shift.starts_at <= ^at and shift.ends_at > ^at,
        order_by: [asc: shift.starts_at],
        limit: 1,
        preload: [assignments: :staff_member]
    )
  end

  @doc "Shifts in a department that nobody is scheduled to work."
  def uncovered(department, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.all(
      from shift in Shift,
        left_join: assignment in ShiftAssignment,
        on: assignment.shift_id == shift.id and assignment.status != "absent",
        where: shift.department == ^department and shift.ends_at > ^now,
        group_by: shift.id,
        having: count(assignment.id) == 0,
        order_by: [asc: shift.starts_at]
    )
  end

  @doc """
  Builds a shift's window from the three values a form actually collects: a
  date, a start time and an end time.

  An end at or before the start means the shift runs into the next day. That
  is a rostering rule rather than form parsing — 22:00 to 06:00 is a night
  audit, not a mistake — so it lives here and is tested here rather than being
  re-derived by whatever screen happens to collect the times.
  """
  def window_from_form(%Date{} = date, %Time{} = start_time, %Time{} = end_time) do
    ends_on =
      if Time.compare(end_time, start_time) in [:lt, :eq], do: Date.add(date, 1), else: date

    {DateTime.new!(date, start_time, "Etc/UTC"), DateTime.new!(ends_on, end_time, "Etc/UTC")}
  end

  ## Writes

  @doc """
  Creates a shift. Supervisor-only, and it defaults to the supervisor's own
  department rather than accepting one from the caller.
  """
  def create(supervisor_id, attrs) do
    supervisor = Repo.get!(StaffMember, supervisor_id)

    if supervisor.is_supervisor do
      attrs =
        attrs
        |> Map.new(fn {key, value} -> {to_string(key), value} end)
        |> Map.put_new("department", supervisor.department)

      %Shift{}
      |> Shift.changeset(attrs)
      |> Repo.insert()
      |> broadcast_result()
    else
      {:error, :not_supervisor}
    end
  end

  @doc "Updates a shift's details. Supervisor-only, within their own department."
  def update(shift_id, attrs, actor_id) do
    with {:ok, shift, _actor} <- authorize(shift_id, actor_id) do
      shift
      |> Shift.changeset(Map.new(attrs, fn {k, v} -> {to_string(k), v} end))
      |> Repo.update()
      |> broadcast_result()
    end
  end

  @doc "Deletes a shift and its assignments. Supervisor-only, own department."
  def delete(shift_id, actor_id) do
    with {:ok, shift, _actor} <- authorize(shift_id, actor_id) do
      shift |> Repo.delete() |> broadcast_result()
    end
  end

  @doc """
  Puts someone on a shift, or updates their status on it.

  Both the actor and the person being scheduled must belong to the shift's
  department — a supervisor cannot roster another department's staff.
  """
  def assign(shift_id, staff_id, actor_id, status \\ "scheduled") do
    with {:ok, shift, _actor} <- authorize(shift_id, actor_id),
         {:ok, staff} <- fetch_staff(staff_id, shift.department) do
      existing =
        Repo.get_by(ShiftAssignment, shift_id: shift.id, staff_member_id: staff.id) ||
          %ShiftAssignment{}

      existing
      |> ShiftAssignment.changeset(%{
        "shift_id" => shift.id,
        "staff_member_id" => staff.id,
        "status" => status
      })
      |> Repo.insert_or_update()
      |> broadcast_result()
    end
  end

  @doc """
  Records that someone will not be working a shift they were scheduled for.

  This is the fact a coverage request should be raised from, which is why it
  is a status change rather than a deletion — the roster still says they were
  meant to be there.
  """
  def mark_absent(shift_id, staff_id, actor_id),
    do: assign(shift_id, staff_id, actor_id, "absent")

  @doc "Takes someone off a shift entirely."
  def unassign(shift_id, staff_id, actor_id) do
    with {:ok, shift, _actor} <- authorize(shift_id, actor_id) do
      case Repo.get_by(ShiftAssignment, shift_id: shift.id, staff_member_id: staff_id) do
        nil -> {:error, :not_assigned}
        assignment -> assignment |> Repo.delete() |> broadcast_result()
      end
    end
  end

  ## Helpers

  defp authorize(shift_id, actor_id) do
    shift = Repo.get!(Shift, shift_id)
    actor = Repo.get!(StaffMember, actor_id)

    cond do
      not actor.is_supervisor -> {:error, :not_supervisor}
      actor.department != shift.department -> {:error, :wrong_department}
      true -> {:ok, shift, actor}
    end
  end

  defp fetch_staff(staff_id, department) do
    case Repo.get(StaffMember, staff_id) do
      nil -> {:error, :unknown_staff}
      %StaffMember{department: ^department} = staff -> {:ok, staff}
      _other -> {:error, :wrong_department}
    end
  end

  defp broadcast_result({:ok, record}) do
    Notifier.broadcast_shifts()
    {:ok, record}
  end

  defp broadcast_result({:error, _} = error), do: error
end
