defmodule Shiftline.Demo do
  @moduledoc """
  Demo scaffolding: the seeded dataset and the two switchable personas that
  stand in for authentication.

  This lives outside `Shiftline.Coordination` on purpose. Everything in here is
  the part of the prototype that a real deployment deletes — fixture data, a
  reset button, and a persona switcher that hands out an identity with no
  proof of who is asking. Keeping it in the domain context would have meant
  seeding logic and business rules ageing together in one file, and would
  have blurred the one thing worth being unambiguous about: the domain
  guards below this line are real, and the identity above it is not.

  Authentication replaces `personas/0` and nothing else. The write functions
  in `Shiftline.Coordination` and `Shiftline.Coordination.Tasks` already take an actor
  id and already check department, role and ownership against it, so a real
  session would feed the same ids into the same guards.
  """

  import Ecto.Query

  alias Shiftline.Coordination.{
    ActivityEvent,
    CoverageRequest,
    CoverageResponse,
    Events,
    Message,
    MessageRead,
    Notifier,
    Shift,
    ShiftAssignment,
    ShiftTask,
    StaffMember
  }

  alias Shiftline.Repo

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
    Repo.delete_all(MessageRead)
    Repo.delete_all(Message)
    Repo.delete_all(ShiftAssignment)
    Repo.delete_all(Shift)
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
    rosa =
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

    seed_messages(%{maya: maya, luis: luis, priya: priya, rosa: rosa})
    seed_tasks(maya, luis, priya)
    seed_shifts(%{maya: maya, luis: luis, priya: priya, theo: theo, dana: dana, sofia: sofia})

    request
  end

  # Enough conversation to show what the tab is for on first load: a pinned
  # announcement waiting to be acknowledged, an ordinary channel exchange, and
  # one direct line already in progress.
  defp seed_messages(staff) do
    announcement =
      insert_message!(staff.maya,
        department: "Front Office",
        urgent: true,
        pinned: true,
        body:
          "Welcome Ana, our new night auditor. Please introduce yourself at the 17:45 handoff."
      )

    # Priya has seen the pin and said so; Luis has not, so the demo opens with
    # an acknowledgement still outstanding.
    Repo.insert!(%MessageRead{
      message_id: announcement.id,
      staff_member_id: staff.priya.id,
      viewed_at: now(),
      acknowledged_at: now()
    })

    insert_message!(staff.priya,
      department: "Front Office",
      body: "The ice machine on floor 3 is working again."
    )

    insert_message!(staff.maya,
      recipient_id: staff.luis.id,
      body: "Can you take the lobby handoff checklist before the evening rush?"
    )

    insert_message!(staff.luis,
      recipient_id: staff.maya.id,
      body: "Yes, I will start it at 17:30."
    )

    insert_message!(staff.rosa,
      department: "Housekeeping",
      body: "Floors 1 to 4 are clear. Linen delivery arrives at 16:00."
    )
  end

  defp insert_message!(sender, opts) do
    body = Keyword.fetch!(opts, :body)
    Notifier.translate_message_content([body])

    Repo.insert!(%Message{
      body: body,
      sender_id: sender.id,
      department: Keyword.get(opts, :department),
      recipient_id: Keyword.get(opts, :recipient_id),
      urgent: Keyword.get(opts, :urgent, false),
      pinned: Keyword.get(opts, :pinned, false)
    })
  end

  # Three shifts, chosen to exercise the model rather than to look full: the
  # Front Office evening block the demo revolves around, a night audit that
  # crosses midnight, and a Housekeeping morning so department scoping is
  # visible here too.
  defp seed_shifts(staff) do
    evening =
      insert_shift!("Front Office", "Front Desk Agent", ~T[14:00:00], ~T[22:00:00],
        location: "Lobby front desk"
      )

    night =
      insert_shift!("Front Office", "Night Auditor", ~T[22:00:00], ~T[06:00:00],
        location: "Front desk",
        crosses_midnight: true
      )

    _morning =
      insert_shift!("Housekeeping", "Room Attendant", ~T[07:00:00], ~T[15:00:00],
        location: "Floors 1-4"
      )

    for person <- [staff.maya, staff.luis, staff.priya, staff.sofia] do
      insert_assignment!(evening, person)
    end

    insert_assignment!(night, staff.dana)

    # Theo is on the evening shift but cannot make it — the fact the seeded
    # coverage request exists because of.
    insert_assignment!(evening, staff.theo, "absent")
  end

  defp insert_shift!(department, role, start_time, end_time, opts) do
    today = Date.utc_today()
    ends_on = if opts[:crosses_midnight], do: Date.add(today, 1), else: today

    Repo.insert!(%Shift{
      department: department,
      role: role,
      starts_at: DateTime.new!(today, start_time, "Etc/UTC"),
      ends_at: DateTime.new!(ends_on, end_time, "Etc/UTC"),
      location: Keyword.get(opts, :location),
      source: "manual"
    })
  end

  defp insert_assignment!(shift, staff, status \\ "scheduled") do
    Repo.insert!(%ShiftAssignment{
      shift_id: shift.id,
      staff_member_id: staff.id,
      status: status
    })
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
