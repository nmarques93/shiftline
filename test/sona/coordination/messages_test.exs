defmodule Sona.Coordination.MessagesTest do
  use Sona.DataCase, async: true

  alias Sona.Coordination.{Message, Messages, StaffMember}
  alias Sona.Demo

  setup do
    Demo.seed_demo()

    %{
      maya: Demo.supervisor_persona(),
      luis: Demo.frontline_persona(),
      priya: Repo.get_by!(StaffMember, name: "Priya Shah"),
      rosa: Repo.get_by!(StaffMember, name: "Rosa Iglesias"),
      mei: Repo.get_by!(StaffMember, name: "Mei Tanaka")
    }
  end

  describe "posting to a department channel" do
    test "a message goes to the sender's own department", %{luis: luis} do
      {:ok, message} =
        Messages.send_message(luis.id, Messages.department_conversation(), "Lobby is quiet.")

      assert message.department == "Front Office"
      assert is_nil(message.recipient_id)
    end

    test "the channel a message lands in comes from the sender, not the caller", %{rosa: rosa} do
      # Housekeeping's supervisor writes to "department" and reaches
      # Housekeeping, whatever any other department is called.
      {:ok, message} =
        Messages.send_message(rosa.id, Messages.department_conversation(), "Linen is late.")

      assert message.department == "Housekeeping"
    end

    test "another department's channel is not readable", %{luis: luis, rosa: rosa} do
      {:ok, _} =
        Messages.send_message(rosa.id, Messages.department_conversation(), "Linen is late.")

      {:ok, thread} = Messages.thread(luis, Messages.department_conversation())

      refute Enum.any?(thread, &(&1.body == "Linen is late."))
    end

    test "an empty message is refused", %{luis: luis} do
      assert {:error, :empty_message} =
               Messages.send_message(luis.id, Messages.department_conversation(), "   ")
    end
  end

  describe "direct messages" do
    test "reach only the two people named", %{maya: maya, luis: luis, priya: priya} do
      {:ok, _} =
        Messages.send_message(maya.id, Messages.direct_conversation(luis), "Are you in early?")

      {:ok, luis_thread} = Messages.thread(luis, Messages.direct_conversation(maya))
      {:ok, priya_thread} = Messages.thread(priya, Messages.direct_conversation(maya))

      assert Enum.any?(luis_thread, &(&1.body == "Are you in early?"))
      refute Enum.any?(priya_thread, &(&1.body == "Are you in early?"))
    end

    test "cross a department boundary, because a supervisor's questions do", %{
      maya: maya,
      mei: mei
    } do
      assert {:ok, message} =
               Messages.send_message(maya.id, Messages.direct_conversation(mei), "Is 402 ready?")

      assert message.recipient_id == mei.id
    end

    test "an unknown conversation id is refused rather than guessed at", %{luis: luis} do
      assert {:error, :unknown_conversation} = Messages.send_message(luis.id, "direct:0", "Hello")
      assert {:error, :unknown_conversation} = Messages.send_message(luis.id, "everyone", "Hello")
      assert {:error, :unknown_conversation} = Messages.thread(luis, "direct:abc")
    end

    test "a person cannot open a direct conversation with themselves", %{luis: luis} do
      assert {:error, :unknown_conversation} =
               Messages.thread(luis, Messages.direct_conversation(luis))
    end
  end

  describe "pinning" do
    test "only a supervisor can pin an announcement", %{luis: luis} do
      assert {:error, :not_supervisor} =
               Messages.send_message(luis.id, Messages.department_conversation(), "Read this",
                 pinned: true
               )
    end

    test "a direct message cannot be pinned", %{maya: maya, luis: luis} do
      assert {:error, :cannot_pin_direct} =
               Messages.send_message(maya.id, Messages.direct_conversation(luis), "Read this",
                 pinned: true
               )
    end

    test "pinned announcements are scoped to the reader's department", %{luis: luis, mei: mei} do
      assert Enum.any?(Messages.pinned_for(luis), & &1.pinned)
      assert Messages.pinned_for(mei) == []
    end
  end

  describe "urgency" do
    test "anyone can raise an urgent message, because a blocker is not a rank", %{luis: luis} do
      {:ok, message} =
        Messages.send_message(
          luis.id,
          Messages.department_conversation(),
          "Card terminal is down.",
          urgent: true
        )

      assert message.urgent
    end
  end

  describe "read and acknowledgement" do
    test "opening a conversation marks what other people wrote as seen", %{luis: luis} do
      before = Messages.unread_count(luis)
      assert before > 0

      {:ok, marked} = Messages.mark_read(luis, Messages.department_conversation())

      assert marked > 0
      assert Messages.unread_count(luis) < before
    end

    test "your own messages were never unread", %{luis: luis} do
      {:ok, _} = Messages.mark_read(luis, Messages.department_conversation())
      {:ok, _} = Messages.mark_read(luis, Messages.direct_conversation(Demo.supervisor_persona()))

      {:ok, _} = Messages.send_message(luis.id, Messages.department_conversation(), "On my way.")

      assert Messages.unread_count(luis) == 0
    end

    test "re-opening a read conversation changes nothing", %{luis: luis} do
      {:ok, _} = Messages.mark_read(luis, Messages.department_conversation())

      assert {:ok, 0} = Messages.mark_read(luis, Messages.department_conversation())
    end

    test "acknowledging an urgent message records who promised what", %{luis: luis} do
      pinned = Messages.pinned_for(luis) |> hd()

      {:ok, read} = Messages.acknowledge(pinned.id, luis.id)

      assert read.acknowledged_at
      assert read.viewed_at
    end

    test "an ordinary message asks for no acknowledgement", %{maya: maya, luis: luis} do
      {:ok, message} =
        Messages.send_message(maya.id, Messages.department_conversation(), "Coffee is on.")

      assert {:error, :not_urgent} = Messages.acknowledge(message.id, luis.id)
    end

    test "you do not acknowledge your own announcement", %{maya: maya, luis: luis} do
      pinned = Messages.pinned_for(luis) |> hd()

      assert pinned.sender_id == maya.id
      assert {:error, :not_addressed} = Messages.acknowledge(pinned.id, maya.id)
    end

    test "someone the message never reached cannot acknowledge it", %{mei: mei, luis: luis} do
      pinned = Messages.pinned_for(luis) |> hd()

      assert {:error, :not_addressed} = Messages.acknowledge(pinned.id, mei.id)
    end
  end

  describe "the conversation list" do
    test "leads with the department channel, then everyone you could talk to", %{luis: luis} do
      [channel | directs] = Messages.conversations(luis)

      assert channel.kind == :department
      assert channel.title == "Front Office"
      assert Enum.all?(directs, &(&1.kind == :direct))
      refute Enum.any?(directs, &(&1.partner.id == luis.id))
    end

    test "colleagues with no history are still listed, so a 1-to-1 needs no setup", %{
      luis: luis,
      priya: priya
    } do
      assert Enum.any?(Messages.conversations(luis), &(&1.partner && &1.partner.id == priya.id))
    end

    test "someone outside your department appears once you have talked", %{luis: luis, mei: mei} do
      refute Enum.any?(Messages.conversations(luis), &(&1.partner && &1.partner.id == mei.id))

      {:ok, _} =
        Messages.send_message(mei.id, Messages.direct_conversation(luis), "Room 402 is ready.")

      assert Enum.any?(Messages.conversations(luis), &(&1.partner && &1.partner.id == mei.id))
    end

    test "conversations with something in them come before empty ones", %{luis: luis} do
      [_channel | directs] = Messages.conversations(luis)

      assert hd(directs).partner.name == "Maya Chen"
    end

    test "an unread urgent message is flagged on the conversation it is in", %{luis: luis} do
      [channel | _] = Messages.conversations(luis)

      assert channel.urgent?
      assert channel.unread > 0
    end
  end

  describe "audience" do
    test "the channel reaches the department minus the reader", %{luis: luis} do
      front_office =
        Repo.aggregate(from(s in StaffMember, where: s.department == "Front Office"), :count)

      [channel | _directs] = Messages.conversations(luis)

      assert channel.audience_size == front_office - 1
    end

    test "a direct conversation reaches one person", %{luis: luis} do
      [_channel | directs] = Messages.conversations(luis)

      assert Enum.all?(directs, &(&1.audience_size == 1))
    end
  end

  describe "the database is the last guard" do
    test "a row addressed to both a channel and a person is rejected", %{maya: maya, luis: luis} do
      changeset =
        Message.changeset(%Message{}, %{
          "body" => "Both",
          "sender_id" => maya.id,
          "department" => "Front Office",
          "recipient_id" => luis.id
        })

      refute changeset.valid?
    end
  end
end
