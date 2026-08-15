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
  attr :tasks, :list, required: true
  attr :assignable_staff, :list, required: true
  attr :new_task_open, :boolean, required: true

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
      <.link
        patch={~p"/?view=profile&role=#{@role}"}
        class="language-chip"
        title={gettext("Change your language in Profile")}
      >
        <span class="language-glyph">文</span>
        <span>{language_label(@current_staff.language)}</span>
        <.icon name="arrow" />
      </.link>
    </section>

    <div class="shift-strip">
      <div class="shift-icon"><.icon name="clock" /></div>
      <div>
        <span class="eyebrow">{gettext("YOUR SHIFT")}</span>
        <strong>{@current_staff.role}</strong>
      </div>
      <div class="shift-fact"><span>14:00–22:00</span><small>{gettext("Lobby")}</small></div>
      <div class="shift-fact hide-small">
        <span>{Enum.count(@tasks, &(&1.status != "done"))}</span>
        <small>{gettext("Open tasks")}</small>
      </div>
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
          <button
            :if={@role == "supervisor"}
            class="text-button"
            phx-click="toggle_new_task"
            aria-expanded={to_string(@new_task_open)}
          >
            <.icon name={if @new_task_open, do: "close", else: "plus"} />
            {if @new_task_open, do: gettext("Cancel"), else: gettext("Assign work")}
          </button>
        </div>

        <form
          :if={@role == "supervisor" and @new_task_open}
          id="new-task-form"
          class="task-form"
          phx-submit="create_task"
        >
          <input name="title" required placeholder={gettext("What needs doing?")} />
          <select name="assignee_id">
            <option value="">{gettext("Anyone on the team")}</option>
            <option :for={person <- @assignable_staff} value={person.id}>{person.name}</option>
          </select>
          <select name="due_time" aria-label={gettext("Due")}>
            <option value="">{gettext("No due time")}</option>
            <option :for={time <- day_time_choices()} value={time}>{time}</option>
          </select>
          <button class="primary-button">{gettext("Add task")}</button>
        </form>

        <p :if={@tasks == []} class="task-empty">{gettext("No work assigned for today.")}</p>

        <div class="task-list">
          <div :for={task <- @tasks} class={task_row_class(task)}>
            <span class="task-check">
              <.icon :if={task.status == "done"} name="check" />
            </span>
            <div>
              <strong>{translate_content(task.title)}</strong>
              <span>{task_meta(task, @role)}</span>
            </div>

            <form :if={@role == "supervisor"} id={"assign-task-#{task.id}"} phx-change="assign_task">
              <input type="hidden" name="task-id" value={task.id} />
              <select
                class="task-assignee"
                name="assignee_id"
                aria-label={gettext("Assign this task")}
              >
                <option value="" selected={is_nil(task.assignee_id)}>{gettext("Unassigned")}</option>
                <option
                  :for={person <- @assignable_staff}
                  value={person.id}
                  selected={task.assignee_id == person.id}
                >
                  {person.name}
                </option>
              </select>
            </form>

            <button
              :if={@role != "supervisor" and is_nil(task.assignee_id)}
              class="task-action"
              phx-click="claim_task"
              phx-value-task-id={task.id}
            >
              {gettext("Claim")}
            </button>

            <button
              :if={next_status(task, @current_staff, @role)}
              class="task-action"
              phx-click="advance_task"
              phx-value-task-id={task.id}
              phx-value-status={next_status(task, @current_staff, @role)}
            >
              {next_status_label(next_status(task, @current_staff, @role))}
            </button>

            <span class={task_status_class(task)}>{task_status_label(task.status)}</span>
          </div>
        </div>
      </section>
      <section class="panel-section activity-panel">
        <div class="section-heading compact">
          <div>
            <span class="section-kicker">{gettext("TEAM HANDOFFS")}</span>
            <h2>{gettext("What changed")}</h2>
          </div>
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
