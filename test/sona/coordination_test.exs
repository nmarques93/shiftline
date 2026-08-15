defmodule Sona.CoordinationTest do
  use Sona.DataCase, async: true

  alias Sona.Coordination
  alias Sona.Coordination.{CoverageRequest, CoverageResponse, StaffMember}

  setup do
    request = Coordination.seed_demo()

    %{
      request: request,
      maya: Coordination.supervisor_persona(),
      luis: Coordination.frontline_persona()
    }
  end

  describe "seed and reads" do
    test "active_request returns the open seeded request", %{request: request} do
      assert Coordination.active_request().id == request.id
      assert Coordination.active_request().status == "open"
    end

    test "active_requests orders by shift date before start time", %{request: request} do
      tomorrow_early =
        Repo.insert!(%CoverageRequest{
          absent_name: "Jordan Lee",
          department: "Front Office",
          role: "Front Desk Agent",
          shift_date: Date.add(Date.utc_today(), 1),
          start_time: ~T[02:00:00],
          end_time: ~T[06:00:00],
          location: "Lobby front desk",
          urgency: "Urgent",
          reason: "Night audit cover.",
          status: "open"
        })

      # Today's 18:00 shift outranks tomorrow's 02:00 shift.
      assert Enum.map(Coordination.active_requests(), & &1.id) == [
               request.id,
               tomorrow_early.id
             ]
    end

    test "eligible_staff excludes supervisors", %{request: request, maya: maya} do
      staff = Coordination.eligible_staff(request)

      assert length(staff) == 7
      refute Enum.any?(staff, &(&1.id == maya.id))
    end
  end

  describe "respond/4" do
    test "an offer moves an open request to claimed", %{request: request, luis: luis} do
      assert {:ok, %CoverageResponse{response_type: "accepted"} = response} =
               Coordination.respond(request.id, luis.id, "accepted")

      assert response.viewed_at
      assert Repo.get!(CoverageRequest, request.id).status == "claimed"
    end

    test "declining does not change the status", %{request: request, luis: luis} do
      assert {:ok, _} = Coordination.respond(request.id, luis.id, "declined")
      assert Repo.get!(CoverageRequest, request.id).status == "open"
    end

    test "a second response updates the existing row", %{request: request, luis: luis} do
      {:ok, first} = Coordination.respond(request.id, luis.id, "declined")
      {:ok, second} = Coordination.respond(request.id, luis.id, "accepted")

      assert first.id == second.id
      assert second.response_type == "accepted"
    end

    test "a partial offer requires a window inside the shift", %{request: request, luis: luis} do
      assert {:error, :missing_window} = Coordination.respond(request.id, luis.id, "partial")

      assert {:error, :invalid_window} =
               Coordination.respond(request.id, luis.id, "partial",
                 cover_start: ~T[17:00:00],
                 cover_end: ~T[20:00:00]
               )

      assert {:error, :invalid_window} =
               Coordination.respond(request.id, luis.id, "partial",
                 cover_start: ~T[21:00:00],
                 cover_end: ~T[19:00:00]
               )

      assert {:ok, response} =
               Coordination.respond(request.id, luis.id, "partial",
                 cover_start: ~T[19:00:00],
                 cover_end: ~T[22:00:00]
               )

      assert response.cover_start_time == ~T[19:00:00]
      assert Repo.get!(CoverageRequest, request.id).status == "claimed"
    end

    test "records an activity event naming the actual responder", %{
      request: request,
      luis: luis
    } do
      {:ok, _} = Coordination.respond(request.id, luis.id, "accepted")

      details = Coordination.request_with_details(request.id)
      assert Enum.any?(details.activity_events, &(&1.body =~ "Luis offered to cover"))
    end

    test "rejects staff who are not eligible for the request", %{request: request, maya: maya} do
      # Supervisors are not eligible to cover their own request.
      assert {:error, :not_eligible} = Coordination.respond(request.id, maya.id, "accepted")

      outsider =
        Repo.insert!(%StaffMember{
          name: "Iris Beck",
          role: "Housekeeper",
          department: "Housekeeping",
          language: "English"
        })

      assert {:error, :not_eligible} = Coordination.respond(request.id, outsider.id, "accepted")
    end

    test "rejects responses once the request is closed", %{
      request: request,
      luis: luis,
      maya: maya
    } do
      {:ok, _} = Coordination.respond(request.id, luis.id, "accepted")
      {:ok, _} = Coordination.approve(request.id, luis.id, maya.id)

      assert {:error, :request_closed} = Coordination.respond(request.id, luis.id, "declined")
    end
  end

  describe "create_coverage_request/2" do
    @valid_request %{
      "absent_name" => "Noor Haddad",
      "department" => "Front Office",
      "role" => "Front Desk Agent",
      "shift_date" => Date.to_iso8601(Date.utc_today()),
      "start_time" => "08:00",
      "end_time" => "12:00",
      "location" => "Lobby front desk",
      "urgency" => "High",
      "reason" => "Noor called in sick for the morning shift."
    }

    test "a supervisor can open a request, which becomes the live incident", %{maya: maya} do
      assert {:ok, request} = Coordination.create_coverage_request(maya.id, @valid_request)

      assert request.status == "open"
      assert request.absent_name == "Noor Haddad"
      # HTML time inputs submit "HH:MM"; the context normalises them.
      assert request.start_time == ~T[08:00:00]
      assert Enum.any?(Coordination.active_requests(), &(&1.id == request.id))

      details = Coordination.request_with_details(request.id)
      assert Enum.any?(details.activity_events, &(&1.body =~ "Maya created a high coverage"))
    end

    test "eligible staff can immediately respond to it", %{maya: maya, luis: luis} do
      {:ok, request} = Coordination.create_coverage_request(maya.id, @valid_request)

      assert {:ok, _response} = Coordination.respond(request.id, luis.id, "accepted")
      assert {:ok, approved} = Coordination.approve(request.id, luis.id, maya.id)
      assert approved.selected_replacement_id == luis.id
    end

    test "frontline staff cannot open one", %{luis: luis} do
      assert {:error, :not_supervisor} =
               Coordination.create_coverage_request(luis.id, @valid_request)
    end

    test "rejects a shift window that ends before it starts", %{maya: maya} do
      attrs = %{@valid_request | "start_time" => "22:00", "end_time" => "18:00"}

      assert {:error, changeset} = Coordination.create_coverage_request(maya.id, attrs)
      assert %{end_time: ["must be after the start time"]} = errors_on(changeset)
    end

    test "rejects missing required details", %{maya: maya} do
      attrs = Map.drop(@valid_request, ["reason", "location"])

      assert {:error, changeset} = Coordination.create_coverage_request(maya.id, attrs)
      errors = errors_on(changeset)
      assert errors[:reason]
      assert errors[:location]
    end
  end

  describe "update_staff_settings/2" do
    test "updates the settings a person controls themselves", %{luis: luis} do
      assert {:ok, updated} =
               Coordination.update_staff_settings(luis.id, %{
                 language: "French",
                 notify_in_app: false
               })

      assert updated.language == "French"
      assert updated.notify_in_app == false
    end

    test "rejects an unsupported language", %{luis: luis} do
      assert {:error, changeset} =
               Coordination.update_staff_settings(luis.id, %{language: "Klingon"})

      assert %{language: ["is invalid"]} = errors_on(changeset)
      assert Repo.get!(StaffMember, luis.id).language == "Spanish"
    end

    test "cannot change role, department or supervisor status", %{luis: luis} do
      # A crafted submission must not be able to promote the sender: the
      # settings changeset does not cast these fields at all.
      assert {:ok, _updated} =
               Coordination.update_staff_settings(luis.id, %{
                 language: "English",
                 is_supervisor: true,
                 role: "Front Office Supervisor",
                 department: "Housekeeping"
               })

      unchanged = Repo.get!(StaffMember, luis.id)
      assert unchanged.is_supervisor == false
      assert unchanged.role == "Front Desk Agent"
      assert unchanged.department == "Front Office"
    end

    test "a promoted-by-form staff member still cannot approve", %{
      request: request,
      luis: luis
    } do
      priya = Repo.get_by!(StaffMember, name: "Priya Shah")
      {:ok, _} = Coordination.respond(request.id, luis.id, "accepted")
      {:ok, _} = Coordination.update_staff_settings(priya.id, %{is_supervisor: true})

      assert {:error, :not_supervisor} = Coordination.approve(request.id, luis.id, priya.id)
    end
  end

  describe "ask_question/3" do
    test "never overwrites an existing offer, so the person stays approvable", %{
      request: request,
      luis: luis,
      maya: maya
    } do
      {:ok, offer} = Coordination.respond(request.id, luis.id, "accepted")
      {:ok, _event} = Coordination.ask_question(request.id, luis.id, "Which desk?")

      unchanged = Repo.get!(CoverageResponse, offer.id)
      assert unchanged.response_type == "accepted"

      # The whole point: asking a question must not strand the request.
      assert {:ok, approved} = Coordination.approve(request.id, luis.id, maya.id)
      assert approved.selected_replacement_id == luis.id
    end

    test "records the question and marks the asker as having viewed", %{
      request: request,
      luis: luis
    } do
      assert {:ok, event} = Coordination.ask_question(request.id, luis.id, "Which desk?")
      assert event.kind == "question"
      assert event.body =~ "Luis asked: Which desk?"

      response =
        Repo.get_by!(CoverageResponse, coverage_request_id: request.id, staff_member_id: luis.id)

      assert response.response_type == "pending"
      assert response.viewed_at
    end

    test "rejects blank questions, closed requests, and ineligible staff", %{
      request: request,
      luis: luis,
      maya: maya
    } do
      assert {:error, :empty_question} = Coordination.ask_question(request.id, luis.id, "   ")
      assert {:error, :not_eligible} = Coordination.ask_question(request.id, maya.id, "Hello?")

      {:ok, _} = Coordination.respond(request.id, luis.id, "accepted")
      {:ok, _} = Coordination.approve(request.id, luis.id, maya.id)
      assert {:error, :request_closed} = Coordination.ask_question(request.id, luis.id, "Hi?")
    end
  end

  describe "approve/3" do
    test "requires an actual offer from the chosen staff member", %{
      request: request,
      luis: luis,
      maya: maya
    } do
      assert {:error, :no_offer} = Coordination.approve(request.id, luis.id, maya.id)

      {:ok, _} = Coordination.respond(request.id, luis.id, "declined")
      assert {:error, :no_offer} = Coordination.approve(request.id, luis.id, maya.id)
    end

    test "sets the replacement and records the approver", %{
      request: request,
      luis: luis,
      maya: maya
    } do
      {:ok, _} = Coordination.respond(request.id, luis.id, "accepted")
      assert {:ok, approved} = Coordination.approve(request.id, luis.id, maya.id)

      assert approved.status == "approved"
      assert approved.selected_replacement_id == luis.id
      assert Enum.any?(approved.activity_events, &(&1.body =~ "Maya approved Luis Garcia"))
    end

    test "requires the approver to be a supervisor", %{request: request, luis: luis} do
      {:ok, _} = Coordination.respond(request.id, luis.id, "accepted")

      priya = Repo.get_by!(StaffMember, name: "Priya Shah")
      assert {:error, :not_supervisor} = Coordination.approve(request.id, luis.id, priya.id)
    end

    test "rejects approving a closed request", %{request: request, luis: luis, maya: maya} do
      {:ok, _} = Coordination.respond(request.id, luis.id, "accepted")
      {:ok, _} = Coordination.approve(request.id, luis.id, maya.id)

      assert {:error, :request_closed} = Coordination.approve(request.id, luis.id, maya.id)
    end
  end

  describe "acknowledge_handoff/2" do
    test "only an approved request can be acknowledged", %{request: request, luis: luis} do
      assert {:error, :not_approved} = Coordination.acknowledge_handoff(request.id, luis.id)
    end

    test "only the approved replacement can acknowledge", %{
      request: request,
      luis: luis,
      maya: maya
    } do
      # Priya's seeded partial offer gets approved; Luis must not be able
      # to acknowledge the handoff on her behalf.
      priya = Repo.get_by!(StaffMember, name: "Priya Shah")
      {:ok, _} = Coordination.approve(request.id, priya.id, maya.id)

      assert {:error, :not_replacement} = Coordination.acknowledge_handoff(request.id, luis.id)
      assert {:ok, resolved} = Coordination.acknowledge_handoff(request.id, priya.id)
      assert resolved.status == "resolved"
    end

    test "resolves the request and stamps the acknowledgement", %{
      request: request,
      luis: luis,
      maya: maya
    } do
      {:ok, _} = Coordination.respond(request.id, luis.id, "accepted")
      {:ok, _} = Coordination.approve(request.id, luis.id, maya.id)

      assert {:ok, resolved} = Coordination.acknowledge_handoff(request.id, luis.id)
      assert resolved.status == "resolved"
      assert resolved.handoff_acknowledged_at

      response = Enum.find(resolved.responses, &(&1.staff_member_id == luis.id))
      assert response.acknowledged_at

      # Full coverage leaves nothing behind: no follow-up request is opened.
      assert Coordination.active_request().id == request.id
    end

    test "acknowledging a partial offer opens a follow-up request for the gap", %{
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
      {:ok, resolved} = Coordination.acknowledge_handoff(request.id, luis.id)

      assert resolved.status == "resolved"

      followup = Coordination.active_request()
      assert followup.id != request.id
      assert followup.status == "open"
      assert followup.start_time == ~T[20:00:00]
      assert followup.end_time == ~T[22:00:00]
      assert followup.department == request.department

      # The gap request is a live incident: eligible staff can respond to it.
      assert {:ok, _} = Coordination.respond(followup.id, luis.id, "accepted")
    end

    test "a mid-shift partial opens follow-ups for both gaps", %{
      request: request,
      luis: luis,
      maya: maya
    } do
      {:ok, _} =
        Coordination.respond(request.id, luis.id, "partial",
          cover_start: ~T[19:00:00],
          cover_end: ~T[21:00:00]
        )

      {:ok, _} = Coordination.approve(request.id, luis.id, maya.id)
      {:ok, _} = Coordination.acknowledge_handoff(request.id, luis.id)

      followups = Coordination.active_requests()

      assert [{~T[18:00:00], ~T[19:00:00]}, {~T[21:00:00], ~T[22:00:00]}] ==
               Enum.map(followups, &{&1.start_time, &1.end_time})

      assert Enum.all?(followups, &(&1.status == "open"))
    end
  end

  describe "ensure_demo_data/0" do
    test "reseeds when the request is missing without duplicating staff" do
      Repo.delete_all(Sona.Coordination.ActivityEvent)
      Repo.delete_all(Sona.Coordination.CoverageResponse)
      Repo.delete_all(CoverageRequest)

      assert :ok = Coordination.ensure_demo_data()
      assert Coordination.active_request()
      assert Repo.aggregate(StaffMember, :count) == 12
    end

    test "is a no-op when the demo data is present", %{request: request} do
      assert :ok = Coordination.ensure_demo_data()
      assert Coordination.active_request().id == request.id
    end

    test "reseeds when a demo persona is missing", %{luis: luis} do
      Repo.delete!(luis)

      assert :ok = Coordination.ensure_demo_data()
      assert Coordination.frontline_persona()
      assert Repo.aggregate(StaffMember, :count) == 12
    end
  end

  describe "mark_viewed/2" do
    test "rejects staff who are not eligible", %{request: request, maya: maya} do
      assert {:error, :not_eligible} = Coordination.mark_viewed(request.id, maya.id)
    end

    test "creates a pending response so viewed and responded stay distinct", %{
      request: request,
      luis: luis
    } do
      assert {:ok, %CoverageResponse{response_type: "pending"} = viewed} =
               Coordination.mark_viewed(request.id, luis.id)

      assert viewed.viewed_at
      assert Repo.get!(CoverageRequest, request.id).status == "open"
    end

    test "is idempotent and upgraded by a real response", %{request: request, luis: luis} do
      {:ok, viewed} = Coordination.mark_viewed(request.id, luis.id)
      {:ok, again} = Coordination.mark_viewed(request.id, luis.id)
      assert viewed.id == again.id

      {:ok, response} =
        Coordination.respond(request.id, luis.id, "partial",
          cover_start: ~T[18:00:00],
          cover_end: ~T[20:00:00]
        )

      assert response.id == viewed.id
      assert response.response_type == "partial"
    end
  end

  describe "coverage_gaps/2" do
    test "empty while nobody is approved and for full-shift offers", %{
      request: request,
      luis: luis,
      maya: maya
    } do
      details = Coordination.request_with_details(request.id)
      assert Coordination.coverage_gaps(details, details.responses) == []

      {:ok, _} = Coordination.respond(request.id, luis.id, "accepted")
      {:ok, approved} = Coordination.approve(request.id, luis.id, maya.id)
      assert Coordination.coverage_gaps(approved, approved.responses) == []
    end

    test "reports the uncovered remainder of an approved partial offer", %{
      request: request,
      luis: luis,
      maya: maya
    } do
      {:ok, _} =
        Coordination.respond(request.id, luis.id, "partial",
          cover_start: ~T[18:00:00],
          cover_end: ~T[20:00:00]
        )

      {:ok, approved} = Coordination.approve(request.id, luis.id, maya.id)

      assert Coordination.coverage_gaps(approved, approved.responses) ==
               [{~T[20:00:00], ~T[22:00:00]}]
    end

    test "reports gaps on both sides of a mid-shift window", %{
      request: request,
      luis: luis,
      maya: maya
    } do
      {:ok, _} =
        Coordination.respond(request.id, luis.id, "partial",
          cover_start: ~T[19:00:00],
          cover_end: ~T[21:00:00]
        )

      {:ok, approved} = Coordination.approve(request.id, luis.id, maya.id)

      assert Coordination.coverage_gaps(approved, approved.responses) ==
               [{~T[18:00:00], ~T[19:00:00]}, {~T[21:00:00], ~T[22:00:00]}]
    end
  end

  describe "pub/sub" do
    test "workflow writes broadcast an update", %{request: request, luis: luis} do
      Coordination.subscribe()

      {:ok, _} = Coordination.respond(request.id, luis.id, "accepted")

      request_id = request.id
      assert_receive {:coordination_updated, ^request_id}
    end
  end
end
