defmodule SonaWeb.HomeLive.UI do
  @moduledoc """
  Shared function components and view helpers for the Sona prototype:
  the coverage card, resolved card, icon set, and formatting helpers used
  by every tab.
  """
  use SonaWeb, :html

  @active_statuses ~w(open contacting claimed)

  def active_status?(status), do: status in @active_statuses

  ## Coverage card

  attr :request, :map, required: true
  attr :responses, :list, required: true
  attr :eligible_staff, :list, required: true
  attr :role, :string, required: true
  attr :current_staff, :map, required: true
  attr :requester, :map, required: true
  attr :compact, :boolean, default: true

  def coverage_card(assigns) do
    ~H"""
    <article class={if @compact, do: "signal-card", else: "signal-card expanded"}>
      <div class="signal-rail"></div>
      <div class="signal-content">
        <div class="signal-topline">
          <span class="status-label urgent"><i></i> {urgency_label(@request.urgency)}</span>
          <span class="signal-time">{starts_in(@request)} <.icon name="arrow-up" /></span>
        </div>
        <h3>{gettext("Urgent coverage needed")}</h3>
        <div class="fact-row">
          <span><.icon name="briefcase" />{@request.role}</span>
          <span><.icon name="clock" />{gettext("Today")}, {shift_window(@request)}</span>
          <span><.icon name="pin" />{@request.location}</span>
        </div>
        <p>{translate_content(@request.reason)}</p>
        <div :if={content_translated?(@request.reason)} class="translation-note">
          <span class="language-glyph">文</span>
          {language_label(@current_staff.language)} <span>·</span>
          <span>{gettext("Translated automatically")}</span>
        </div>
        <div
          :if={not content_translated?(@request.reason) and @current_staff.language != "English"}
          class="translation-note muted"
        >
          <span class="language-glyph">文</span>
          <span>{gettext("Shown in its original language")}</span>
        </div>
        <div class="signal-bottom">
          <span>
            <span class={"avatar tiny #{avatar_palette(@requester.name)}"}>
              {initials(@requester.name)}
            </span>
            {@requester.name} <em>· {@request.department}</em>
          </span>
          <span class="response-state">
            {if @role == "frontline",
              do: response_label(response_for(@responses, @current_staff.id)),
              else: response_summary(@responses, @eligible_staff)}
          </span>
        </div>
        <div :if={@role == "frontline" and active_status?(@request.status)} class="response-actions">
          <.link
            patch={~p"/?view=coverage&role=#{@role}&request=#{@request.id}"}
            class="primary-response"
          >
            {gettext("Respond to request")} <.icon name="arrow" />
          </.link>
        </div>
        <div :if={@role == "supervisor" and @compact} class="response-actions">
          <.link
            patch={~p"/?view=coverage&role=#{@role}&request=#{@request.id}"}
            class="primary-response"
          >
            {gettext("Open request")} <.icon name="arrow" />
          </.link>
        </div>
      </div>
    </article>
    """
  end

  ## Resolved / approved card

  attr :request, :map, required: true
  attr :responses, :list, required: true
  attr :role, :string, required: true
  attr :current_staff, :map, required: true

  def resolved_card(assigns) do
    assigns =
      assign(assigns, :gaps, Sona.Coordination.coverage_gaps(assigns.request, assigns.responses))

    ~H"""
    <article class="resolved-card">
      <div class="resolved-icon"><.icon name="check" /></div>
      <div>
        <span class={if @gaps == [], do: "status-label success", else: "status-label warning"}>
          <i></i> {cond do
            @gaps != [] -> gettext("PARTIALLY COVERED")
            @request.status == "approved" -> gettext("APPROVED")
            true -> gettext("RESOLVED")
          end}
        </span>
        <h3>{resolved_title(@request, @responses, @gaps)}</h3>
        <p>{@request.role} · {gettext("Today")}, {shift_window(@request)} · {@request.location}</p>
        <div :for={{gap_start, gap_end} <- @gaps} class="gap-note">
          <span class="note-icon"><.icon name="clock" /></span>
          <span>
            <strong>{gettext("Coverage gap")}</strong>{gettext("%{window} still needs coverage",
              window: "#{format_time(gap_start)}–#{format_time(gap_end)}"
            )}
          </span>
        </div>
        <div class="handoff-note">
          <span class="note-icon"><.icon name="flag" /></span>
          <span>
            <strong>{gettext("Handoff note")}</strong>{translate_content(@request.handoff_note)}
          </span>
        </div>
        <%= cond do %>
          <% @role == "frontline" and is_nil(@request.handoff_acknowledged_at) and
              @request.selected_replacement_id == @current_staff.id -> %>
            <button class="primary-button" phx-click="acknowledge">
              <.icon name="check" /> {gettext("Acknowledge handoff")}
            </button>
          <% is_nil(@request.handoff_acknowledged_at) -> %>
            <span class="acknowledged waiting">
              <.icon name="clock" /> {gettext("Waiting for handoff acknowledgement")}
            </span>
          <% true -> %>
            <span class="acknowledged">
              <.icon name="check" /> {gettext("Handoff acknowledged")}
            </span>
        <% end %>
      </div>
    </article>
    """
  end

  ## Icons

  attr :name, :string, required: true

  def icon(assigns) do
    ~H"""
    <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><%= case @name do %>
      <% "home" -> %>
        <path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1V10Z" />
      <% "signal" -> %>
        <path d="M4 19v-3M8 19v-6M12 19V9M16 19V5M20 19V2" />
      <% "chat" -> %>
        <path d="M20 11.5a7.5 7.5 0 0 1-8 7.5 8.7 8.7 0 0 1-3.5-.7L4 20l1.7-3.6A7.4 7.4 0 0 1 4 11.5 7.5 7.5 0 0 1 12 4a7.5 7.5 0 0 1 8 7.5Z" />
      <% "user" -> %>
        <circle cx="12" cy="8" r="3.5" /><path d="M4.5 21a7.5 7.5 0 0 1 15 0" />
      <% "refresh" -> %>
        <path d="M20 11a8 8 0 0 0-14-4L4 9M4 5v4h4M4 13a8 8 0 0 0 14 4l2-2M20 19v-4h-4" />
      <% "chevron" -> %>
        <path d="m7 9 5 5 5-5" />
      <% "bell" -> %>
        <path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4" />
      <% "clock" -> %>
        <circle cx="12" cy="12" r="8.5" /><path d="M12 7v5l3 2" />
      <% "arrow" -> %>
        <path d="M4 12h15m-6-6 6 6-6 6" />
      <% "arrow-up" -> %>
        <path d="M12 19V5m-5 5 5-5 5 5" />
      <% "briefcase" -> %>
        <rect x="3" y="7" width="18" height="12" rx="2" /><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 12h18" />
      <% "pin" -> %>
        <path d="M18 10c0 5-6 10-6 10S6 15 6 10a6 6 0 1 1 12 0Z" /><circle cx="12" cy="10" r="2" />
      <% "check" -> %>
        <path d="m5 12 4 4L19 6" />
      <% "close" -> %>
        <path d="m6 6 12 12M18 6 6 18" />
      <% "send" -> %>
        <path d="m21 3-7 18-4-8-8-4 19-6Z" />
      <% "plus" -> %>
        <path d="M12 5v14M5 12h14" />
      <% "flag" -> %>
        <path d="M5 21V4m0 0c5-3 9 3 14 0v9c-5 3-9-3-14 0" />
    <% end %></svg>
    """
  end

  ## Content translation

  @doc """
  Renders user-entered content (request reasons, handoff notes, questions) in
  the reader's language.

  Reads the translation cache first — `Sona.Translation` fills it in the
  background whenever someone writes something — then falls back to the
  Gettext catalogs for seeded content, and finally to the original text.
  """
  def translate_content(nil), do: nil

  def translate_content(text) do
    locale = Gettext.get_locale(SonaWeb.Gettext)
    Sona.Translation.lookup(text, locale) || Gettext.gettext(SonaWeb.Gettext, text)
  end

  @doc """
  Whether `text` is actually being shown translated, so the UI can say so
  rather than implying a translation that did not happen.
  """
  def content_translated?(nil), do: false
  def content_translated?(text), do: translate_content(text) != text

  ## Status and labels

  def status_class(status), do: "status-chip #{status}"

  def status_label("open"), do: gettext("Open")
  def status_label("contacting"), do: gettext("Contacting")
  def status_label("claimed"), do: gettext("Claimed")
  def status_label("approved"), do: gettext("Approved")
  def status_label("resolved"), do: gettext("Resolved")
  def status_label(_), do: gettext("Open")

  def urgency_label("Urgent"), do: gettext("URGENT")
  def urgency_label("High"), do: gettext("HIGH")
  def urgency_label(_), do: gettext("UPDATE")

  def step_class(status, step) do
    order = %{"open" => 0, "contacting" => 1, "claimed" => 2, "approved" => 3, "resolved" => 4}
    current = Map.get(order, status, 0)
    step_order = Map.get(order, step, 0)

    cond do
      step_order < current -> "step complete"
      step_order == current -> "step current"
      true -> "step"
    end
  end

  def workflow_steps do
    [
      {"open", gettext("Open")},
      {"contacting", gettext("Contacting")},
      {"claimed", gettext("Claimed")},
      {"approved", gettext("Approved")},
      {"resolved", gettext("Resolved")}
    ]
  end

  ## Responses

  def response_for(responses, staff_id) do
    Enum.find(responses, &(&1.staff_member_id == staff_id))
  end

  def response_label(nil), do: gettext("Response needed")
  def response_label(%{response_type: "accepted"}), do: gettext("Full shift")
  def response_label(%{response_type: "partial"}), do: gettext("Partial coverage")
  def response_label(%{response_type: "declined"}), do: gettext("Declined")
  def response_label(%{response_type: "pending"}), do: gettext("Viewed, no response yet")

  def response_state(%{acknowledged_at: %DateTime{}}), do: gettext("Acknowledged")
  def response_state(%{viewed_at: nil}), do: gettext("Not viewed")
  def response_state(%{response_type: "pending"}), do: gettext("Viewed")
  def response_state(%{response_type: "declined"}), do: gettext("Declined")
  def response_state(_), do: gettext("Responded")

  def response_state_class(%{response_type: "accepted"}), do: "response-state confirmed"
  def response_state_class(%{response_type: "partial"}), do: "response-state waiting"
  def response_state_class(_), do: "response-state muted"

  def offer?(%{response_type: type}), do: type in ~w(accepted partial)

  def response_window(%{
        response_type: "partial",
        cover_start_time: %Time{} = cover_start,
        cover_end_time: %Time{} = cover_end
      }),
      do: "#{format_time(cover_start)}–#{format_time(cover_end)}"

  def response_window(_response), do: nil

  def resolved_title(%{selected_replacement: nil}, _responses, _gaps),
    do: gettext("Coverage is confirmed")

  def resolved_title(request, responses, gaps) do
    offer = response_for(responses, request.selected_replacement_id)

    case {gaps, offer && response_window(offer)} do
      {[], _} ->
        gettext("%{name} is covering the shift", name: request.selected_replacement.name)

      {_, window} when is_binary(window) ->
        gettext("%{name} is covering %{window}",
          name: request.selected_replacement.name,
          window: window
        )

      _ ->
        gettext("%{name} is covering the shift", name: request.selected_replacement.name)
    end
  end

  def viewed_count(responses), do: Enum.count(responses, & &1.viewed_at)

  def answered_count(responses),
    do: Enum.count(responses, &(&1.response_type != "pending"))

  def response_summary(responses, eligible_staff) do
    gettext("%{viewed} of %{total} viewed · %{answers} responses",
      viewed: viewed_count(responses),
      total: length(eligible_staff),
      answers: answered_count(responses)
    )
  end

  ## People

  def initials(name), do: name |> String.split() |> Enum.map_join(&String.first/1)

  def first_name(name), do: name |> String.split() |> hd()

  # The stylesheet ships three avatar palettes; pick one deterministically
  # per person so colors stay stable between renders.
  def avatar_palette("Maya Chen"), do: "maya"
  def avatar_palette("Luis Garcia"), do: "luis"
  def avatar_palette("Priya Shah"), do: "priya"
  def avatar_palette(name), do: Enum.at(~w(maya luis priya), :erlang.phash2(name, 3))

  def language_label("Spanish"), do: "Español"
  def language_label("French"), do: "Français"
  def language_label(_), do: "English"

  ## Time choices

  @doc """
  Half-hour options between two times, for constraining a picker to a shift.

  A free-text time field lets someone enter a time outside the shift and then
  be told off for it; offering only the valid times makes that error close to
  unreachable.
  """
  def time_choices(%Time{} = from, %Time{} = to, step_minutes \\ 30) do
    # Counted rather than generated-until-past-`to`: Time.add/3 wraps around
    # midnight, so a comparison-based loop never terminates on a full day.
    case Time.diff(to, from, :second) do
      seconds when seconds < 0 ->
        []

      seconds ->
        step = step_minutes * 60

        Enum.map(0..div(seconds, step), fn index ->
          from |> Time.add(index * step, :second) |> format_time()
        end)
    end
  end

  @doc "Half-hour options across a whole day, for a shift that has no window yet."
  def day_time_choices(step_minutes \\ 30) do
    time_choices(~T[00:00:00], ~T[23:30:00], step_minutes)
  end

  @doc """
  The two obvious ways to split a shift, as `{label, from, to}`.

  Most partial offers are "I can do the first half" or "the back end of it",
  so those are one tap rather than two dropdowns.
  """
  def half_windows(request) do
    minutes = Time.diff(request.end_time, request.start_time, :second) |> div(60)

    if minutes >= 120 do
      midpoint = Time.add(request.start_time, div(minutes, 60) * 30 * 60, :second)

      [
        {gettext("First half"), format_time(request.start_time), format_time(midpoint)},
        {gettext("Second half"), format_time(midpoint), format_time(request.end_time)}
      ]
    else
      []
    end
  end

  ## Shift tasks

  def task_row_class(%{status: "done"}), do: "task-row done"
  def task_row_class(_task), do: "task-row"

  def task_status_class(%{status: "todo"}), do: "task-status pending"
  def task_status_class(%{status: "in_progress"}), do: "task-status active"
  def task_status_class(_task), do: "task-status"

  def task_status_label("todo"), do: gettext("Not started")
  def task_status_label("in_progress"), do: gettext("In progress")
  def task_status_label(_status), do: gettext("Done")

  @doc """
  The supporting line under a task. Supervisors get the owner from the
  assignment control beside it, so repeating it here would just be noise.
  """
  def task_meta(task, role \\ "frontline") do
    owner =
      cond do
        role == "supervisor" -> nil
        task.assignee -> task.assignee.name
        true -> gettext("Unassigned")
      end

    [
      task.due_time && gettext("Due %{time}", time: format_time(task.due_time)),
      task.location,
      owner
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc """
  The status this person can move the task to next, or `nil` when they own
  no action on it. Only the assignee or a supervisor can advance work.
  """
  def next_status(%{assignee_id: nil}, _staff, _role), do: nil

  def next_status(task, staff, role) do
    owns? = task.assignee_id == staff.id or role == "supervisor"

    case {owns?, task.status} do
      {true, "todo"} -> "in_progress"
      {true, "in_progress"} -> "done"
      _otherwise -> nil
    end
  end

  def next_status_label("in_progress"), do: gettext("Start")
  def next_status_label("done"), do: gettext("Mark done")
  def next_status_label(_status), do: nil

  ## Events

  def event_marker_class("response"), do: "activity-marker amber"
  def event_marker_class("question"), do: "activity-marker amber"
  def event_marker_class("handoff"), do: "activity-marker success"
  def event_marker_class(_), do: "activity-marker moss"

  def event_actor(%{actor: nil}), do: "Sona"
  def event_actor(%{actor: actor}), do: actor.name

  ## Time

  def relative_time(%DateTime{} = datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :minute)

    cond do
      diff < 1 -> gettext("Just now")
      diff < 60 -> gettext("%{count} min ago", count: diff)
      diff < 60 * 24 -> gettext("%{count} h ago", count: div(diff, 60))
      true -> gettext("%{count} d ago", count: div(diff, 60 * 24))
    end
  end

  def starts_in(request) do
    start = DateTime.new!(request.shift_date, request.start_time, "Etc/UTC")
    diff = DateTime.diff(start, DateTime.utc_now(), :minute)

    cond do
      diff <= 0 -> gettext("Shift in progress")
      diff < 60 -> gettext("Starts in %{count} min", count: diff)
      true -> gettext("Starts in %{count} h", count: div(diff, 60))
    end
  end

  def shift_window(request) do
    "#{format_time(request.start_time)}–#{format_time(request.end_time)}"
  end

  def format_time(%Time{} = time), do: Calendar.strftime(time, "%H:%M")

  def today_line, do: Calendar.strftime(Date.utc_today(), "%A, %B %-d")
end
