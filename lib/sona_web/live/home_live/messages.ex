defmodule SonaWeb.HomeLive.Messages do
  @moduledoc """
  The Messages tab. Deliberately a static preview in this prototype — the
  coverage workflow is the deep slice — except for the coverage row, which
  reflects the real request state.
  """
  use SonaWeb, :html

  import SonaWeb.HomeLive.UI

  attr :request, :map, required: true
  attr :responses, :list, required: true
  attr :eligible_staff, :list, required: true

  def messages_view(assigns) do
    ~H"""
    <section class="page-heading compact-heading">
      <div>
        <p class="date-line">{gettext("Front Office / Today")}</p>
        <h1>{gettext("Messages")}</h1>
        <p class="heading-subtitle">
          {gettext("Conversations stay attached to the work they change.")}
        </p>
      </div>
      <button class="outline-button"><.icon name="plus" /> {gettext("New message")}</button>
    </section>
    <section class="message-preview">
      <div class="message-header">
        <div>
          <span class="section-kicker">{gettext("PINNED FOR YOUR TEAM")}</span>
          <h2>{gettext("Front Office · Evening handoff")}</h2>
        </div>
        <span class="message-status">{gettext("Preview")}</span>
      </div>
      <p>
        {gettext(
          "Welcome Ana, our new night auditor. Please introduce yourself during the 17:45 handoff."
        )}
      </p>
      <div class="message-footer">
        <span class="avatar-stack">
          <span class="avatar tiny maya">MC</span>
          <span class="avatar tiny luis">LG</span>
          <span class="avatar tiny priya">PS</span>
        </span>
        <span>{gettext("Front Office team · illustrative preview")}</span>
        <button class="text-button">{gettext("Open thread")} <.icon name="arrow" /></button>
      </div>
    </section>
    <section class="message-list">
      <div class="section-heading compact">
        <div>
          <span class="section-kicker">{gettext("RECENT CONVERSATIONS")}</span>
          <h2>{gettext("Team activity")}</h2>
        </div>
      </div>
      <div class="conversation-row">
        <span class="conversation-icon amber-bg"><.icon name="signal" /></span>
        <div>
          <strong>{gettext("Coverage needed · Front desk")}</strong>
          <span>Maya · {response_summary(@responses, @eligible_staff)}</span>
        </div>
        <span :if={active_status?(@request.status)} class="unread-dot"></span>
      </div>
      <div class="conversation-row">
        <span class="conversation-icon moss-bg"><.icon name="chat" /></span>
        <div>
          <strong>{gettext("Maintenance handoff")}</strong>
          <span>{gettext("Engineering · Ice machine issue cleared")}</span>
        </div>
      </div>
    </section>
    """
  end
end
