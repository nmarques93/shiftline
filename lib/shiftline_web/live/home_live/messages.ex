defmodule ShiftlineWeb.HomeLive.Messages do
  @moduledoc """
  The Messages tab: the department channel, a direct line to each colleague,
  and the pinned announcements that sit above both.

  One conversation is open at a time and which one is URL state, so the list
  and the thread never compete for the same screen — the brief's primary
  device is a phone. `Shiftline.Coordination.Messages` owns who may read and write
  what; this module only draws what that context already allows.
  """
  use ShiftlineWeb, :html

  import ShiftlineWeb.HomeLive.UI

  attr :role, :string, required: true
  attr :current_staff, :map, required: true
  attr :conversations, :list, required: true
  attr :conversation, :map, default: nil
  attr :thread, :list, default: []
  attr :pinned, :list, required: true
  attr :channel_audience, :integer, required: true

  def messages_view(assigns) do
    ~H"""
    <section class="page-heading compact-heading">
      <div>
        <p class="date-line">{@current_staff.department} / {gettext("Today")}</p>
        <h1>{gettext("Messages")}</h1>
        <p class="heading-subtitle">
          {gettext("Conversations stay attached to the work they change.")}
        </p>
      </div>
    </section>

    <%= if @conversation do %>
      <.thread
        conversation={@conversation}
        thread={@thread}
        role={@role}
        current_staff={@current_staff}
      />
    <% else %>
      <.pinned_announcements
        pinned={@pinned}
        current_staff={@current_staff}
        audience={@channel_audience}
      />
      <.conversation_list conversations={@conversations} role={@role} />
    <% end %>
    """
  end

  ## Pinned announcements

  attr :pinned, :list, required: true
  attr :current_staff, :map, required: true
  attr :audience, :integer, required: true

  defp pinned_announcements(assigns) do
    ~H"""
    <section :for={message <- @pinned} class="message-preview">
      <div class="message-header">
        <div>
          <span class="section-kicker">{gettext("PINNED FOR YOUR TEAM")}</span>
          <h2>{message.sender.name} · {message.department}</h2>
        </div>
        <span :if={message.urgent} class="status-label urgent">
          <i></i> {gettext("URGENT")}
        </span>
      </div>
      <p>{translate_content(message.body)}</p>
      <.translation_note texts={[message.body]} current_staff={@current_staff} />
      <div class="message-footer">
        <span>
          {gettext("Seen by %{seen} of %{total} · acknowledged by %{acknowledged}",
            seen: seen_count(message),
            total: @audience,
            acknowledged: acknowledged_count(message)
          )}
        </span>
        <button
          :if={
            message.urgent and message.sender_id != @current_staff.id and
              not acknowledged_by?(message, @current_staff)
          }
          class="primary-button"
          phx-click="acknowledge_message"
          phx-value-message-id={message.id}
        >
          <.icon name="check" /> {gettext("Acknowledge")}
        </button>
        <span :if={acknowledged_by?(message, @current_staff)} class="acknowledged">
          <.icon name="check" /> {gettext("You acknowledged this")}
        </span>
      </div>
    </section>
    """
  end

  ## Conversation list

  attr :conversations, :list, required: true
  attr :role, :string, required: true

  defp conversation_list(assigns) do
    ~H"""
    <section class="message-list">
      <div class="section-heading compact">
        <div>
          <span class="section-kicker">{gettext("CONVERSATIONS")}</span>
          <h2>{gettext("Your channels and people")}</h2>
        </div>
      </div>
      <.link
        :for={conversation <- @conversations}
        patch={~p"/?view=messages&role=#{@role}&conversation=#{conversation.id}"}
        class="conversation-row"
      >
        <span class={conversation_icon_class(conversation)}>
          <.icon name={if conversation.kind == :department, do: "chat", else: "user"} />
        </span>
        <div>
          <strong>{conversation_title(conversation)}</strong>
          <span>{preview(conversation)}</span>
        </div>
        <span :if={conversation.urgent?} class="status-label urgent"><i></i> {gettext("URGENT")}</span>
        <span :if={conversation.unread > 0} class="unread-count">{conversation.unread}</span>
      </.link>
    </section>
    """
  end

  ## One conversation

  attr :conversation, :map, required: true
  attr :thread, :list, required: true
  attr :role, :string, required: true
  attr :current_staff, :map, required: true

  defp thread(assigns) do
    ~H"""
    <section class="thread">
      <div class="thread-head">
        <.link patch={~p"/?view=messages&role=#{@role}"} class="text-button">
          <.icon name="chevron" /> {gettext("All conversations")}
        </.link>
        <div>
          <span class="section-kicker">{conversation_kicker(@conversation)}</span>
          <h2>{conversation_title(@conversation)}</h2>
        </div>
      </div>

      <p :if={@thread == []} class="task-empty">
        {gettext("Nothing here yet. Say the first thing.")}
      </p>

      <%!-- One note for the conversation rather than one per message: the fact
            being stated is about the whole thread, and repeating it under every
            bubble would bury the messages themselves. --%>
      <.translation_note
        texts={Enum.map(@thread, & &1.body)}
        current_staff={@current_staff}
      />

      <article
        :for={message <- @thread}
        class={if message.sender_id == @current_staff.id, do: "bubble mine", else: "bubble"}
      >
        <div class="bubble-head">
          <span class={"avatar tiny #{avatar_palette(message.sender.name)}"}>
            {initials(message.sender.name)}
          </span>
          <strong>{message.sender.name}</strong>
          <span :if={message.urgent} class="status-label urgent"><i></i> {gettext("URGENT")}</span>
          <span class="bubble-time">{relative_time(message.inserted_at)}</span>
        </div>
        <p>{translate_content(message.body)}</p>
        <div class="bubble-footer">
          <span :if={message.sender_id == @current_staff.id}>
            {gettext("Seen by %{seen} of %{total}",
              seen: seen_count(message),
              total: @conversation.audience_size
            )}
          </span>
          <span :if={message.urgent and message.sender_id == @current_staff.id}>
            {gettext("· acknowledged by %{count}", count: acknowledged_count(message))}
          </span>
          <button
            :if={
              message.urgent and message.sender_id != @current_staff.id and
                not acknowledged_by?(message, @current_staff)
            }
            class="primary-button"
            phx-click="acknowledge_message"
            phx-value-message-id={message.id}
          >
            <.icon name="check" /> {gettext("Acknowledge")}
          </button>
          <span
            :if={message.urgent and acknowledged_by?(message, @current_staff)}
            class="acknowledged"
          >
            <.icon name="check" /> {gettext("Acknowledged")}
          </span>
        </div>
      </article>

      <form id="message-form" class="composer" phx-submit="send_message">
        <input type="hidden" name="conversation" value={@conversation.id} />
        <textarea
          name="body"
          rows="2"
          required
          placeholder={gettext("Write a message…")}
          aria-label={gettext("Write a message")}
        ></textarea>
        <div class="composer-actions">
          <label class="composer-flag">
            <input type="checkbox" name="urgent" value="true" />
            <span>{gettext("Mark urgent")}</span>
          </label>
          <label :if={pinnable?(@conversation, @current_staff)} class="composer-flag">
            <input type="checkbox" name="pinned" value="true" />
            <span>{gettext("Pin for the team")}</span>
          </label>
          <button class="primary-button">
            <.icon name="send" /> {gettext("Send")}
          </button>
        </div>
      </form>
    </section>
    """
  end

  ## The translation affordance, on every piece of text a person typed

  attr :texts, :list, required: true
  attr :current_staff, :map, required: true

  defp translation_note(assigns) do
    assigns =
      assign(assigns,
        translated?: Enum.any?(assigns.texts, &content_translated?/1),
        untranslated?:
          assigns.current_staff.language != "English" and
            Enum.any?(assigns.texts, &(not content_translated?(&1)))
      )

    ~H"""
    <div :if={@translated?} class="translation-note">
      <span class="language-glyph">文</span>
      {language_label(@current_staff.language)} <span>·</span>
      <span>{gettext("Translated automatically")}</span>
      <span>·</span>
      <button type="button" phx-click="toggle_original">
        {if show_original?(), do: gettext("Show translation"), else: gettext("Show original")}
      </button>
    </div>
    <%!-- Saying nothing here would let an English message pass for one written
          in the reader's language. --%>
    <div :if={@untranslated?} class="translation-note muted">
      <span class="language-glyph">文</span>
      <span>{gettext("Shown in its original language")}</span>
    </div>
    """
  end

  ## Helpers

  defp conversation_title(%{kind: :department, title: title}), do: title
  defp conversation_title(%{title: title}), do: title

  defp conversation_kicker(%{kind: :department}), do: gettext("DEPARTMENT CHANNEL")
  defp conversation_kicker(%{partner: partner}), do: String.upcase(partner.role)

  defp conversation_icon_class(%{kind: :department}), do: "conversation-icon moss-bg"
  defp conversation_icon_class(_conversation), do: "conversation-icon amber-bg"

  defp preview(%{last_message: nil, kind: :department}),
    do: gettext("No messages in this channel yet")

  defp preview(%{last_message: nil, partner: partner}),
    do: gettext("Start a conversation with %{name}", name: first_name(partner.name))

  defp preview(%{last_message: message}) do
    "#{first_name(message.sender.name)} · #{translate_content(message.body)}"
  end

  # Pinning is a department announcement, so it is offered only where the
  # context would accept it: a supervisor, writing in a channel.
  defp pinnable?(%{kind: :department}, %{is_supervisor: true}), do: true
  defp pinnable?(_conversation, _staff), do: false

  defp seen_count(message), do: Enum.count(message.reads, & &1.viewed_at)

  defp acknowledged_count(message), do: Enum.count(message.reads, & &1.acknowledged_at)

  defp acknowledged_by?(message, staff) do
    Enum.any?(message.reads, &(&1.staff_member_id == staff.id and &1.acknowledged_at))
  end
end
