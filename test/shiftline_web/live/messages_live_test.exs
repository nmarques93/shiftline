defmodule ShiftlineWeb.MessagesLiveTest do
  @moduledoc """
  The Messages tab from the outside: what each persona is offered, and what
  the page says after they use it.
  """
  use ShiftlineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Shiftline.Coordination.{Messages, StaffMember}
  alias Shiftline.Demo
  alias Shiftline.Repo

  setup do
    Demo.seed_demo()

    %{maya: Demo.supervisor_persona(), luis: Demo.frontline_persona()}
  end

  describe "the conversation list" do
    test "leads with the department channel and the pinned announcement", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/?view=messages&role=supervisor")

      assert html =~ "PINNED FOR YOUR TEAM"
      assert html =~ "night auditor"
      assert html =~ "Front Office"
      assert html =~ "Maya Chen"
    end

    test "shows the frontline persona their unread count", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/?view=today&role=frontline")

      assert has_element?(live, ".nav-count")
      assert render(live) =~ "URGENTE"
    end

    test "opening a conversation clears its unread count", %{conn: conn, luis: luis} do
      before = Messages.unread_count(luis)

      {:ok, _live, _html} = live(conn, ~p"/?view=messages&role=frontline&conversation=department")

      assert Messages.unread_count(luis) < before
    end

    test "an unknown conversation id falls back to the list rather than crashing",
         %{conn: conn} do
      {:ok, _live, html} =
        live(conn, ~p"/?view=messages&role=frontline&conversation=direct:99999")

      # And in Spanish, because that is the frontline persona's language.
      assert html =~ "Tus canales y tu equipo"
    end
  end

  describe "sending" do
    test "a message posted to the channel reaches the other persona", %{conn: conn} do
      {:ok, supervisor, _html} =
        live(conn, ~p"/?view=messages&role=supervisor&conversation=department")

      supervisor
      |> form("#message-form", %{"body" => "Lobby carpet is being cleaned at 19:00."})
      |> render_submit()

      {:ok, _frontline, html} =
        live(conn, ~p"/?view=messages&role=frontline&conversation=department")

      assert html =~ "Lobby carpet is being cleaned at 19:00."
    end

    test "the frontline persona can start a direct conversation with their supervisor",
         %{conn: conn, maya: maya} do
      {:ok, live, _html} =
        live(conn, ~p"/?view=messages&role=frontline&conversation=direct:#{maya.id}")

      html =
        live
        |> form("#message-form", %{"body" => "I need a hand at the desk."})
        |> render_submit()

      assert html =~ "I need a hand at the desk."
    end

    test "only a supervisor is offered the pin control", %{conn: conn} do
      {:ok, supervisor, _} =
        live(conn, ~p"/?view=messages&role=supervisor&conversation=department")

      assert has_element?(supervisor, "input[name='pinned']")

      {:ok, frontline, _} = live(conn, ~p"/?view=messages&role=frontline&conversation=department")
      refute has_element?(frontline, "input[name='pinned']")
    end

    # Pinning is a supervisor affordance, but urgency is not: a frontline
    # blocker is the thing the brief most wants to travel.
    test "anyone can mark a message urgent", %{conn: conn} do
      {:ok, frontline, _} = live(conn, ~p"/?view=messages&role=frontline&conversation=department")
      assert has_element?(frontline, "input[name='urgent']")

      html =
        frontline
        |> form("#message-form", %{"body" => "Card terminal is down.", "urgent" => "true"})
        |> render_submit()

      assert html =~ "Card terminal is down."
      assert html =~ "URGENTE"
    end

    test "a direct conversation is not offered a pin", %{conn: conn, maya: maya} do
      {:ok, live, _} =
        live(conn, ~p"/?view=messages&role=frontline&conversation=direct:#{maya.id}")

      refute has_element?(live, "input[name='pinned']")
    end
  end

  describe "read and acknowledgement" do
    test "the sender sees how far their message got", %{conn: conn} do
      {:ok, live, _} = live(conn, ~p"/?view=messages&role=supervisor&conversation=department")

      html = live |> form("#message-form", %{"body" => "Handover at 17:45."}) |> render_submit()

      assert html =~ "Seen by 0 of 7"
    end

    test "acknowledging an urgent announcement records it for the supervisor to see",
         %{conn: conn, luis: luis} do
      {:ok, frontline, _} = live(conn, ~p"/?view=messages&role=frontline")

      html =
        frontline
        |> element("button[phx-click='acknowledge_message']")
        |> render_click()

      assert html =~ "Has confirmado este mensaje"

      pinned = luis |> Messages.pinned_for() |> hd()
      assert Enum.any?(pinned.reads, &(&1.staff_member_id == luis.id and &1.acknowledged_at))
    end
  end

  describe "language" do
    test "the Spanish persona reads a colleague's English message translated",
         %{conn: conn, maya: maya} do
      # The stub provider prefixes what it translated, which is what separates
      # "translated" from "fell back to the original" — the distinction the
      # whole feature rests on.
      {:ok, _} =
        Messages.send_message(
          maya.id,
          Messages.department_conversation(),
          "Check the arrivals list."
        )

      {:ok, live, html} = live(conn, ~p"/?view=messages&role=frontline&conversation=department")

      assert html =~ "[stub] Check the arrivals list."
      assert html =~ "Traducido automáticamente"

      # And can always get back to what Maya actually wrote, without losing
      # the conversation they are reading.
      assert {:error, {:live_redirect, %{to: to}}} = render_click(live, "toggle_original", %{})

      # The conversation is part of that URL, so switching to the original does
      # not drop the reader back into the conversation list.
      assert to =~ "conversation=department"

      {:ok, _live, original} = live(conn, to)

      assert original =~ "Check the arrivals list."
      refute original =~ "[stub] Check the arrivals list."
    end

    test "the tab is titled in the reader's own language", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/?view=messages&role=frontline")

      assert html =~ "Mensajes"
    end
  end

  describe "scoping" do
    test "a Housekeeping channel message never appears in Front Office", %{conn: conn} do
      rosa = Repo.get_by!(StaffMember, name: "Rosa Iglesias")

      {:ok, _} =
        Messages.send_message(
          rosa.id,
          Messages.department_conversation(),
          "Linen delivery is late."
        )

      {:ok, _live, html} = live(conn, ~p"/?view=messages&role=frontline&conversation=department")

      refute html =~ "Linen delivery is late."
    end
  end
end
