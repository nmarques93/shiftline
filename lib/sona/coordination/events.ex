defmodule Sona.Coordination.Events do
  @moduledoc """
  The activity feed: what happened on a coverage request, in the words the
  team will actually read.

  Event bodies are composed sentences carrying real names and times, so they
  can never be Gettext msgids — they go through the same translation cache as
  anything else a person types. `record/4` does that scheduling, which is the
  reason writing an event is a function here instead of a bare
  `Repo.insert!` at each call site.
  """

  import Ecto.Query

  alias Sona.Coordination.{ActivityEvent, CoverageResponse, Notifier, StaffMember}
  alias Sona.Repo

  @doc """
  Records an event against a request and queues its body for translation.
  `actor_id` is `nil` for the events the system raises itself.
  """
  def record(request_id, actor_id, kind, body) do
    Notifier.translate_content([body], request_id)

    Repo.insert!(%ActivityEvent{
      coverage_request_id: request_id,
      actor_id: actor_id,
      kind: kind,
      body: body
    })
  end

  @doc """
  The most recent activity across every request, newest first — the feed
  behind the notifications panel.
  """
  def recent(limit \\ 6) do
    Repo.all(
      from event in ActivityEvent,
        order_by: [desc: event.inserted_at, desc: event.id],
        limit: ^limit,
        preload: [:actor]
    )
  end

  @doc "The sentence describing what a staff member answered."
  def response_body(staff, %CoverageResponse{response_type: "accepted"}),
    do: "#{first_name(staff)} offered to cover the full shift."

  def response_body(staff, %CoverageResponse{response_type: "partial"} = response),
    do: "#{first_name(staff)} offered partial coverage (#{window(response)})."

  def response_body(staff, %CoverageResponse{response_type: "declined"}),
    do: "#{first_name(staff)} declined the coverage request."

  @doc "Event bodies name people the way a colleague would out loud."
  def first_name(%StaffMember{name: name}), do: name |> String.split() |> hd()

  def window(%{cover_start_time: cover_start, cover_end_time: cover_end}),
    do: "#{format_time(cover_start)}–#{format_time(cover_end)}"

  def format_time(%Time{} = time), do: Calendar.strftime(time, "%H:%M")
end
