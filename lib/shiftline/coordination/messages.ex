defmodule Shiftline.Coordination.Messages do
  @moduledoc """
  Conversations: a channel per department, and a direct line between any two
  people.

  This is the brief's headline noun, and it is deliberately not a general chat
  system. Two audiences exist and no more — your department, or one colleague —
  because every extra way to address a message is another way for a shift
  instruction to reach the wrong people. There are no threads: a reply is the
  next message in the conversation it belongs to, and the coverage workflow
  already owns the one place where replies hang off a specific incident.

  Two flags carry the operational weight the brief asks for:

    * `urgent` — anyone can raise one, because a frontline blocker is as urgent
      as a supervisor's instruction, and it is what makes "which messages are
      urgent?" answerable.
    * `pinned` — supervisor-only, and department channels only. Pinning is the
      announcement affordance, so it is the one that needs a role behind it.

  Read and acknowledgement live in `Shiftline.Coordination.MessageRead`, the same
  two-timestamp shape as a coverage response. Opening a conversation records
  that you saw it; an urgent message additionally asks you to say so.

  Like everywhere else in this domain, every write takes an explicit actor id
  and checks it — the sender's department is read from the sender, never from
  the caller.
  """

  import Ecto.Query

  alias Shiftline.Coordination.{Message, MessageRead, Notifier, StaffMember}
  alias Shiftline.Repo

  @department_conversation "department"

  @doc "The conversation id for a staff member's own department channel."
  def department_conversation, do: @department_conversation

  @doc "The conversation id for a direct line with `staff`."
  def direct_conversation(%StaffMember{id: id}), do: "direct:#{id}"

  ## Reads

  @doc """
  Every conversation this person has, department channel first.

  Direct rows are listed for each colleague in their own department whether or
  not anything has been said yet — starting a 1-to-1 should not need a "new
  message" screen — plus anyone outside it they have already talked to.
  """
  def conversations(%StaffMember{} = staff) do
    messages = visible_messages(staff)
    read_ids = read_message_ids(staff)
    channel_audience = department_size(staff) - 1

    channel_messages = Enum.filter(messages, &(&1.department != nil))
    direct_messages = Enum.filter(messages, &(&1.department == nil))

    by_partner = Enum.group_by(direct_messages, &partner_id(&1, staff))

    directs =
      staff
      |> direct_partners(Map.keys(by_partner))
      |> Enum.map(fn partner ->
        conversation(
          direct_conversation(partner),
          :direct,
          partner.name,
          partner,
          Map.get(by_partner, partner.id, []),
          1,
          staff,
          read_ids
        )
      end)
      |> Enum.sort_by(&sort_key/1)

    channel =
      conversation(
        @department_conversation,
        :department,
        staff.department,
        nil,
        channel_messages,
        channel_audience,
        staff,
        read_ids
      )

    [channel | directs]
  end

  @doc """
  The messages in one conversation, oldest first, or `{:error, :unknown_conversation}`.

  The scoping is the authorization: a department id only ever resolves to the
  reader's own department, and a direct id only to messages between the two
  people named, so there is no id a caller can pass to read someone else's
  conversation.
  """
  def thread(%StaffMember{} = staff, conversation_id) do
    with {:ok, audience} <- resolve(staff, conversation_id) do
      {:ok,
       audience
       |> scope(staff)
       |> order_by([message], asc: message.inserted_at, asc: message.id)
       |> preload([:sender, reads: :staff_member])
       |> Repo.all()}
    end
  end

  @doc """
  The pinned announcements for this person's department, newest first.

  Pinned messages are the thing that has to be visible without opening a
  conversation, so they are read separately rather than filtered out of a
  thread.
  """
  def pinned_for(%StaffMember{} = staff) do
    Repo.all(
      from message in Message,
        where: message.department == ^staff.department and message.pinned,
        order_by: [desc: message.inserted_at, desc: message.id],
        preload: [:sender, reads: :staff_member]
    )
  end

  @doc "How many messages this person has not opened yet, across every conversation."
  def unread_count(%StaffMember{} = staff) do
    read_ids = read_message_ids(staff)

    staff
    |> visible_messages()
    |> Enum.count(&unread?(&1, staff, read_ids))
  end

  ## Writes

  @doc """
  Posts a message into a conversation on behalf of `sender_id`.

  Options: `:urgent` and `:pinned`. Pinning is supervisor-only and meaningless
  on a direct message, so it is rejected rather than silently dropped.
  """
  def send_message(sender_id, conversation_id, body, opts \\ []) when is_binary(body) do
    sender = Repo.get!(StaffMember, sender_id)
    body = String.trim(body)
    pinned = Keyword.get(opts, :pinned, false)

    with {:ok, audience} <- resolve(sender, conversation_id),
         :ok <- validate_body(body),
         :ok <- validate_pin(sender, audience, pinned) do
      attrs =
        audience
        |> address()
        |> Map.merge(%{
          "body" => body,
          "sender_id" => sender.id,
          "urgent" => Keyword.get(opts, :urgent, false),
          "pinned" => pinned
        })

      case %Message{} |> Message.changeset(attrs) |> Repo.insert() do
        {:ok, message} ->
          Notifier.translate_message_content([message.body])
          Notifier.broadcast_messages()
          {:ok, Repo.preload(message, [:sender, reads: :staff_member])}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Records that `staff` has opened a conversation, marking every message in it
  that somebody else wrote as seen.

  Returns the number of messages that changed, so a caller can skip
  broadcasting when nothing did — the alternative is every client re-rendering
  each time anyone opens a thread they have already read.
  """
  def mark_read(%StaffMember{} = staff, conversation_id) do
    with {:ok, audience} <- resolve(staff, conversation_id) do
      read_ids = read_message_ids(staff)

      unseen =
        audience
        |> scope(staff)
        |> Repo.all()
        |> Enum.filter(&unread?(&1, staff, read_ids))

      Enum.each(unseen, &upsert_read(&1.id, staff.id, %{viewed_at: now()}))
      if unseen != [], do: Notifier.broadcast_messages()

      {:ok, length(unseen)}
    end
  end

  @doc """
  Records that this person has acknowledged an urgent message.

  Only someone the message was addressed to can acknowledge it, and only an
  urgent message asks to be acknowledged at all — an acknowledgement on an
  ordinary message would be a promise nobody made.
  """
  def acknowledge(message_id, staff_id) do
    message = Repo.get!(Message, message_id)
    staff = Repo.get!(StaffMember, staff_id)

    cond do
      not message.urgent -> {:error, :not_urgent}
      not addressed_to?(message, staff) -> {:error, :not_addressed}
      true -> {:ok, do_acknowledge(message, staff)}
    end
  end

  defp do_acknowledge(message, staff) do
    now = now()
    read = upsert_read(message.id, staff.id, %{viewed_at: now, acknowledged_at: now})
    Notifier.broadcast_messages()
    read
  end

  ## Conversation ids

  # A conversation id is resolved against the reader every time rather than
  # trusted: "department" means *their* department, and a direct id has to name
  # somebody who exists.
  defp resolve(%StaffMember{} = staff, @department_conversation),
    do: {:ok, {:department, staff.department}}

  defp resolve(%StaffMember{} = staff, "direct:" <> id) do
    with {partner_id, ""} <- Integer.parse(id),
         true <- partner_id != staff.id,
         %StaffMember{} = partner <- Repo.get(StaffMember, partner_id) do
      {:ok, {:direct, partner}}
    else
      _otherwise -> {:error, :unknown_conversation}
    end
  end

  defp resolve(_staff, _other), do: {:error, :unknown_conversation}

  defp address({:department, department}), do: %{"department" => department}
  defp address({:direct, partner}), do: %{"recipient_id" => partner.id}

  defp scope({:department, department}, _staff) do
    from message in Message, where: message.department == ^department
  end

  defp scope({:direct, partner}, staff) do
    from message in Message,
      where:
        (message.sender_id == ^staff.id and message.recipient_id == ^partner.id) or
          (message.sender_id == ^partner.id and message.recipient_id == ^staff.id)
  end

  ## Helpers

  # Everything this person is allowed to see, newest first. Loading the lot is
  # honest at a property's volume and keeps the conversation list a single
  # query; the day it is not, this is the function that grows a per-conversation
  # aggregate rather than the callers.
  defp visible_messages(%StaffMember{} = staff) do
    Repo.all(
      from message in Message,
        where:
          message.department == ^staff.department or
            message.recipient_id == ^staff.id or
            (message.sender_id == ^staff.id and not is_nil(message.recipient_id)),
        order_by: [desc: message.inserted_at, desc: message.id],
        preload: [:sender]
    )
  end

  defp department_size(%StaffMember{department: department}) do
    Repo.aggregate(from(staff in StaffMember, where: staff.department == ^department), :count)
  end

  defp read_message_ids(%StaffMember{} = staff) do
    MapSet.new(
      Repo.all(
        from read in MessageRead,
          where: read.staff_member_id == ^staff.id and not is_nil(read.viewed_at),
          select: read.message_id
      )
    )
  end

  defp unread?(message, staff, read_ids),
    do: message.sender_id != staff.id and not MapSet.member?(read_ids, message.id)

  defp partner_id(%Message{sender_id: sender_id, recipient_id: recipient_id}, staff),
    do: if(sender_id == staff.id, do: recipient_id, else: sender_id)

  # Colleagues in the same department, plus anyone else already in a direct
  # conversation with this person — a supervisor who messaged Housekeeping
  # should not lose the thread just because they do not work there.
  defp direct_partners(%StaffMember{} = staff, known_ids) do
    Repo.all(
      from person in StaffMember,
        where: person.id != ^staff.id,
        where: person.department == ^staff.department or person.id in ^known_ids,
        order_by: [asc: person.name]
    )
  end

  defp conversation(id, kind, title, partner, messages, audience_size, staff, read_ids) do
    %{
      id: id,
      kind: kind,
      title: title,
      partner: partner,
      # Everyone this conversation reaches other than the reader — the
      # denominator in "seen by 4 of 7".
      audience_size: audience_size,
      last_message: List.first(messages),
      unread: Enum.count(messages, &unread?(&1, staff, read_ids)),
      urgent?: Enum.any?(messages, &(&1.urgent and unread?(&1, staff, read_ids)))
    }
  end

  # Conversations with something in them come first, most recent first; the
  # rest fall back to name order so the list is stable.
  defp sort_key(%{last_message: nil, title: title}), do: {1, nil, title}

  defp sort_key(%{last_message: message, title: title}),
    do: {0, -DateTime.to_unix(message.inserted_at), title}

  # The sender is never part of their own audience: acknowledging your own
  # announcement would inflate the count a supervisor reads as "it landed".
  defp addressed_to?(%Message{sender_id: sender_id}, %StaffMember{id: sender_id}), do: false

  defp addressed_to?(%Message{department: nil} = message, staff),
    do: message.recipient_id == staff.id

  defp addressed_to?(%Message{department: department}, staff),
    do: staff.department == department

  defp validate_body(""), do: {:error, :empty_message}
  defp validate_body(_body), do: :ok

  defp validate_pin(_sender, _audience, false), do: :ok

  defp validate_pin(%StaffMember{is_supervisor: false}, _audience, true),
    do: {:error, :not_supervisor}

  defp validate_pin(_sender, {:direct, _partner}, true), do: {:error, :cannot_pin_direct}
  defp validate_pin(_sender, _audience, true), do: :ok

  defp upsert_read(message_id, staff_id, attrs) do
    existing =
      Repo.get_by(MessageRead, message_id: message_id, staff_member_id: staff_id) ||
        %MessageRead{}

    existing
    |> MessageRead.changeset(
      Map.merge(attrs, %{message_id: message_id, staff_member_id: staff_id})
    )
    |> Repo.insert_or_update!()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
