defmodule Shiftline.Coordination.Notifier do
  @moduledoc """
  The one place that knows how a coordination change reaches connected
  clients.

  Every write in the domain ends here and every LiveView subscribes through
  `subscribe/0`, so the set of messages a client has to handle is this
  module's public API rather than something you discover by grepping for
  `broadcast`.

  Five messages, deliberately distinct so a client can react narrowly:

    * `{:coordination_updated, request_id}` — a coverage request changed
    * `{:settings_updated, staff_id}` — one person's language or alerts changed
    * `:tasks_updated` — the shift task board changed
    * `:shifts_updated` — the roster changed
    * `:messages_updated` — a conversation changed
  """

  @topic "coordination"

  def subscribe, do: Phoenix.PubSub.subscribe(Shiftline.PubSub, @topic)

  def broadcast(request_id) do
    Phoenix.PubSub.broadcast(Shiftline.PubSub, @topic, {:coordination_updated, request_id})
  end

  def broadcast_settings(staff_id) do
    Phoenix.PubSub.broadcast(Shiftline.PubSub, @topic, {:settings_updated, staff_id})
  end

  def broadcast_tasks do
    Phoenix.PubSub.broadcast(Shiftline.PubSub, @topic, :tasks_updated)
  end

  def broadcast_shifts do
    Phoenix.PubSub.broadcast(Shiftline.PubSub, @topic, :shifts_updated)
  end

  def broadcast_messages do
    Phoenix.PubSub.broadcast(Shiftline.PubSub, @topic, :messages_updated)
  end

  @doc """
  Queues user-entered text for translation and broadcasts once it lands, so
  other windows re-render in their own language without the writer ever
  waiting on a translation provider.
  """
  def translate_content(texts, request_id) do
    schedule(texts, fn -> broadcast(request_id) end)
  end

  @doc """
  The same, for task titles. A title is typed by a supervisor this morning,
  so Gettext cannot cover it and it needs the runtime path too.
  """
  def translate_task_content(texts) do
    schedule(texts, &broadcast_tasks/0)
  end

  @doc """
  The same, for what people say to each other. This is the path the product's
  central claim rests on: a Spanish speaker reads a note typed in English
  without either of them choosing to translate anything.
  """
  def translate_message_content(texts) do
    schedule(texts, &broadcast_messages/0)
  end

  defp schedule(texts, on_complete) do
    texts
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> Enum.each(&Shiftline.Translation.translate_later(&1, on_complete))
  end
end
