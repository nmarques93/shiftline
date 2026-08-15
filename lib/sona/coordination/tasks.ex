defmodule Sona.Coordination.Tasks do
  @moduledoc """
  The shift task board: the work a department owes today, who owns each
  piece, and how far along it is.

  Separate from coverage because it answers a different question. Coverage
  asks "who will stand in for the person who is missing?" and runs through a
  state machine to a single approved replacement. A task asks "who is doing
  this?" and is owned by one person at a time, claimable by anyone in the
  department. The two share a team and a shift, and nothing else.

  Every write here is guarded by department and ownership, so a status is a
  statement by someone accountable for the work rather than by whoever
  happened to have the page open.
  """

  import Ecto.Query

  alias Sona.Coordination.{Notifier, ShiftTask, StaffMember}
  alias Sona.Repo

  @statuses ~w(todo in_progress done)

  def statuses, do: @statuses

  @doc """
  Everyone a task can be handed to: the staff member's own department,
  supervisors included, since supervisors carry work too.
  """
  def assignable_staff(%StaffMember{} = staff) do
    Repo.all(
      from person in StaffMember,
        where: person.department == ^staff.department,
        order_by: [asc: person.name]
    )
  end

  @doc """
  Tasks for a staff member's department on a given day, unassigned first so
  work nobody owns is the thing you see.
  """
  def list(%StaffMember{} = staff, shift_date \\ nil) do
    date = shift_date || Date.utc_today()

    Repo.all(
      from task in ShiftTask,
        where: task.department == ^staff.department and task.shift_date == ^date,
        order_by: [asc: is_nil(task.assignee_id) == false, asc: task.due_time, asc: task.id],
        preload: [:assignee]
    )
  end

  @doc """
  Creates a task for a department. Only a supervisor can put work on the
  board; `:assignee_id` is optional, and leaving it out posts the task to the
  department for someone to claim.
  """
  def create(supervisor_id, attrs) do
    supervisor = Repo.get!(StaffMember, supervisor_id)

    if supervisor.is_supervisor do
      attrs =
        attrs
        |> Map.new(fn {key, value} -> {to_string(key), value} end)
        |> Map.put_new("department", supervisor.department)
        |> Map.put_new("shift_date", Date.utc_today())
        |> Map.put("created_by_id", supervisor.id)
        |> Map.put("status", "todo")
        |> normalise_assignee()

      case %ShiftTask{} |> ShiftTask.changeset(attrs) |> Repo.insert() do
        {:ok, task} ->
          Notifier.translate_task_content([task.title])
          Notifier.broadcast_tasks()
          {:ok, Repo.preload(task, :assignee)}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :not_supervisor}
    end
  end

  @doc """
  Assigns a task to someone, or clears the assignment with `nil`.

  Only a supervisor may assign work to another person, and only within their
  own department — a supervisor cannot hand a task to another department's
  staff, and staff cannot be assigned work outside theirs.
  """
  def assign(task_id, assignee_id, actor_id) do
    task = Repo.get!(ShiftTask, task_id)
    actor = Repo.get!(StaffMember, actor_id)
    assignee = assignee_id && Repo.get(StaffMember, assignee_id)

    cond do
      not actor.is_supervisor ->
        {:error, :not_supervisor}

      actor.department != task.department ->
        {:error, :wrong_department}

      assignee_id && is_nil(assignee) ->
        {:error, :unknown_staff}

      assignee && assignee.department != task.department ->
        {:error, :wrong_department}

      true ->
        update!(task, %{assignee_id: assignee_id})
    end
  end

  @doc """
  Lets a staff member take ownership of unclaimed work in their department.

  This is the frontline half of "confirm ownership": nobody has to wait for a
  supervisor to hand out a task that is already sitting there.
  """
  def claim(task_id, staff_id) do
    task = Repo.get!(ShiftTask, task_id)
    staff = Repo.get!(StaffMember, staff_id)

    cond do
      staff.department != task.department -> {:error, :wrong_department}
      not is_nil(task.assignee_id) -> {:error, :already_assigned}
      true -> update!(task, %{assignee_id: staff.id})
    end
  end

  @doc """
  Moves a task between `todo`, `in_progress` and `done`.

  Only the person who owns the task or a supervisor in its department can
  change it.
  """
  def update_status(task_id, status, actor_id) when status in @statuses do
    task = Repo.get!(ShiftTask, task_id)
    actor = Repo.get!(StaffMember, actor_id)

    cond do
      actor.department != task.department ->
        {:error, :wrong_department}

      task.assignee_id != actor.id and not actor.is_supervisor ->
        {:error, :not_task_owner}

      is_nil(task.assignee_id) ->
        {:error, :unassigned}

      true ->
        update!(task, %{status: status})
    end
  end

  defp update!(task, attrs) do
    updated = task |> ShiftTask.changeset(attrs) |> Repo.update!()
    Notifier.broadcast_tasks()
    {:ok, Repo.preload(updated, :assignee, force: true)}
  end

  # A blank select value arrives as "" and means "nobody".
  defp normalise_assignee(attrs) do
    case Map.get(attrs, "assignee_id") do
      "" -> Map.put(attrs, "assignee_id", nil)
      _other -> attrs
    end
  end
end
