defmodule Shiftline.Coordination do
  @moduledoc """
  The coordination context: coverage requests, staff responses, approvals,
  and handoffs.

  The coverage workflow is an explicit state machine:

      open -> contacting -> claimed -> approved -> resolved

  Write functions validate the transition and return `{:ok, result}` or
  `{:error, reason}`, and broadcast `{:coordination_updated, request_id}`
  so every connected client refreshes.

  Coverage is the whole of this module. Its neighbours own the rest:

    * `Shiftline.Coordination.Tasks` — the shift task board, a different question
      with a different shape (owned by one person, no state machine)
    * `Shiftline.Coordination.Events` — the activity feed, and the sentences that
      go in it
    * `Shiftline.Coordination.Notifier` — the PubSub contract every client reads
    * `Shiftline.Demo` — seeded fixtures and the persona switcher standing in for
      authentication, deliberately outside the domain
  """

  import Ecto.Query
  alias Shiftline.Repo

  alias Shiftline.Coordination.{
    CoverageRequest,
    CoverageResponse,
    Events,
    Notifier,
    StaffMember
  }

  @active_statuses ~w(open contacting claimed)
  @offer_types ~w(accepted partial)

  @doc """
  Subscribes the caller to every coordination message. `Shiftline.Coordination.Notifier`
  documents the message shapes.
  """
  defdelegate subscribe, to: Notifier

  ## Reads

  @doc """
  Every request that still needs attention, earliest shift window first.
  A single acknowledgement of a mid-shift partial offer can open two
  follow-up requests, so callers must not assume there is at most one.
  """
  def active_requests do
    Repo.all(
      from request in CoverageRequest,
        where: request.status in ^@active_statuses,
        order_by: [asc: request.shift_date, asc: request.start_time, asc: request.id]
    )
  end

  @doc """
  The most pressing active request, falling back to the most recent request
  of any status so the demo always has something to show after resolution.
  """
  def active_request do
    case active_requests() do
      [first | _rest] ->
        first

      [] ->
        Repo.one(from request in CoverageRequest, order_by: [desc: request.inserted_at], limit: 1)
    end
  end

  def request_with_details(id) do
    CoverageRequest
    |> Repo.get!(id)
    |> Repo.preload([:selected_replacement, responses: :staff_member, activity_events: :actor])
  end

  ## Staff settings

  @doc """
  Updates the settings a staff member controls themselves: preferred
  language and whether they receive in-app alerts.

  Uses `StaffMember.settings_changeset/2`, which cannot reach role,
  department or supervisor status — see the note there.
  """
  def update_staff_settings(staff_id, attrs) do
    staff = Repo.get!(StaffMember, staff_id)

    case staff |> StaffMember.settings_changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        Notifier.broadcast_settings(updated.id)
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def eligible_staff(%CoverageRequest{} = request) do
    Repo.all(
      from staff in StaffMember,
        where: staff.department == ^request.department and staff.is_supervisor == false,
        order_by: [asc: staff.name]
    )
  end

  @doc """
  Staff names for the new-request form's suggestions.

  The person who called in sick is nearly always on the roster, so the field
  suggests rather than constrains — agency cover and someone hired last week
  still need to be nameable.
  """
  def staff_names do
    Repo.all(from staff in StaffMember, select: staff.name, order_by: [asc: staff.name])
  end

  @doc """
  The departments that currently have staff, for the new-request form.
  """
  def departments do
    Repo.all(
      from staff in StaffMember,
        distinct: true,
        select: staff.department,
        order_by: staff.department
    )
  end

  ## Workflow transitions

  @doc """
  Opens a new coverage request on behalf of a supervisor.

  This is step 1 of the brief's primary scenario: the supervisor states who
  is missing, and which department, role, time, location and urgency the
  gap covers. Only supervisors can raise one.
  """
  def create_coverage_request(supervisor_id, attrs) do
    supervisor = Repo.get!(StaffMember, supervisor_id)

    if supervisor.is_supervisor do
      changeset =
        CoverageRequest.changeset(%CoverageRequest{}, prepare_request_attrs(attrs))

      case Repo.transaction(fn ->
             case Repo.insert(changeset) do
               {:ok, request} ->
                 Events.record(
                   request.id,
                   supervisor_id,
                   "created",
                   "#{Events.first_name(supervisor)} created a #{String.downcase(request.urgency)} " <>
                     "coverage request for #{request.department}."
                 )

                 request

               {:error, invalid} ->
                 Repo.rollback(invalid)
             end
           end) do
        {:ok, request} ->
          Notifier.translate_content([request.reason, request.handoff_note], request.id)
          Notifier.broadcast(request.id)
          {:ok, request}

        {:error, invalid} ->
          {:error, invalid}
      end
    else
      {:error, :not_supervisor}
    end
  end

  # HTML time inputs submit "HH:MM"; Ecto wants a full time. Status is set
  # here rather than trusted from the form.
  defp prepare_request_attrs(attrs) do
    attrs
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.put("status", "open")
    |> Map.update("start_time", nil, &pad_time/1)
    |> Map.update("end_time", nil, &pad_time/1)
  end

  defp pad_time(value) when is_binary(value) do
    case String.split(value, ":") do
      [_hour, _minute] -> value <> ":00"
      _other -> value
    end
  end

  defp pad_time(value), do: value

  @doc """
  Records a staff member's response to a coverage request.

  An offer (`accepted` or `partial`) moves an active request to `claimed`;
  `declined` and `question` leave the status unchanged. Responding also
  counts as having viewed the request.

  Options: `:note`, and for partial offers the required covered window as
  `:cover_start` / `:cover_end` (must fall inside the shift).

  Only eligible staff (same department, not a supervisor) can respond —
  the UI hides controls by role, but the context is the authority.

  Asking a question is not a response: see `ask_question/3`.
  """
  def respond(request_id, staff_id, response_type, opts \\ [])
      when response_type in ~w(accepted partial declined) do
    staff = Repo.get!(StaffMember, staff_id)
    cover = {opts[:cover_start], opts[:cover_end]}

    write_transaction(request_id, fn request ->
      cond do
        request.status not in @active_statuses ->
          Repo.rollback(:request_closed)

        not eligible?(request, staff) ->
          Repo.rollback(:not_eligible)

        error = cover_window_error(request, response_type, cover) ->
          Repo.rollback(error)

        true ->
          {cover_start, cover_end} = if response_type == "partial", do: cover, else: {nil, nil}

          response =
            upsert_response(request_id, staff_id, %{
              response_type: response_type,
              note: opts[:note],
              cover_start_time: cover_start,
              cover_end_time: cover_end,
              viewed_at: now()
            })

          if response_type in @offer_types and request.status != "claimed" do
            update_request!(request, %{status: "claimed"})
          end

          Events.record(request_id, staff_id, "response", Events.response_body(staff, response))
          Notifier.translate_content([opts[:note]], request_id)
          response
      end
    end)
  end

  @doc """
  Records a question about the shift from an eligible staff member.

  A question is a message, not a coverage answer: it never overwrites an
  existing accept/partial/decline, it only records that the person has seen
  the request. Otherwise asking "which desk?" after accepting would erase
  the offer and leave the request claimed with nobody approvable.
  """
  def ask_question(request_id, staff_id, text) when is_binary(text) do
    staff = Repo.get!(StaffMember, staff_id)
    text = String.trim(text)

    write_transaction(request_id, fn request ->
      cond do
        request.status not in @active_statuses ->
          Repo.rollback(:request_closed)

        not eligible?(request, staff) ->
          Repo.rollback(:not_eligible)

        text == "" ->
          Repo.rollback(:empty_question)

        true ->
          touch_viewed(request_id, staff_id)

          Events.record(
            request_id,
            staff_id,
            "question",
            "#{Events.first_name(staff)} asked: #{text}"
          )
      end
    end)
  end

  # Locks the request row for the duration of the transaction, so a
  # concurrent approval or acknowledgement cannot slip between the status
  # check and the write. `fun` receives the freshly-locked request and may
  # `Repo.rollback/1` with an error reason.
  defp write_transaction(request_id, fun) do
    result =
      Repo.transaction(fn ->
        request =
          Repo.one!(
            from request in CoverageRequest, where: request.id == ^request_id, lock: "FOR UPDATE"
          )

        fun.(request)
      end)

    with {:ok, _value} <- result, do: Notifier.broadcast(request_id)
    result
  end

  defp cover_window_error(request, "partial", {cover_start, cover_end}) do
    cond do
      is_nil(cover_start) or is_nil(cover_end) ->
        :missing_window

      Time.compare(cover_start, cover_end) != :lt ->
        :invalid_window

      Time.compare(cover_start, request.start_time) == :lt or
          Time.compare(cover_end, request.end_time) == :gt ->
        :invalid_window

      true ->
        nil
    end
  end

  defp cover_window_error(_request, _type, _cover), do: nil

  defp eligible?(request, staff),
    do: staff.department == request.department and not staff.is_supervisor

  @doc """
  The parts of the shift left uncovered by the approved replacement's offer,
  as a list of `{start_time, end_time}` tuples. Empty for full-shift offers
  or while no replacement is approved.
  """
  def coverage_gaps(%CoverageRequest{selected_replacement_id: nil}, _responses), do: []

  def coverage_gaps(request, responses) do
    case Enum.find(responses, &(&1.staff_member_id == request.selected_replacement_id)) do
      %CoverageResponse{
        response_type: "partial",
        cover_start_time: %Time{} = cover_start,
        cover_end_time: %Time{} = cover_end
      } ->
        before_gap =
          if Time.compare(request.start_time, cover_start) == :lt,
            do: [{request.start_time, cover_start}],
            else: []

        after_gap =
          if Time.compare(cover_end, request.end_time) == :lt,
            do: [{cover_end, request.end_time}],
            else: []

        before_gap ++ after_gap

      _ ->
        []
    end
  end

  @doc """
  Approves `staff_id` as the replacement, on behalf of `approver_id`.

  Requires an active request, a supervisor as approver, and an actual offer
  (full or partial) from the chosen staff member.
  """
  def approve(request_id, staff_id, approver_id) do
    approver = Repo.get!(StaffMember, approver_id)
    staff = Repo.get!(StaffMember, staff_id)

    write_transaction(request_id, fn request ->
      offer =
        Repo.get_by(CoverageResponse, coverage_request_id: request_id, staff_member_id: staff_id)

      cond do
        request.status not in @active_statuses ->
          Repo.rollback(:request_closed)

        not approver.is_supervisor ->
          Repo.rollback(:not_supervisor)

        is_nil(offer) or offer.response_type not in @offer_types ->
          Repo.rollback(:no_offer)

        true ->
          scope =
            case offer do
              %{response_type: "partial"} = partial ->
                "part of the shift (#{Events.window(partial)})"

              _full ->
                "the #{request.role} shift"
            end

          update_request!(request, %{status: "approved", selected_replacement_id: staff_id})

          Events.record(
            request_id,
            approver_id,
            "approved",
            "#{Events.first_name(approver)} approved #{staff.name} for #{scope}."
          )

          request_with_details(request_id)
      end
    end)
  end

  @doc """
  Marks the handoff as acknowledged by `staff_id` and resolves the request.
  Only an `approved` request can be acknowledged, and only by the approved
  replacement.

  If the approved offer was partial, resolving would leave part of the shift
  uncovered — so a follow-up coverage request is opened for each remaining
  gap, keeping the incident honest instead of silently closing it.
  """
  def acknowledge_handoff(request_id, staff_id) do
    staff = Repo.get!(StaffMember, staff_id)

    # The status check, resolution and follow-up creation all happen under
    # the row lock: the request must never end up resolved while a gap
    # failed to materialize, nor be acknowledged twice into duplicate
    # follow-up requests.
    write_transaction(request_id, fn request ->
      cond do
        request.status != "approved" ->
          Repo.rollback(:not_approved)

        request.selected_replacement_id != staff_id ->
          Repo.rollback(:not_replacement)

        true ->
          now = now()

          from(response in CoverageResponse,
            where:
              response.coverage_request_id == ^request.id and
                response.staff_member_id == ^staff_id
          )
          |> Repo.update_all(set: [acknowledged_at: now, updated_at: now])

          update_request!(request, %{status: "resolved", handoff_acknowledged_at: now})

          Events.record(
            request.id,
            staff_id,
            "handoff",
            "#{Events.first_name(staff)} acknowledged the handoff at #{request.location}."
          )

          details = request_with_details(request.id)

          for {gap_start, gap_end} <- coverage_gaps(details, details.responses) do
            open_followup_request(details, gap_start, gap_end)
          end

          details
      end
    end)
  end

  defp open_followup_request(request, gap_start, gap_end) do
    followup =
      Repo.insert!(%CoverageRequest{
        absent_name: request.absent_name,
        department: request.department,
        role: request.role,
        shift_date: request.shift_date,
        start_time: gap_start,
        end_time: gap_end,
        location: request.location,
        urgency: request.urgency,
        reason: "The remaining window of this shift still needs coverage.",
        handoff_note: request.handoff_note,
        status: "open"
      })

    Events.record(
      followup.id,
      nil,
      "created",
      "Shiftline opened a follow-up request for #{Events.format_time(gap_start)}–#{Events.format_time(gap_end)}."
    )

    followup
  end

  @doc """
  Records that a staff member has seen the request without answering it,
  so viewed / responded / acknowledged stay separate states.
  """
  def mark_viewed(request_id, staff_id) do
    request = Repo.get!(CoverageRequest, request_id)
    staff = Repo.get!(StaffMember, staff_id)

    if eligible?(request, staff) do
      do_mark_viewed(request_id, staff_id)
    else
      {:error, :not_eligible}
    end
  end

  defp do_mark_viewed(request_id, staff_id) do
    response = touch_viewed(request_id, staff_id)
    Notifier.broadcast(request_id)
    {:ok, response}
  end

  # Records that this person has seen the request, without disturbing any
  # answer they have already given.
  defp touch_viewed(request_id, staff_id) do
    case Repo.get_by(CoverageResponse,
           coverage_request_id: request_id,
           staff_member_id: staff_id
         ) do
      nil ->
        upsert_response(request_id, staff_id, %{response_type: "pending", viewed_at: now()})

      %CoverageResponse{viewed_at: nil} = existing ->
        existing |> CoverageResponse.changeset(%{viewed_at: now()}) |> Repo.update!()

      existing ->
        existing
    end
  end

  defp upsert_response(request_id, staff_id, attrs) do
    attrs =
      Map.merge(attrs, %{coverage_request_id: request_id, staff_member_id: staff_id})

    case Repo.get_by(CoverageResponse,
           coverage_request_id: request_id,
           staff_member_id: staff_id
         ) do
      nil -> %CoverageResponse{}
      existing -> existing
    end
    |> CoverageResponse.changeset(attrs)
    |> Repo.insert_or_update!()
  end

  defp update_request!(request, attrs) do
    request |> CoverageRequest.changeset(attrs) |> Repo.update!()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
