defmodule SonaWeb.HomeLive.Coverage do
  @moduledoc "The Coverage tab: the active incident, response actions, and the team response board."
  use SonaWeb, :html

  import SonaWeb.HomeLive.UI

  alias Sona.Coordination.CoverageRequest

  attr :role, :string, required: true
  attr :current_staff, :map, required: true
  attr :requester, :map, required: true
  attr :request, :map, required: true
  attr :incidents, :list, required: true
  attr :responses, :list, required: true
  attr :eligible_staff, :list, required: true
  attr :question, :string, required: true
  attr :questions, :list, required: true
  attr :partial_open, :boolean, required: true
  attr :new_request_open, :boolean, required: true
  attr :request_errors, :list, required: true
  attr :departments, :list, required: true
  attr :staff_names, :list, required: true

  def coverage_view(assigns) do
    assigns =
      assign(
        assigns,
        :other_incidents,
        Enum.reject(assigns.incidents, &(&1.id == assigns.request.id))
      )

    ~H"""
    <section class="page-heading compact-heading">
      <div>
        <p class="date-line">{gettext("Operations board")}</p>
        <h1>{gettext("Coverage")}</h1>
        <p class="heading-subtitle">
          {gettext("See the open gap, responses, and handoff in one place.")}
        </p>
      </div>
      <button
        :if={@role == "supervisor"}
        class="outline-button"
        phx-click="toggle_new_request"
        aria-expanded={to_string(@new_request_open)}
      >
        <.icon name={if @new_request_open, do: "close", else: "plus"} />
        {if @new_request_open, do: gettext("Cancel"), else: gettext("New coverage request")}
      </button>
    </section>

    <.new_request_form
      :if={@role == "supervisor" and @new_request_open}
      request={@request}
      departments={@departments}
      staff_names={@staff_names}
      request_errors={@request_errors}
    />
    <section class="coverage-board">
      <div class="board-label">
        <span class="section-kicker">{gettext("ACTIVE INCIDENT")}</span>
        <span class={status_class(@request.status)}>{status_label(@request.status)}</span>
      </div>
      <.coverage_card
        request={@request}
        responses={@responses}
        eligible_staff={@eligible_staff}
        role={@role}
        current_staff={@current_staff}
        requester={@requester}
        compact={false}
      />
      <.incident_detail
        request={@request}
        responses={@responses}
        eligible_staff={@eligible_staff}
        role={@role}
        current_staff={@current_staff}
        question={@question}
        questions={@questions}
        partial_open={@partial_open}
      />
    </section>
    <section :if={@other_incidents != []} class="message-list">
      <div class="section-heading compact">
        <div>
          <span class="section-kicker">{gettext("OTHER OPEN REQUESTS")}</span>
          <h2>{gettext("Also needs coverage")}</h2>
        </div>
      </div>
      <div :for={incident <- @other_incidents} class="conversation-row">
        <span class="conversation-icon amber-bg"><.icon name="signal" /></span>
        <div>
          <strong>{incident.role} · {gettext("Today")}, {shift_window(incident)}</strong>
          <span>{status_label(incident.status)} · {incident.location}</span>
        </div>
        <.link
          patch={~p"/?view=coverage&role=#{@role}&request=#{incident.id}"}
          class="text-button"
        >
          {gettext("Open request")} <.icon name="arrow" />
        </.link>
      </div>
    </section>
    """
  end

  attr :request, :map, required: true
  attr :departments, :list, required: true
  attr :staff_names, :list, required: true
  attr :request_errors, :list, required: true

  # Step 1 of the brief's primary scenario: the supervisor states who is
  # missing and which department, role, time, location and urgency the gap
  # covers. Defaults are seeded from the current incident so the demo needs
  # very little typing.
  defp new_request_form(assigns) do
    ~H"""
    <section class="new-request-card">
      <div class="section-heading compact">
        <div>
          <span class="section-kicker">{gettext("NEW COVERAGE REQUEST")}</span>
          <h2>{gettext("Report an absence")}</h2>
        </div>
      </div>

      <div :if={@request_errors != []} class="form-errors" role="alert">
        <strong>{gettext("Please check this form")}</strong>
        <ul>
          <li :for={message <- @request_errors}>{message}</li>
        </ul>
      </div>

      <form id="new-request-form" phx-submit="create_request" class="request-form">
        <label>
          <span>{gettext("Who is unavailable")}</span>
          <input
            name="absent_name"
            list="staff-names"
            autocomplete="off"
            required
            placeholder={gettext("Team member's name")}
          />
          <datalist id="staff-names">
            <option :for={name <- @staff_names} value={name}></option>
          </datalist>
        </label>
        <label>
          <span>{gettext("Department")}</span>
          <select name="department">
            <option :for={department <- @departments} value={department}>{department}</option>
          </select>
        </label>
        <label>
          <span>{gettext("Role needed")}</span>
          <input name="role" required value={@request.role} />
        </label>
        <label>
          <span>{gettext("Date")}</span>
          <input type="date" name="shift_date" required value={Date.to_iso8601(Date.utc_today())} />
        </label>
        <label>
          <span>{gettext("From")}</span>
          <select name="start_time">
            <option :for={time <- day_time_choices()} value={time} selected={time == "18:00"}>
              {time}
            </option>
          </select>
        </label>
        <label>
          <span>{gettext("Until")}</span>
          <select name="end_time">
            <option :for={time <- day_time_choices()} value={time} selected={time == "22:00"}>
              {time}
            </option>
          </select>
        </label>
        <label>
          <span>{gettext("Location")}</span>
          <input name="location" required value={@request.location} />
        </label>
        <label>
          <span>{gettext("Urgency")}</span>
          <select name="urgency">
            <option :for={urgency <- CoverageRequest.urgencies()} value={urgency}>{urgency}</option>
          </select>
        </label>
        <label class="span-two">
          <span>{gettext("What the team needs to know")}</span>
          <textarea name="reason" rows="2" required></textarea>
        </label>
        <label class="span-two">
          <span>{gettext("Handoff note (optional)")}</span>
          <textarea name="handoff_note" rows="2"></textarea>
        </label>
        <button class="primary-button span-two">
          <.icon name="send" /> {gettext("Send to eligible team members")}
        </button>
      </form>
    </section>
    """
  end

  attr :role, :string, required: true
  attr :current_staff, :map, required: true
  attr :request, :map, required: true
  attr :responses, :list, required: true
  attr :eligible_staff, :list, required: true
  attr :question, :string, required: true
  attr :questions, :list, required: true
  attr :partial_open, :boolean, required: true

  defp incident_detail(assigns) do
    ~H"""
    <section class="incident-panel">
      <div class="incident-heading">
        <div>
          <span class="section-kicker">{gettext("COVERAGE REQUEST")}</span>
          <h2>{gettext("Front desk coverage")}</h2>
        </div>
        <span class={status_class(@request.status)}>{status_label(@request.status)}</span>
      </div>
      <div class="step-trail">
        <span :for={{step, label} <- workflow_steps()} class={step_class(@request.status, step)}>
          <i></i>{label}
        </span>
      </div>
      <%= if @role == "frontline" and active_status?(@request.status) do %>
        <div class="localized-actions">
          <div>
            <span class="section-kicker">{gettext("YOUR RESPONSE")}</span>
            <h3>{response_label(response_for(@responses, @current_staff.id))}</h3>
            <p>{translate_content(@request.handoff_note)}</p>
          </div>
          <div class="action-grid">
            <button class="action-button green" phx-click="respond" phx-value-type="accepted">
              <.icon name="check" /> {gettext("I can cover all of it")}
            </button>
            <button class="action-button" phx-click="toggle_partial">
              <.icon name="clock" /> {gettext("I can cover part of it")}
            </button>
            <button class="action-button muted" phx-click="respond" phx-value-type="declined">
              <.icon name="close" /> {gettext("I can't cover it")}
            </button>
          </div>
          <div :if={@partial_open} class="partial-picker">
            <div :if={half_windows(@request) != []} class="partial-presets">
              <span class="partial-hint">{gettext("How much can you cover?")}</span>
              <button
                :for={{label, from, to} <- half_windows(@request)}
                class="action-button"
                phx-click="respond_partial"
                phx-value-from={from}
                phx-value-to={to}
              >
                {label} <em>{from}–{to}</em>
              </button>
            </div>

            <form id="partial-cover-form" class="partial-form" phx-submit="respond_partial">
              <label>
                {gettext("From")}
                <select name="from">
                  <option
                    :for={time <- time_choices(@request.start_time, @request.end_time)}
                    value={time}
                    selected={time == format_time(@request.start_time)}
                  >
                    {time}
                  </option>
                </select>
              </label>
              <label>
                {gettext("Until")}
                <select name="to">
                  <option
                    :for={time <- time_choices(@request.start_time, @request.end_time)}
                    value={time}
                    selected={time == format_time(@request.end_time)}
                  >
                    {time}
                  </option>
                </select>
              </label>
              <button class="primary-button">{gettext("Confirm partial coverage")}</button>
            </form>
          </div>
          <form id="ask-question-form" class="question-form" phx-submit="ask_question">
            <input
              name="question"
              value={@question}
              placeholder={gettext("Ask a question about the shift...")}
              aria-label={gettext("Ask a question")}
            />
            <button aria-label={gettext("Send question")}><.icon name="send" /></button>
          </form>
        </div>
      <% end %>
      <div :if={@role == "supervisor" and @questions != []} class="questions-block">
        <div class="response-heading">
          <div>
            <span class="section-kicker">{gettext("OPEN QUESTIONS")}</span>
            <h3>{gettext("The team asked")}</h3>
          </div>
        </div>
        <div :for={question <- @questions} class="question-row">
          <span class={"avatar response-avatar #{avatar_palette(event_actor(question))}"}>
            {initials(event_actor(question))}
          </span>
          <div>
            <strong>{translate_content(question.body)}</strong>
            <span>{relative_time(question.inserted_at)}</span>
          </div>
        </div>
      </div>
      <%= if @role == "supervisor" do %>
        <div class="response-heading">
          <div>
            <span class="section-kicker">{gettext("TEAM RESPONSES")}</span>
            <h3>{gettext("Who has seen this?")}</h3>
          </div>
          <span>
            {gettext("%{viewed} of %{total} viewed",
              viewed: viewed_count(@responses),
              total: length(@eligible_staff)
            )}
          </span>
        </div>
        <div class="response-list">
          <div :for={response <- @responses} class="response-row">
            <span class={"avatar response-avatar #{avatar_palette(response.staff_member.name)}"}>
              {initials(response.staff_member.name)}
            </span>
            <div>
              <strong>{response.staff_member.name}</strong>
              <span>{response_label(response)}{if window = response_window(response),
                do: " · #{window}"}{if response.note,
                do: " · #{translate_content(response.note)}"}</span>
            </div>
            <span class={response_state_class(response)}>{response_state(response)}</span>
            <button
              :if={offer?(response) and active_status?(@request.status)}
              class="approve-button"
              phx-click="approve"
              phx-value-staff-id={response.staff_member_id}
            >
              {gettext("Approve")}
            </button>
          </div>
        </div>
      <% end %>
      <.resolved_card
        :if={@request.status in ["approved", "resolved"]}
        request={@request}
        responses={@responses}
        role={@role}
        current_staff={@current_staff}
      />
    </section>
    """
  end
end
