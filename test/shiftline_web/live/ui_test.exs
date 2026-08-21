defmodule ShiftlineWeb.HomeLive.UITest do
  use ExUnit.Case, async: true

  alias ShiftlineWeb.HomeLive.UI

  describe "time_choices/3" do
    test "offers every step between the two times, inclusive" do
      assert UI.time_choices(~T[18:00:00], ~T[20:00:00]) ==
               ["18:00", "18:30", "19:00", "19:30", "20:00"]
    end

    test "covers a whole day without running past midnight" do
      # Time.add/3 wraps at midnight, so a loop that compares against the end
      # time never terminates here. This is the regression guard for that.
      choices = UI.day_time_choices()

      assert length(choices) == 48
      assert List.first(choices) == "00:00"
      assert List.last(choices) == "23:30"
    end

    test "an inverted window offers nothing rather than looping" do
      assert UI.time_choices(~T[22:00:00], ~T[18:00:00]) == []
    end

    test "honours a custom step" do
      assert UI.time_choices(~T[09:00:00], ~T[10:00:00], 15) ==
               ["09:00", "09:15", "09:30", "09:45", "10:00"]
    end
  end

  describe "half_windows/1" do
    test "splits a shift into two halves on a clean boundary" do
      request = %{start_time: ~T[18:00:00], end_time: ~T[22:00:00]}

      assert UI.half_windows(request) == [
               {"First half", "18:00", "20:00"},
               {"Second half", "20:00", "22:00"}
             ]
    end

    test "offers no shortcut for a shift too short to halve usefully" do
      assert UI.half_windows(%{start_time: ~T[18:00:00], end_time: ~T[19:00:00]}) == []
    end
  end
end
