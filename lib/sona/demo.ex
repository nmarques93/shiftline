defmodule Sona.Demo do
  @moduledoc """
  Demo scaffolding: the seeded dataset and the two switchable personas that
  stand in for authentication.

  This lives outside `Sona.Coordination` on purpose. Everything in here is
  the part of the prototype that a real deployment deletes — fixture data, a
  reset button, and a persona switcher that hands out an identity with no
  proof of who is asking. Keeping it in the domain context would have meant
  seeding logic and business rules ageing together in one file, and would
  have blurred the one thing worth being unambiguous about: the domain
  guards below this line are real, and the identity above it is not.

  Authentication replaces `personas/0` and nothing else. The write functions
  in `Sona.Coordination` and `Sona.Coordination.Tasks` already take an actor
  id and already check department, role and ownership against it, so a real
  session would feed the same ids into the same guards.
  """

  import Ecto.Query

  alias Sona.Coordination.{
    ActivityEvent,
    CoverageRequest,
    CoverageResponse,
    Events,
    Notifier,
    ShiftTask,
    StaffMember
  }

  alias Sona.Repo

  # The frontline persona is pinned by name so the demo always lands on a
  # Spanish-speaking staff member and the translation story is visible on the
  # first screen.
  @frontline_persona "Luis Garcia"

  # Serializes concurrent seeding attempts (e.g. two first-time clients
  # mounting at once) within the seeding transaction.
  @seed_lock_key 571_113

  ## Personas

  def supervisor_persona do
    Repo.one!(
      from staff in StaffMember, where: staff.is_supervisor, order_by: [asc: staff.id], limit: 1
    )
  end

  def frontline_persona, do: Repo.get_by!(StaffMember, name: @frontline_persona)

  def personas, do: %{"supervisor" => supervisor_persona(), "frontline" => frontline_persona()}

  ## Seeding

  @doc """
  Reseeds the demo dataset when its structural anchors are missing: any
  staff, any coverage request, or either demo persona. It does not detect
  arbitrary corruption of an otherwise-anchored dataset — `Reset demo` is
  the recovery path for that. Safe to call from every mount: the
  check-and-seed runs in a transaction under an advisory lock, so
  concurrent callers cannot double-seed.
  """
  def ensure_demo_data do
    {:ok, seeded} =
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock($1)", [@seed_lock_key])

        if anchors_missing?() do
          delete_demo_data()
          {:seeded, seed_demo()}
        else
          :present
        end
      end)

    with {:seeded, request} <- seeded, do: Notifier.broadcast(request.id)
    :ok
  end

  defp anchors_missing? do
    Repo.aggregate(CoverageRequest, :count) == 0 or
      is_nil(Repo.one(from staff in StaffMember, where: staff.is_supervisor, limit: 1)) or
      is_nil(Repo.get_by(StaffMember, name: @frontline_persona))
  end

  def reset_demo do
    {:ok, request} =
      Repo.transaction(fn ->
        delete_demo_data()
        seed_demo()
      end)

    Notifier.broadcast(request.id)
    request
  end

  defp delete_demo_data do
    Repo.delete_all(ShiftTask)
    Repo.delete_all(ActivityEvent)
    Repo.delete_all(CoverageResponse)
    Repo.delete_all(CoverageRequest)
    Repo.delete_all(StaffMember)
  end

  def seed_demo do
    maya =
      insert_staff!("Maya Chen", "Front Office Supervisor", "English", is_supervisor: true)

    luis = insert_staff!("Luis Garcia", "Front Desk Agent", "Spanish")
    priya = insert_staff!("Priya Shah", "Front Desk Agent", "English")
    theo = insert_staff!("Theo Martin", "Front Desk Agent", "French")
    dana = insert_staff!("Dana Kim", "Night Auditor", "English")
    sofia = insert_staff!("Sofia Alvarez", "Front Desk Agent", "Spanish")
    _omar = insert_staff!("Omar Haddad", "Front Desk Agent", "French")
    _ana = insert_staff!("Ana Costa", "Night Auditor", "Spanish")

    # A second department, so that department-scoped eligibility is visible
    # rather than theoretical: a Housekeeping request never reaches the front
    # desk, and vice versa.
    _rosa =
      insert_staff!("Rosa Iglesias", "Housekeeping Supervisor", "Spanish",
        department: "Housekeeping",
        is_supervisor: true
      )

    _mei = insert_staff!("Mei Tanaka", "Room Attendant", "English", department: "Housekeeping")
    _yusuf = insert_staff!("Yusuf Demir", "Room Attendant", "French", department: "Housekeeping")

    _carla =
      insert_staff!("Carla Mendes", "Housekeeping Attendant", "Spanish",
        department: "Housekeeping"
      )

    request =
      Repo.insert!(%CoverageRequest{
        absent_name: "Jordan Lee",
        department: "Front Office",
        role: "Front Desk Agent",
        shift_date: Date.utc_today(),
        start_time: ~T[18:00:00],
        end_time: ~T[22:00:00],
        location: "Lobby front desk",
        urgency: "Urgent",
        reason:
          "Jordan is unexpectedly unavailable. We need front desk coverage for the evening shift.",
        handoff_note: "Please review VIP arrivals with Maya at 17:45.",
        # "claimed", not "open": Priya's partial offer below is seeded as an
        # existing row rather than replayed through `respond/4`, so the status
        # has to be set to what that call would have left behind. An offer
        # with the request still open is a state the workflow cannot reach,
        # and seeded data has no business inventing one.
        status: "claimed"
      })

    priya_offer =
      Repo.insert!(%CoverageResponse{
        coverage_request_id: request.id,
        staff_member_id: priya.id,
        response_type: "partial",
        note: "I can cover the first half.",
        cover_start_time: ~T[18:00:00],
        cover_end_time: ~T[20:00:00],
        viewed_at: now()
      })

    Repo.insert!(%CoverageResponse{
      coverage_request_id: request.id,
      staff_member_id: theo.id,
      response_type: "declined",
      note: "Already working in reservations.",
      viewed_at: now()
    })

    Repo.insert!(%CoverageResponse{
      coverage_request_id: request.id,
      staff_member_id: dana.id,
      response_type: "pending",
      viewed_at: now()
    })

    Events.record(
      request.id,
      maya.id,
      "created",
      "Maya created an urgent coverage request for the Front Office."
    )

    Events.record(request.id, priya.id, "response", Events.response_body(priya, priya_offer))
    Events.record(request.id, sofia.id, "team", "Sofia completed the 15:00 room release update.")

    seed_tasks(maya, luis, priya)

    request
  end

  defp seed_tasks(maya, luis, priya) do
    insert_task!(maya, "Complete the lobby handoff checklist",
      assignee_id: luis.id,
      due_time: ~T[17:45:00],
      location: "Front desk"
    )

    insert_task!(maya, "Review guest arrival notes",
      assignee_id: priya.id,
      status: "done",
      due_time: ~T[15:20:00],
      location: "Front desk"
    )

    # Left unassigned on purpose: it is the piece of work a frontline member
    # can claim without waiting to be asked.
    insert_task!(maya, "Restock the welcome desk stationery",
      due_time: ~T[19:00:00],
      location: "Lobby"
    )
  end

  defp insert_task!(creator, title, opts) do
    Notifier.translate_task_content([title])

    Repo.insert!(%ShiftTask{
      title: title,
      department: creator.department,
      status: Keyword.get(opts, :status, "todo"),
      shift_date: Date.utc_today(),
      due_time: Keyword.get(opts, :due_time),
      location: Keyword.get(opts, :location),
      assignee_id: Keyword.get(opts, :assignee_id),
      created_by_id: creator.id
    })
  end

  defp insert_staff!(name, role, language, opts \\ []) do
    Repo.insert!(%StaffMember{
      name: name,
      role: role,
      department: Keyword.get(opts, :department, "Front Office"),
      language: language,
      is_supervisor: Keyword.get(opts, :is_supervisor, false)
    })
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
