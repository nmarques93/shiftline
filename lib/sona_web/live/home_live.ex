defmodule SonaWeb.HomeLive do
  @moduledoc """
  The prototype shell: navigation, demo role switcher, and the event
  handlers for the coverage workflow. Tab content lives in
  `SonaWeb.HomeLive.{Today, Coverage, Messages, Profile}`.

  The current tab and demo persona are URL state (`?view=...&role=...`),
  so views are linkable, the back button works, and two browser windows
  can watch the same incident from both sides. All workflow writes go
  through `Sona.Coordination`, which broadcasts changes back to every
  connected client.
  """
  use SonaWeb, :live_view

  alias Sona.Coordination
  alias Sona.Coordination.{Events, Tasks}
  alias Sona.Demo
  alias SonaWeb.HomeLive.{Coverage, Messages, Profile, Shifts, Today}

  import SonaWeb.HomeLive.UI

  @views ~w(today coverage shifts messages profile)
  @roles ~w(supervisor frontline)

  @impl true
  def mount(_params, _session, socket) do
    Demo.ensure_demo_data()
    if connected?(socket), do: Coordination.subscribe()

    {:ok,
     assign(socket,
       role: "supervisor",
       view: "today",
       question: "",
       partial_open: false,
       notifications_open: false,
       new_request_open: false,
       new_task_open: false,
       new_shift_open: false,
       editing_shift_id: nil,
       shift_errors: [],
       request_errors: []
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    view = if params["view"] in @views, do: params["view"], else: "today"
    role = if params["role"] in @roles, do: params["role"], else: "supervisor"

    focused_request_id =
      case Integer.parse(params["request"] || "") do
        {id, ""} -> id
        _other -> nil
      end

    {:noreply,
     socket
     |> assign(
       view: view,
       role: role,
       partial_open: false,
       notifications_open: false,
       new_request_open: false,
       new_task_open: false,
       request_errors: [],
       focused_request_id: focused_request_id,
       show_original: params["original"] == "1"
     )
     |> refresh_data()
     |> maybe_mark_viewed()}
  end

  @impl true
  def handle_info({:coordination_updated, _request_id}, socket) do
    {:noreply, refresh_data(socket)}
  end

  def handle_info(:tasks_updated, socket) do
    {:noreply, refresh_data(socket)}
  end

  # Nothing renders shifts yet, but every client subscribes to the one topic,
  # so a message with no clause here would take the LiveView down.
  def handle_info(:shifts_updated, socket) do
    {:noreply, refresh_data(socket)}
  end

  # Another window changed the settings of the persona this one is showing.
  # A locale change cannot be applied by re-rendering (gettext strings with
  # no assign reference are static in the diff), so remount instead.
  def handle_info({:settings_updated, staff_id}, socket) do
    if staff_id == socket.assigns.current_staff.id do
      {:noreply, push_navigate(socket, to: current_path(socket))}
    else
      {:noreply, refresh_data(socket)}
    end
  end

  @impl true
  def handle_event("respond", %{"type" => type}, socket) do
    case Coordination.respond(
           socket.assigns.request.id,
           socket.assigns.current_staff.id,
           type,
           note: default_note(type)
         ) do
      {:ok, _response} ->
        {:noreply,
         socket |> response_sent_flash() |> assign(:partial_open, false) |> refresh_data()}

      {:error, reason} ->
        {:noreply, domain_error_flash(socket, reason)}
    end
  end

  def handle_event("toggle_partial", _params, socket) do
    {:noreply, assign(socket, :partial_open, !socket.assigns.partial_open)}
  end

  def handle_event("respond_partial", %{"from" => from, "to" => to}, socket) do
    with {:ok, cover_start} <- Time.from_iso8601(from <> ":00"),
         {:ok, cover_end} <- Time.from_iso8601(to <> ":00"),
         {:ok, _response} <-
           Coordination.respond(
             socket.assigns.request.id,
             socket.assigns.current_staff.id,
             "partial",
             cover_start: cover_start,
             cover_end: cover_end
           ) do
      {:noreply,
       socket |> response_sent_flash() |> assign(:partial_open, false) |> refresh_data()}
    else
      {:error, reason} when reason in [:request_closed, :not_eligible] ->
        {:noreply, domain_error_flash(socket, reason)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Choose a window inside the shift times."))
         |> refresh_data()}
    end
  end

  def handle_event("ask_question", %{"question" => question}, socket)
      when byte_size(question) > 0 do
    case Coordination.ask_question(
           socket.assigns.request.id,
           socket.assigns.current_staff.id,
           question
         ) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Question sent to %{name}", name: first_name(socket.assigns.requester.name))
         )
         |> assign(:question, "")
         |> refresh_data()}

      {:error, reason} ->
        {:noreply, domain_error_flash(socket, reason)}
    end
  end

  def handle_event("ask_question", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_new_request", _params, socket) do
    {:noreply,
     assign(socket,
       new_request_open: !socket.assigns.new_request_open,
       request_errors: []
     )}
  end

  def handle_event("create_request", params, socket) do
    case Coordination.create_coverage_request(socket.assigns.current_staff.id, params) do
      {:ok, request} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Coverage request sent to the team"))
         |> assign(new_request_open: false, request_errors: [])
         |> push_patch(to: ~p"/?view=coverage&role=#{socket.assigns.role}&request=#{request.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :request_errors, changeset_messages(changeset))}

      {:error, reason} ->
        {:noreply, domain_error_flash(socket, reason)}
    end
  end

  def handle_event("toggle_new_task", _params, socket) do
    {:noreply, assign(socket, :new_task_open, !socket.assigns.new_task_open)}
  end

  def handle_event("create_task", params, socket) do
    attrs = Map.take(params, ["title", "assignee_id", "due_time"])

    case Tasks.create(socket.assigns.current_staff.id, attrs) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Task added"))
         |> assign(:new_task_open, false)
         |> refresh_data()}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, gettext("Give the task a title first."))}

      {:error, reason} ->
        {:noreply, domain_error_flash(socket, reason)}
    end
  end

  def handle_event("assign_task", %{"task-id" => task_id, "assignee_id" => assignee_id}, socket) do
    assignee = if assignee_id == "", do: nil, else: String.to_integer(assignee_id)

    case Tasks.assign(
           String.to_integer(task_id),
           assignee,
           socket.assigns.current_staff.id
         ) do
      {:ok, _task} -> {:noreply, refresh_data(socket)}
      {:error, reason} -> {:noreply, domain_error_flash(socket, reason)}
    end
  end

  def handle_event("claim_task", %{"task-id" => task_id}, socket) do
    case Tasks.claim(String.to_integer(task_id), socket.assigns.current_staff.id) do
      {:ok, _task} ->
        {:noreply, socket |> put_flash(:info, gettext("That one is yours now")) |> refresh_data()}

      {:error, reason} ->
        {:noreply, domain_error_flash(socket, reason)}
    end
  end

  def handle_event("advance_task", %{"task-id" => task_id, "status" => status}, socket) do
    case Tasks.update_status(
           String.to_integer(task_id),
           status,
           socket.assigns.current_staff.id
         ) do
      {:ok, _task} -> {:noreply, refresh_data(socket)}
      {:error, reason} -> {:noreply, domain_error_flash(socket, reason)}
    end
  end

  ## Shifts

  def handle_event("toggle_new_shift", _params, socket) do
    open? = not socket.assigns.new_shift_open

    {:noreply,
     socket
     |> assign(new_shift_open: open?, shift_errors: [])
     |> assign(:editing_shift_id, if(open?, do: socket.assigns.editing_shift_id))
     |> refresh_data()}
  end

  def handle_event("edit_shift", %{"shift-id" => id}, socket) do
    {:noreply,
     socket
     |> assign(new_shift_open: true, editing_shift_id: String.to_integer(id), shift_errors: [])
     |> refresh_data()}
  end

  # One form for both, keyed on whether a shift id came back with it — an edit
  # of a roster entry needs exactly the fields creating one does.
  def handle_event("save_shift", params, socket) do
    actor_id = socket.assigns.current_staff.id

    with {:ok, attrs} <- shift_attrs(params) do
      result =
        case params["shift_id"] do
          nil -> Coordination.Shifts.create(actor_id, attrs)
          "" -> Coordination.Shifts.create(actor_id, attrs)
          id -> Coordination.Shifts.update(String.to_integer(id), attrs, actor_id)
        end

      case result do
        {:ok, _shift} ->
          {:noreply,
           socket
           |> assign(new_shift_open: false, editing_shift_id: nil, shift_errors: [])
           |> refresh_data()}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :shift_errors, changeset_messages(changeset))}

        {:error, reason} ->
          {:noreply, domain_error_flash(socket, reason)}
      end
    else
      {:error, message} -> {:noreply, assign(socket, :shift_errors, [message])}
    end
  end

  def handle_event("delete_shift", %{"shift-id" => id}, socket) do
    case Coordination.Shifts.delete(String.to_integer(id), socket.assigns.current_staff.id) do
      {:ok, _} -> {:noreply, socket |> assign(:editing_shift_id, nil) |> refresh_data()}
      {:error, reason} -> {:noreply, domain_error_flash(socket, reason)}
    end
  end

  # A blank selection is the placeholder option, not an instruction.
  def handle_event("assign_shift", %{"staff_id" => ""}, socket), do: {:noreply, socket}

  def handle_event("assign_shift", %{"shift-id" => shift_id, "staff_id" => staff_id}, socket) do
    case Coordination.Shifts.assign(
           String.to_integer(shift_id),
           String.to_integer(staff_id),
           socket.assigns.current_staff.id
         ) do
      {:ok, _} -> {:noreply, refresh_data(socket)}
      {:error, reason} -> {:noreply, domain_error_flash(socket, reason)}
    end
  end

  def handle_event("unassign_shift", %{"shift-id" => shift_id, "staff-id" => staff_id}, socket) do
    case Coordination.Shifts.unassign(
           String.to_integer(shift_id),
           String.to_integer(staff_id),
           socket.assigns.current_staff.id
         ) do
      {:ok, _} -> {:noreply, refresh_data(socket)}
      {:error, reason} -> {:noreply, domain_error_flash(socket, reason)}
    end
  end

  def handle_event("toggle_notifications", _params, socket) do
    {:noreply, assign(socket, :notifications_open, !socket.assigns.notifications_open)}
  end

  # Machine translation is advisory, not authoritative: the reader can always
  # get back to what the author actually wrote. That matters because the text
  # is attacker-influenced — a crafted note could try to talk the translation
  # provider into emitting something other than a translation, and this is the
  # affordance that makes such a discrepancy visible instead of invisible.
  # Navigates rather than patches, for the same reason saving settings does:
  # what this changes is *how* existing text renders, not which assigns feed it.
  # `@request` is unchanged, so LiveView's change tracking would skip
  # re-evaluating the very expressions that need re-running. Remounting from the
  # URL sidesteps that, and keeps the mode shareable and refresh-safe like every
  # other piece of view state here.
  def handle_event("toggle_original", _params, socket) do
    socket = assign(socket, :show_original, not socket.assigns.show_original)
    {:noreply, push_navigate(socket, to: current_path(socket))}
  end

  def handle_event("save_settings", params, socket) do
    attrs = %{
      language: params["language"],
      notify_in_app: params["notify_in_app"] == "true"
    }

    case Coordination.update_staff_settings(socket.assigns.current_staff.id, attrs) do
      {:ok, updated} ->
        # Confirm in the language just chosen, then remount so every static
        # string in the layout is re-rendered in the new locale.
        Gettext.put_locale(SonaWeb.Gettext, locale_for(updated.language))

        {:noreply,
         socket
         |> put_flash(:info, gettext("Settings saved"))
         |> push_navigate(to: current_path(socket))}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Those settings could not be saved."))
         |> refresh_data()}
    end
  end

  def handle_event("approve", %{"staff-id" => staff_id}, socket) do
    case Coordination.approve(
           socket.assigns.request.id,
           String.to_integer(staff_id),
           socket.assigns.current_staff.id
         ) do
      {:ok, _request} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Replacement approved and the team has been updated"))
         |> refresh_data()}

      {:error, reason} ->
        {:noreply, domain_error_flash(socket, reason)}
    end
  end

  def handle_event("acknowledge", _params, socket) do
    case Coordination.acknowledge_handoff(
           socket.assigns.request.id,
           socket.assigns.current_staff.id
         ) do
      {:ok, _request} ->
        {:noreply, socket |> put_flash(:info, gettext("Handoff acknowledged")) |> refresh_data()}

      {:error, reason} ->
        {:noreply, domain_error_flash(socket, reason)}
    end
  end

  def handle_event("reset", _params, socket) do
    Demo.reset_demo()

    {:noreply,
     socket
     |> put_flash(:info, gettext("Demo reset"))
     |> push_navigate(to: ~p"/?view=today&role=supervisor")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="app-shell">
      <aside class="sidebar">
        <div class="brand-lockup">
          <div class="brand-mark">S</div>
          <div>
            <p class="brand-name">Sona</p>
            <p class="brand-subtitle">The Lark Hotel</p>
          </div>
        </div>

        <div class="property-context">
          <span class="eyebrow">{gettext("CURRENT PROPERTY")}</span>
          <strong>Portland / Downtown</strong>
          <span class="status-dot"><i></i> {gettext("Live operations")}</span>
        </div>

        <nav class="desktop-nav" aria-label="Primary navigation">
          <.nav_link view={@view} role={@role} target="today" icon="home" label={gettext("Today")}>
            <span :if={@incidents != []} class="nav-count">{length(@incidents)}</span>
          </.nav_link>
          <.nav_link
            view={@view}
            role={@role}
            target="coverage"
            icon="signal"
            label={gettext("Coverage")}
          >
            <span :if={@incidents != []} class="nav-count amber">{length(@incidents)}</span>
          </.nav_link>
          <.nav_link
            view={@view}
            role={@role}
            target="shifts"
            icon="clock"
            label={gettext("Shifts")}
          />
          <.nav_link
            view={@view}
            role={@role}
            target="messages"
            icon="chat"
            label={gettext("Messages")}
          />
          <.nav_link
            view={@view}
            role={@role}
            target="profile"
            icon="user"
            label={gettext("Profile")}
          />
        </nav>

        <div class="sidebar-footer">
          <button class="reset-button" phx-click="reset">
            <.icon name="refresh" /> {gettext("Reset demo")}
          </button>
          <div class="build-note"><span>Prototype</span><span>v0.1</span></div>
        </div>
      </aside>

      <main class="main-area">
        <header class="topbar">
          <div class="mobile-brand">
            <div class="brand-mark small">S</div><strong>Sona</strong>
          </div>
          <div class="topbar-actions">
            <div class="role-switcher" aria-label="Demo perspective">
              <%!-- Switching persona changes the locale. Gettext strings with no
                    assign reference compile to *static* parts of the LiveView diff
                    and are never re-sent on a patch, so this navigates (full
                    remount) to re-render the whole page in the new language. --%>
              <.link
                :for={{role_key, staff} <- @persona_list}
                navigate={~p"/?view=#{@view}&role=#{role_key}"}
                class={if @role == role_key, do: "role-option active", else: "role-option"}
              >
                <span class={"avatar #{avatar_palette(staff.name)}"}>{initials(staff.name)}</span>
                <span class="role-copy"><small>{gettext("Viewing as")}</small>{staff.name}</span>
                <.icon name="chevron" />
              </.link>
            </div>
            <div class="notification-wrap">
              <button
                class="icon-button notification-button"
                phx-click="toggle_notifications"
                aria-label={gettext("Notifications")}
                aria-expanded={to_string(@notifications_open)}
              >
                <.icon name="bell" />
                <span :if={@notifications != []} class="notification-pip"></span>
              </button>
              <div :if={@notifications_open} class="notification-panel" role="dialog">
                <div class="notification-head">
                  <strong>{gettext("Recent activity")}</strong>
                  <button phx-click="toggle_notifications" aria-label={gettext("Close")}>
                    <.icon name="close" />
                  </button>
                </div>
                <p :if={@notifications_muted} class="notification-empty">
                  {gettext("In-app alerts are off. You can turn them back on in Profile.")}
                </p>
                <p :if={not @notifications_muted and @notifications == []} class="notification-empty">
                  {gettext("Nothing new right now.")}
                </p>
                <div :for={event <- @notifications} class="notification-row">
                  <span class={event_marker_class(event.kind)}></span>
                  <div>
                    <strong>{translate_content(event.body)}</strong>
                    <span>{relative_time(event.inserted_at)} · {event_actor(event)}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </header>

        <div class="content-wrap">
          <%= case @view do %>
            <% "today" -> %>
              <Today.today_view
                role={@role}
                current_staff={@current_staff}
                requester={@requester}
                request={@request}
                incidents={@incidents}
                eligible_map={@eligible_map}
                responses={@responses}
                eligible_staff={@eligible_staff}
                events={@events}
                tasks={@tasks}
                assignable_staff={@assignable_staff}
                new_task_open={@new_task_open}
              />
            <% "coverage" -> %>
              <Coverage.coverage_view
                role={@role}
                current_staff={@current_staff}
                requester={@requester}
                request={@request}
                incidents={@incidents}
                responses={@responses}
                eligible_staff={@eligible_staff}
                question={@question}
                questions={@questions}
                partial_open={@partial_open}
                new_request_open={@new_request_open}
                request_errors={@request_errors}
                departments={@departments}
                staff_names={@staff_names}
              />
            <% "shifts" -> %>
              <Shifts.shifts_view
                role={@role}
                current_staff={@current_staff}
                shifts={@shifts}
                assignable_staff={@assignable_staff}
                new_shift_open={@new_shift_open}
                editing_shift={@editing_shift}
                shift_errors={@shift_errors}
              />
            <% "messages" -> %>
              <Messages.messages_view
                request={@request}
                responses={@responses}
                eligible_staff={@eligible_staff}
              />
            <% "profile" -> %>
              <Profile.profile_view current_staff={@current_staff} />
          <% end %>
        </div>

        <nav class="mobile-nav" aria-label="Mobile navigation">
          <.mobile_link view={@view} role={@role} target="today" icon="home" label={gettext("Today")} />
          <.mobile_link
            view={@view}
            role={@role}
            target="coverage"
            icon="signal"
            label={gettext("Coverage")}
          >
            <span :if={@incidents != []} class="mobile-count">{length(@incidents)}</span>
          </.mobile_link>
          <.mobile_link
            view={@view}
            role={@role}
            target="shifts"
            icon="clock"
            label={gettext("Shifts")}
          />
          <.mobile_link
            view={@view}
            role={@role}
            target="messages"
            icon="chat"
            label={gettext("Messages")}
          />
          <.mobile_link
            view={@view}
            role={@role}
            target="profile"
            icon="user"
            label={gettext("Profile")}
          />
        </nav>
      </main>
    </div>
    """
  end

  attr :view, :string, required: true
  attr :role, :string, required: true
  attr :target, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  slot :inner_block

  defp nav_link(assigns) do
    ~H"""
    <.link
      patch={~p"/?view=#{@target}&role=#{@role}"}
      class={if @view == @target, do: "nav-link active", else: "nav-link"}
    >
      <.icon name={@icon} />{@label}{render_slot(@inner_block)}
    </.link>
    """
  end

  attr :view, :string, required: true
  attr :role, :string, required: true
  attr :target, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  slot :inner_block

  defp mobile_link(assigns) do
    ~H"""
    <.link
      patch={~p"/?view=#{@target}&role=#{@role}"}
      class={if @view == @target, do: "mobile-link active", else: "mobile-link"}
    >
      <.icon name={@icon} /><span>{@label}</span>{render_slot(@inner_block)}
    </.link>
    """
  end

  defp refresh_data(socket) do
    incidents =
      Coordination.active_requests()
      |> Enum.map(&Coordination.request_with_details(&1.id))

    focused =
      Enum.find(incidents, &(&1.id == socket.assigns[:focused_request_id])) ||
        List.first(incidents) ||
        Coordination.request_with_details(Coordination.active_request().id)

    personas = Demo.personas()
    current_staff = Map.fetch!(personas, socket.assigns.role)

    Gettext.put_locale(SonaWeb.Gettext, locale_for(current_staff.language))
    put_show_original(Map.get(socket.assigns, :show_original, false))

    events = Enum.sort_by(focused.activity_events, & &1.inserted_at, {:desc, DateTime})

    # A week either side: enough to see the roster around today without the
    # unbounded query a calendar view will need to think harder about.
    now = DateTime.utc_now()

    shifts =
      Coordination.Shifts.list(current_staff,
        from: DateTime.add(now, -7, :day),
        to: DateTime.add(now, 7, :day)
      )

    eligible_map =
      Map.new([focused | incidents], fn request ->
        {request.id, Coordination.eligible_staff(request)}
      end)

    assign(socket,
      request: focused,
      incidents: incidents,
      eligible_map: eligible_map,
      responses: focused.responses,
      events: events,
      personas: personas,
      persona_list: Enum.map(["supervisor", "frontline"], &{&1, Map.fetch!(personas, &1)}),
      requester: Map.fetch!(personas, "supervisor"),
      show_original: Map.get(socket.assigns, :show_original, false),
      current_staff: current_staff,
      eligible_staff: Map.fetch!(eligible_map, focused.id),
      questions: Enum.filter(events, &(&1.kind == "question")),
      # The in-app channel is a real preference: muting it empties the feed
      # rather than just hiding the dot.
      notifications: if(current_staff.notify_in_app, do: Events.recent(), else: []),
      notifications_muted: not current_staff.notify_in_app,
      departments: Coordination.departments(),
      staff_names: Coordination.staff_names(),
      tasks: Tasks.list(current_staff),
      assignable_staff: Tasks.assignable_staff(current_staff),
      shifts: shifts,
      editing_shift: Enum.find(shifts, &(&1.id == socket.assigns[:editing_shift_id]))
    )
  end

  defp shift_attrs(params) do
    with {:ok, date} <- Date.from_iso8601(params["date"] || ""),
         {:ok, start_time} <- parse_time(params["start_time"]),
         {:ok, end_time} <- parse_time(params["end_time"]) do
      {starts_at, ends_at} = Coordination.Shifts.window_from_form(date, start_time, end_time)

      {:ok,
       %{
         "role" => params["role"],
         "location" => params["location"],
         "starts_at" => starts_at,
         "ends_at" => ends_at
       }}
    else
      _error -> {:error, gettext("Enter a valid date and times.")}
    end
  end

  defp parse_time(value) when is_binary(value), do: Time.from_iso8601(value <> ":00")
  defp parse_time(_value), do: :error

  defp current_path(socket) do
    %{view: view, role: role} = socket.assigns

    query = [view: view, role: role]
    query = if id = socket.assigns[:focused_request_id], do: query ++ [request: id], else: query
    query = if socket.assigns[:show_original], do: query ++ [original: "1"], else: query

    ~p"/?#{query}"
  end

  # Opening the Coverage tab as the frontline persona counts as having
  # seen the request — this is what feeds the supervisor's viewed count.
  defp maybe_mark_viewed(%{assigns: %{role: "frontline", view: "coverage"}} = socket) do
    request = socket.assigns.request

    if active_status?(request.status) do
      Coordination.mark_viewed(request.id, socket.assigns.current_staff.id)
      refresh_data(socket)
    else
      socket
    end
  end

  defp maybe_mark_viewed(socket), do: socket

  defp response_sent_flash(socket) do
    put_flash(
      socket,
      :info,
      gettext("Your response was sent to %{name}",
        name: first_name(socket.assigns.requester.name)
      )
    )
  end

  defp changeset_messages(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _whole, key ->
        opts |> Keyword.get(String.to_existing_atom(key), "") |> to_string()
      end)
    end)
    |> Enum.map(fn {field, messages} ->
      "#{field |> to_string() |> String.replace("_", " ") |> String.capitalize()} #{Enum.join(messages, ", ")}"
    end)
  end

  defp domain_error_flash(socket, reason) do
    socket |> put_flash(:error, domain_error_message(reason)) |> refresh_data()
  end

  defp domain_error_message(:request_closed), do: gettext("This request is already closed.")

  defp domain_error_message(:not_eligible),
    do: gettext("You are not eligible to respond to this request.")

  defp domain_error_message(:not_supervisor),
    do: gettext("Only a supervisor can approve a replacement.")

  defp domain_error_message(:no_offer),
    do: gettext("This team member has not offered to cover the shift.")

  defp domain_error_message(:not_approved),
    do: gettext("This handoff is not ready to acknowledge yet.")

  defp domain_error_message(:not_replacement),
    do: gettext("Only the approved replacement can acknowledge this handoff.")

  # Notes are user content; the demo stores them in canonical English and
  # `translate_content/1` localizes known strings at render time.
  defp default_note("accepted"), do: "I can cover the full shift."
  defp default_note(_type), do: nil

  defp locale_for("Spanish"), do: "es"
  defp locale_for("French"), do: "fr"
  defp locale_for(_), do: "en"
end
