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
  alias SonaWeb.HomeLive.{Coverage, Messages, Profile, Today}

  import SonaWeb.HomeLive.UI

  @views ~w(today coverage messages profile)
  @roles ~w(supervisor frontline)

  @impl true
  def mount(_params, _session, socket) do
    Coordination.ensure_demo_data()
    if connected?(socket), do: Coordination.subscribe()

    {:ok,
     assign(socket,
       role: "supervisor",
       view: "today",
       question: "",
       partial_open: false,
       notifications_open: false,
       new_request_open: false,
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
       request_errors: [],
       focused_request_id: focused_request_id
     )
     |> refresh_data()
     |> maybe_mark_viewed()}
  end

  @impl true
  def handle_info({:coordination_updated, _request_id}, socket) do
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

  def handle_event("toggle_notifications", _params, socket) do
    {:noreply, assign(socket, :notifications_open, !socket.assigns.notifications_open)}
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
    Coordination.reset_demo()

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

    personas = Coordination.personas()
    current_staff = Map.fetch!(personas, socket.assigns.role)

    Gettext.put_locale(SonaWeb.Gettext, locale_for(current_staff.language))

    events = Enum.sort_by(focused.activity_events, & &1.inserted_at, {:desc, DateTime})

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
      current_staff: current_staff,
      eligible_staff: Map.fetch!(eligible_map, focused.id),
      questions: Enum.filter(events, &(&1.kind == "question")),
      # The in-app channel is a real preference: muting it empties the feed
      # rather than just hiding the dot.
      notifications: if(current_staff.notify_in_app, do: Coordination.recent_events(), else: []),
      notifications_muted: not current_staff.notify_in_app,
      departments: Coordination.departments()
    )
  end

  defp current_path(socket) do
    %{view: view, role: role} = socket.assigns

    case socket.assigns[:focused_request_id] do
      nil -> ~p"/?view=#{view}&role=#{role}"
      id -> ~p"/?view=#{view}&role=#{role}&request=#{id}"
    end
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
