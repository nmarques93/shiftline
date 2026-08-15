defmodule SonaWeb.HomeLiveTest do
  @moduledoc """
  Tests the LiveView layer: what each persona is allowed to see and do.

  The context tests cover the rules; these cover the surface that exposes
  them — because a control rendered to the wrong person is a bug even when
  the context would reject the event.
  """
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sona.Coordination
  alias Sona.Demo

  setup do
    request = Demo.seed_demo()

    %{
      request: request,
      maya: Demo.supervisor_persona(),
      luis: Demo.frontline_persona()
    }
  end

  describe "landing on Today" do
    test "shows the open coverage request with its real facts", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/?view=today&role=supervisor")

      assert html =~ "One open coverage request"
      assert html =~ "Urgent coverage needed"
      assert html =~ "Lobby front desk"
      # Counts are derived from response rows, not hardcoded.
      assert html =~ "3 of 7 viewed"
    end

    test "greets the frontline persona in their own language", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/?view=today&role=frontline")

      assert html =~ "Buenas tardes, Luis"
      assert html =~ "Un compañero necesita ayuda"
    end
  end

  describe "who can do what" do
    test "only the frontline persona is offered the response actions", %{conn: conn} do
      {:ok, frontline, _html} = live(conn, ~p"/?view=coverage&role=frontline")
      assert has_element?(frontline, "button[phx-value-type='accepted']")

      {:ok, supervisor, _html} = live(conn, ~p"/?view=coverage&role=supervisor")
      refute has_element?(supervisor, "button[phx-value-type='accepted']")
    end

    test "only the supervisor is offered the create-request form", %{conn: conn} do
      {:ok, supervisor, _html} = live(conn, ~p"/?view=coverage&role=supervisor")
      assert has_element?(supervisor, "button[phx-click='toggle_new_request']")

      {:ok, frontline, _html} = live(conn, ~p"/?view=coverage&role=frontline")
      refute has_element?(frontline, "button[phx-click='toggle_new_request']")
    end

    test "Approve is offered for a real offer and withheld from a decline", %{
      conn: conn,
      request: request,
      luis: luis
    } do
      theo = Sona.Repo.get_by!(Sona.Coordination.StaffMember, name: "Theo Martin")
      {:ok, _} = Coordination.respond(request.id, luis.id, "accepted")

      {:ok, live, _html} = live(conn, ~p"/?view=coverage&role=supervisor")

      assert has_element?(live, "button[phx-value-staff-id='#{luis.id}']")
      # Theo declined in the seed data — there is nothing to approve.
      refute has_element?(live, "button[phx-value-staff-id='#{theo.id}']")
    end
  end

  describe "the coverage loop through the UI" do
    test "respond, approve, then acknowledge", %{conn: conn, request: request, luis: luis} do
      {:ok, frontline, _html} = live(conn, ~p"/?view=coverage&role=frontline")

      frontline
      |> element("button[phx-value-type='accepted']")
      |> render_click()

      assert Sona.Repo.get!(Sona.Coordination.CoverageRequest, request.id).status == "claimed"

      {:ok, supervisor, _html} = live(conn, ~p"/?view=coverage&role=supervisor")

      supervisor
      |> element("button[phx-value-staff-id='#{luis.id}']")
      |> render_click()

      approved = Sona.Repo.get!(Sona.Coordination.CoverageRequest, request.id)
      assert approved.status == "approved"
      assert approved.selected_replacement_id == luis.id

      {:ok, replacement, _html} = live(conn, ~p"/?view=coverage&role=frontline")

      replacement
      |> element("button[phx-click='acknowledge']")
      |> render_click()

      assert Sona.Repo.get!(Sona.Coordination.CoverageRequest, request.id).status == "resolved"
    end

    test "an approved partial offer is never shown as full coverage", %{
      conn: conn,
      request: request,
      luis: luis,
      maya: maya
    } do
      {:ok, _} =
        Coordination.respond(request.id, luis.id, "partial",
          cover_start: ~T[18:00:00],
          cover_end: ~T[20:00:00]
        )

      {:ok, _} = Coordination.approve(request.id, luis.id, maya.id)

      {:ok, _live, html} = live(conn, ~p"/?view=coverage&role=supervisor&request=#{request.id}")

      assert html =~ "PARTIALLY COVERED"
      assert html =~ "20:00–22:00"
      refute html =~ "Coverage is confirmed"
    end
  end

  describe "shift tasks on Today" do
    test "the frontline view offers Claim on unowned work and not on other people's", %{
      conn: conn
    } do
      {:ok, live, _html} = live(conn, ~p"/?view=today&role=frontline")

      [unassigned] =
        Sona.Repo.all(Sona.Coordination.ShiftTask) |> Enum.filter(&is_nil(&1.assignee_id))

      assert has_element?(
               live,
               "button[phx-click='claim_task'][phx-value-task-id='#{unassigned.id}']"
             )

      # Exactly one task is claimable; the other two already have owners.
      assert live
             |> element(".task-list")
             |> render()
             |> then(&Regex.scan(~r/claim_task/, &1))
             |> length() == 1
    end

    test "claiming work, starting it and finishing it", %{conn: conn, luis: luis} do
      {:ok, live, _html} = live(conn, ~p"/?view=today&role=frontline")

      [unassigned] =
        Sona.Repo.all(Sona.Coordination.ShiftTask) |> Enum.filter(&is_nil(&1.assignee_id))

      live
      |> element("button[phx-click='claim_task'][phx-value-task-id='#{unassigned.id}']")
      |> render_click()

      claimed = Sona.Repo.get!(Sona.Coordination.ShiftTask, unassigned.id)
      assert claimed.assignee_id == luis.id
      assert claimed.status == "todo"

      live
      |> element("button[phx-value-task-id='#{unassigned.id}'][phx-value-status='in_progress']")
      |> render_click()

      assert Sona.Repo.get!(Sona.Coordination.ShiftTask, unassigned.id).status == "in_progress"

      live
      |> element("button[phx-value-task-id='#{unassigned.id}'][phx-value-status='done']")
      |> render_click()

      assert Sona.Repo.get!(Sona.Coordination.ShiftTask, unassigned.id).status == "done"
    end

    test "a supervisor can add work and hand it to someone", %{conn: conn, luis: luis} do
      {:ok, live, _html} = live(conn, ~p"/?view=today&role=supervisor")

      live |> element("button[phx-click='toggle_new_task']") |> render_click()

      live
      |> form("form[phx-submit='create_task']", %{"title" => "Check the lobby lights"})
      |> render_submit()

      task = Sona.Repo.get_by!(Sona.Coordination.ShiftTask, title: "Check the lobby lights")
      assert is_nil(task.assignee_id)

      live
      |> element("form[phx-change='assign_task']:has(input[value='#{task.id}'])")
      |> render_change(%{"task-id" => to_string(task.id), "assignee_id" => to_string(luis.id)})

      assert Sona.Repo.get!(Sona.Coordination.ShiftTask, task.id).assignee_id == luis.id
    end

    test "frontline staff are never shown the assign or add-work controls", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/?view=today&role=frontline")

      refute has_element?(live, "button[phx-click='toggle_new_task']")
      refute has_element?(live, "form[phx-change='assign_task']")
    end
  end

  describe "settings" do
    test "changing language re-renders the whole surface in it", %{conn: conn} do
      {:ok, live, html} = live(conn, ~p"/?view=profile&role=supervisor")
      assert html =~ "How you use Sona"

      # Saving navigates rather than patches, because gettext strings without
      # an assign reference are static in the LiveView diff.
      assert {:error, {:live_redirect, %{to: to}}} =
               live
               |> form("form[phx-submit='save_settings']", %{
                 "language" => "French",
                 "notify_in_app" => "true"
               })
               |> render_submit()

      {:ok, _live, html} = live(conn, to)
      assert html =~ "Votre utilisation de Sona"
    end

    test "identity fields are not offered as inputs", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/?view=profile&role=frontline")

      assert has_element?(live, "select[name='language']")
      refute has_element?(live, "input[name='role']")
      refute has_element?(live, "input[name='department']")
      refute has_element?(live, "input[name='is_supervisor']")
    end
  end
end
