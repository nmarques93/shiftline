defmodule SonaWeb.HomeLive.Today do
  @moduledoc "The role-aware Today tab: greeting, shift strip, priority card, work and activity."
  use SonaWeb, :html

  import SonaWeb.HomeLive.UI

  attr :role, :string, required: true
  attr :current_staff, :map, required: true
  attr :requester, :map, required: true
  attr :request, :map, required: true
  attr :incidents, :list, required: true
  attr :eligible_map, :map, required: true
  attr :responses, :list, required: true
  attr :eligible_staff, :list, required: true
  attr :events, :list, required: true

  def today_view(assigns) do
    assigns =
      assign(assigns, :gaps, Sona.Coordination.coverage_gaps(assigns.request, assigns.responses))

    ~H"""
    <section class="page-heading">
      <div>
        <p class="date-line">
          {today_line()} <span class="live-pill"><i></i> {gettext("Live")}</span>
        </p>
        <h1>{gettext("Good afternoon, %{name}", name: first_name(@current_staff.name))}</h1>
        <p class="heading-subtitle">{gettext("Here is what needs your attention today.")}</p>
      </div>
      <div class="language-chip">
        <span class="language-glyph">文</span>
        <span>{language_label(@current_staff.language)}</span>
        <.icon name="chevron" />
      </div>
    </section>

    <div class="shift-strip">
      <div class="shift-icon"><.icon name="clock" /></div>
      <div>
        <span class="eyebrow">{gettext("YOUR SHIFT")}</span>
        <strong>{@current_staff.role}</strong>
      </div>
      <div class="shift-fact"><span>14:00–22:00</span><small>{gettext("Lobby")}</small></div>
      <div class="shift-fact hide-small"><span>3</span><small>{gettext("Open tasks")}</small></div>
      <div class="shift-arrow"><.icon name="arrow" /></div>
    </div>

    <%= if @incidents != [] do %>
      <section class="priority-section">
        <div class="section-heading">
          <div>
            <span class="section-kicker urgent-kicker"><i></i> {gettext("NEEDS A RESPONSE")}</span>
            <h2>
              {cond do
                @role != "supervisor" -> gettext("A team member needs help")
                length(@incidents) == 1 -> gettext("One open coverage request")
                true -> gettext("%{count} open coverage requests", count: length(@incidents))
              end}
            </h2>
          </div>
          <span class="section-count">
            {String.pad_leading("#{length(@incidents)}", 2, "0")}
          </span>
        </div>
        <.coverage_card
          :for={incident <- @incidents}
          request={incident}
          responses={incident.responses}
          eligible_staff={Map.fetch!(@eligible_map, incident.id)}
          role={@role}
          current_staff={@current_staff}
          requester={@requester}
          compact={true}
        />
      </section>
    <% else %>
      <section class="priority-section">
        <div class="section-heading">
          <div>
            <span class={
              if @gaps == [],
                do: "section-kicker success-kicker",
                else: "section-kicker urgent-kicker"
            }>
              <i></i> {cond do
                @gaps != [] -> gettext("PARTIALLY COVERED")
                @request.status == "approved" -> gettext("APPROVED")
                true -> gettext("RESOLVED")
              end}
            </span>
            <h2>
              {cond do
                @request.status == "approved" -> gettext("Handoff needs acknowledgement")
                @gaps != [] -> gettext("Coverage partially confirmed")
                true -> gettext("Coverage is confirmed")
              end}
            </h2>
          </div>
          <span class="section-count">01</span>
        </div>
        <.resolved_card
          request={@request}
          responses={@responses}
          role={@role}
          current_staff={@current_staff}
        />
      </section>
    <% end %>

    <div class="lower-grid">
      <section class="panel-section">
        <div class="section-heading compact">
          <div>
            <span class="section-kicker">{gettext("ON YOUR SHIFT")}</span>
            <h2>{gettext("Current work")}</h2>
          </div>
          <button class="text-button">{gettext("View shift")} <.icon name="arrow" /></button>
        </div>
        <div class="task-list">
          <div class="task-row">
            <span class="task-check"></span>
            <div>
              <strong>{gettext("Complete lobby handoff checklist")}</strong>
              <span>{gettext("Due 17:45 · Front desk")}</span>
            </div>
            <span class="task-status pending">{gettext("Not started")}</span>
          </div>
          <div class="task-row done">
            <span class="task-check"><.icon name="check" /></span>
            <div>
              <strong>{gettext("Review guest arrival notes")}</strong>
              <span>{gettext("Completed 15:20 · Front desk")}</span>
            </div>
            <span class="task-status">{gettext("Done")}</span>
          </div>
        </div>
      </section>
      <section class="panel-section activity-panel">
        <div class="section-heading compact">
          <div>
            <span class="section-kicker">{gettext("TEAM HANDOFFS")}</span>
            <h2>{gettext("What changed")}</h2>
          </div>
          <button class="text-button">{gettext("See all")} <.icon name="arrow" /></button>
        </div>
        <div class="activity-list">
          <div :for={event <- Enum.take(@events, 2)} class="activity-row">
            <span class={event_marker_class(event.kind)}></span>
            <div>
              <strong>{translate_content(event.body)}</strong>
              <span>{relative_time(event.inserted_at)} · {event_actor(event)}</span>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
