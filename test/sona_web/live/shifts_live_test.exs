defmodule SonaWeb.ShiftsLiveTest do
  @moduledoc """
  The Shifts tab. As with the rest of the LiveView tests, the point is that the
  surface never offers an action the context would refuse.
  """
  use SonaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sona.Coordination.Shifts
  alias Sona.Demo
  alias Sona.Repo

  setup do
    Demo.seed_demo()

    %{
      maya: Demo.supervisor_persona(),
      luis: Demo.frontline_persona(),
      mei: Repo.get_by!(Sona.Coordination.StaffMember, name: "Mei Tanaka")
    }
  end

  describe "reading the roster" do
    test "shows the department's shifts with who is on them", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/?view=shifts&role=supervisor")

      assert html =~ "Front Desk Agent"
      assert html =~ "Night Auditor"
      assert html =~ "14:00–22:00"
      assert html =~ "Luis Garcia"
    end

    test "marks a shift that runs past midnight", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/?view=shifts&role=supervisor")

      assert html =~ "22:00–06:00"
      assert html =~ "Overnight"
    end

    test "the roster is scoped to the reader's own department", %{conn: conn, mei: mei} do
      {:ok, _live, html} = live(conn, ~p"/?view=shifts&role=supervisor")
      assert html =~ "Front Desk Agent"

      # Housekeeping's own shift exists but never reaches a Front Office view.
      refute html =~ "Floors 1-4"
      assert Enum.any?(Shifts.list(mei), &(&1.location == "Floors 1-4"))
    end
  end

  describe "who can change the roster" do
    test "a supervisor is offered the controls", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/?view=shifts&role=supervisor")

      assert has_element?(live, "button[phx-click='toggle_new_shift']")
      assert has_element?(live, "button[phx-click='delete_shift']")
      assert has_element?(live, "form[phx-change='assign_shift']")
    end

    test "frontline staff are offered none of them", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/?view=shifts&role=frontline")

      refute has_element?(live, "button[phx-click='toggle_new_shift']")
      refute has_element?(live, "button[phx-click='delete_shift']")
      refute has_element?(live, "form[phx-change='assign_shift']")
    end
  end

  describe "creating and editing" do
    test "a supervisor adds a shift", %{conn: conn, maya: maya} do
      {:ok, live, _html} = live(conn, ~p"/?view=shifts&role=supervisor")

      live |> element("button[phx-click='toggle_new_shift']") |> render_click()

      html =
        live
        |> form("#shift-form", %{
          "role" => "Concierge",
          "date" => Date.to_iso8601(Date.utc_today()),
          "start_time" => "09:00",
          "end_time" => "17:00",
          "location" => "Front hall"
        })
        |> render_submit()

      assert html =~ "Concierge"
      assert Enum.any?(Shifts.list(maya), &(&1.role == "Concierge"))
    end

    test "an end at or before the start rolls the shift into the next day", %{
      conn: conn,
      maya: maya
    } do
      {:ok, live, _html} = live(conn, ~p"/?view=shifts&role=supervisor")

      live |> element("button[phx-click='toggle_new_shift']") |> render_click()

      live
      |> form("#shift-form", %{
        "role" => "Porter",
        "date" => Date.to_iso8601(Date.utc_today()),
        "start_time" => "23:00",
        "end_time" => "07:00",
        "location" => "Lobby"
      })
      |> render_submit()

      shift = Enum.find(Shifts.list(maya), &(&1.role == "Porter"))

      assert DateTime.to_date(shift.ends_at) == Date.add(Date.utc_today(), 1)
      assert Sona.Coordination.Shift.duration_minutes(shift) == 480
    end

    test "an invalid window is reported rather than saved", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/?view=shifts&role=supervisor")

      live |> element("button[phx-click='toggle_new_shift']") |> render_click()

      html =
        live
        |> form("#shift-form", %{
          "role" => "Porter",
          "date" => "not-a-date",
          "start_time" => "09:00",
          "end_time" => "17:00",
          "location" => ""
        })
        |> render_submit()

      assert html =~ "Enter a valid date and times."
    end

    test "editing loads the shift into the same form", %{conn: conn, maya: maya} do
      [shift | _] = Shifts.list(maya)

      {:ok, live, _html} = live(conn, ~p"/?view=shifts&role=supervisor")

      html =
        live
        |> element("button[phx-click='edit_shift'][phx-value-shift-id='#{shift.id}']")
        |> render_click()

      assert html =~ "EDIT SHIFT"
      assert html =~ ~s(name="shift_id")
    end
  end

  describe "assignment" do
    test "adding and removing someone updates the shift", %{conn: conn, maya: maya, luis: luis} do
      [shift | _] = Shifts.list(maya)

      {:ok, live, _html} = live(conn, ~p"/?view=shifts&role=supervisor")

      live
      |> element("button[phx-click='unassign_shift'][phx-value-staff-id='#{luis.id}']")
      |> render_click()

      refute Enum.any?(
               Shifts.get!(shift.id).assignments,
               &(&1.staff_member_id == luis.id)
             )

      live
      |> form("#assign-shift-#{shift.id}", %{"staff_id" => to_string(luis.id)})
      |> render_change()

      assert Enum.any?(
               Shifts.get!(shift.id).assignments,
               &(&1.staff_member_id == luis.id)
             )
    end
  end

  describe "localization" do
    test "the roster renders in the reader's language", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/?view=shifts&role=frontline")

      # Luis reads Spanish; this is the check that new UI copy was actually
      # extracted and translated rather than left to fall back to English.
      assert html =~ "Turnos"
      assert html =~ "Cuadrante"
      refute html =~ "No shifts on the roster yet."
    end
  end
end
