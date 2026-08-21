defmodule ShiftlineWeb.HomeLive.Shifts do
  @moduledoc """
  The Shifts tab: the department's roster, and who is on each block.

  Supervisors get create, edit, delete and rostering. Everyone else reads —
  the same split the context enforces, so the controls here mirror what
  `Shiftline.Coordination.Shifts` would actually accept rather than guessing.
  """
  use ShiftlineWeb, :html

  import ShiftlineWeb.HomeLive.UI

  alias Shiftline.Coordination.Shift

  attr :role, :string, required: true
  attr :current_staff, :map, required: true
  attr :shifts, :list, required: true
  attr :assignable_staff, :list, required: true
  attr :new_shift_open, :boolean, required: true
  attr :editing_shift, :map, default: nil
  attr :shift_errors, :list, required: true

  def shifts_view(assigns) do
    ~H"""
    <section class="page-heading compact-heading">
      <div>
        <p class="date-line">{gettext("Roster")}</p>
        <h1>{gettext("Shifts")}</h1>
        <p class="heading-subtitle">
          {gettext("Who is on, when, and where the gaps are.")}
        </p>
      </div>
      <button
        :if={@role == "supervisor"}
        class="outline-button"
        phx-click="toggle_new_shift"
        aria-expanded={to_string(@new_shift_open)}
      >
        <.icon name={if @new_shift_open, do: "close", else: "plus"} />
        {if @new_shift_open, do: gettext("Cancel"), else: gettext("Add shift")}
      </button>
    </section>

    <.shift_form
      :if={@role == "supervisor" and @new_shift_open}
      editing={@editing_shift}
      errors={@shift_errors}
    />

    <p :if={@shifts == []} class="task-empty">{gettext("No shifts on the roster yet.")}</p>

    <section :if={@shifts != []} class="shift-list">
      <article :for={shift <- @shifts} class="shift-card">
        <div class="shift-card-head">
          <div>
            <span class="section-kicker">{shift_day(shift)}</span>
            <h3>{shift.role}</h3>
            <span class="shift-card-meta">
              <.icon name="clock" />{shift_span(shift)}
              <span :if={shift.location}>· {shift.location}</span>
            </span>
          </div>
          <span :if={crosses_midnight?(shift)} class="status-label">{gettext("Overnight")}</span>
        </div>

        <div class="shift-people">
          <span :if={scheduled(shift) == []} class="shift-uncovered">
            <.icon name="flag" />{gettext("Nobody is on this shift")}
          </span>
          <span
            :for={assignment <- shift.assignments}
            class={if assignment.status == "absent", do: "shift-person absent", else: "shift-person"}
          >
            <span class={"avatar tiny #{avatar_palette(assignment.staff_member.name)}"}>
              {initials(assignment.staff_member.name)}
            </span>
            {assignment.staff_member.name}
            <em :if={assignment.status != "scheduled"}>{assignment_label(assignment.status)}</em>
            <button
              :if={@role == "supervisor"}
              class="shift-person-remove"
              phx-click="unassign_shift"
              phx-value-shift-id={shift.id}
              phx-value-staff-id={assignment.staff_member_id}
              aria-label={gettext("Remove from shift")}
            >
              <.icon name="close" />
            </button>
          </span>
        </div>

        <div :if={@role == "supervisor"} class="shift-card-actions">
          <form id={"assign-shift-#{shift.id}"} phx-change="assign_shift">
            <input type="hidden" name="shift-id" value={shift.id} />
            <select name="staff_id" aria-label={gettext("Add someone to this shift")}>
              <option value="">{gettext("Add someone…")}</option>
              <option :for={person <- unassigned(@assignable_staff, shift)} value={person.id}>
                {person.name}
              </option>
            </select>
          </form>

          <button class="text-button" phx-click="edit_shift" phx-value-shift-id={shift.id}>
            {gettext("Edit")}
          </button>
          <button
            class="text-button danger"
            phx-click="delete_shift"
            phx-value-shift-id={shift.id}
            data-confirm={gettext("Delete this shift and its assignments?")}
          >
            {gettext("Delete")}
          </button>
        </div>
      </article>
    </section>
    """
  end

  attr :editing, :map, default: nil
  attr :errors, :list, required: true

  defp shift_form(assigns) do
    ~H"""
    <section class="new-request-card">
      <div class="section-heading compact">
        <div>
          <span class="section-kicker">
            {if @editing, do: gettext("EDIT SHIFT"), else: gettext("NEW SHIFT")}
          </span>
          <h2>{if @editing, do: gettext("Change this shift"), else: gettext("Add to the roster")}</h2>
        </div>
      </div>

      <div :if={@errors != []} class="form-errors" role="alert">
        <strong>{gettext("Please check this form")}</strong>
        <ul>
          <li :for={message <- @errors}>{message}</li>
        </ul>
      </div>

      <form id="shift-form" phx-submit="save_shift" class="request-form">
        <input :if={@editing} type="hidden" name="shift_id" value={@editing.id} />
        <label>
          <span>{gettext("Role needed")}</span>
          <input name="role" required value={@editing && @editing.role} />
        </label>
        <label>
          <span>{gettext("Date")}</span>
          <input type="date" name="date" required value={form_date(@editing)} />
        </label>
        <label>
          <span>{gettext("From")}</span>
          <select name="start_time">
            <option
              :for={time <- day_time_choices()}
              value={time}
              selected={time == form_time(@editing, :starts_at, "14:00")}
            >
              {time}
            </option>
          </select>
        </label>
        <label>
          <span>{gettext("Until")}</span>
          <select name="end_time">
            <option
              :for={time <- day_time_choices()}
              value={time}
              selected={time == form_time(@editing, :ends_at, "22:00")}
            >
              {time}
            </option>
          </select>
        </label>
        <label class="span-two">
          <span>{gettext("Location")}</span>
          <input name="location" value={@editing && @editing.location} />
        </label>
        <p class="form-hint span-two">
          {gettext("An end time at or before the start means the shift runs overnight.")}
        </p>
        <button class="primary-button span-two">
          <.icon name="check" />
          {if @editing, do: gettext("Save shift"), else: gettext("Add shift")}
        </button>
      </form>
    </section>
    """
  end

  ## Helpers

  defp scheduled(shift), do: Enum.reject(shift.assignments, &(&1.status == "absent"))

  defp unassigned(staff, shift) do
    taken = MapSet.new(shift.assignments, & &1.staff_member_id)
    Enum.reject(staff, &MapSet.member?(taken, &1.id))
  end

  defp crosses_midnight?(shift),
    do: DateTime.to_date(shift.starts_at) != DateTime.to_date(shift.ends_at)

  defp shift_span(%Shift{} = shift),
    do: "#{clock(shift.starts_at)}–#{clock(shift.ends_at)}"

  defp clock(%DateTime{} = at), do: Calendar.strftime(at, "%H:%M")

  # Deliberately the ISO date rather than a formatted weekday: `strftime`'s
  # "%A, %B" emits English names whatever the locale, and a roster is exactly
  # where that would be obvious. Localized dates land with the calendar view.
  defp shift_day(%Shift{} = shift), do: Date.to_iso8601(DateTime.to_date(shift.starts_at))

  defp form_date(nil), do: Date.to_iso8601(Date.utc_today())
  defp form_date(shift), do: shift.starts_at |> DateTime.to_date() |> Date.to_iso8601()

  defp form_time(nil, _field, default), do: default
  defp form_time(shift, field, _default), do: shift |> Map.fetch!(field) |> clock()

  defp assignment_label("absent"), do: gettext("Absent")
  defp assignment_label("covering"), do: gettext("Covering")
  defp assignment_label(_other), do: nil
end
