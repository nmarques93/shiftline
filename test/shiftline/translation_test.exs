defmodule Shiftline.TranslationTest do
  use Shiftline.DataCase, async: true

  alias Shiftline.Coordination
  alias Shiftline.Demo
  alias Shiftline.Translation
  alias Shiftline.Translation.ContentTranslation

  describe "translate_now/1 and lookup/2" do
    test "translates arbitrary text into every supported locale and caches it" do
      text = "Noor called in sick for the morning shift."

      assert Translation.translate_now(text) == length(Translation.locales())

      for locale <- Translation.locales() do
        assert Translation.lookup(text, locale) == "[stub] #{text}"
      end
    end

    test "is idempotent — a second pass calls the provider for nothing" do
      text = "The ice machine on floor 3 is leaking."

      assert Translation.translate_now(text) == length(Translation.locales())
      assert Translation.translate_now(text) == 0
      assert Repo.aggregate(ContentTranslation, :count) == length(Translation.locales())
    end

    test "hashes on trimmed text, so whitespace variants share one translation" do
      Translation.translate_now("Front desk needs cover.")

      assert Translation.lookup("  Front desk needs cover.  ", "es") ==
               "[stub] Front desk needs cover."
    end

    test "a provider failure stores nothing and leaves lookup empty" do
      text = "This one is untranslatable."

      assert Translation.translate_now(text) == 0
      assert Translation.lookup(text, "es") == nil
    end

    test "blank and oversized text never reaches the provider" do
      assert Translation.translate_now("   ") == 0
      assert Translation.translate_now(String.duplicate("a", 2_001)) == 0
      assert Repo.aggregate(ContentTranslation, :count) == 0
    end
  end

  describe "the Local (offline) provider" do
    test "translates strings present in the catalogs and refuses the rest" do
      assert {:ok, "Cobertura"} = Translation.Local.translate("Coverage", "es")
      assert {:ok, "Remplacements"} = Translation.Local.translate("Coverage", "fr")
      assert {:ok, "Coverage"} = Translation.Local.translate("Coverage", "en")

      assert {:error, :no_translation} =
               Translation.Local.translate("Noor called in sick.", "es")
    end
  end

  describe "content written through the workflow" do
    setup do
      request = Demo.seed_demo()
      %{request: request, maya: Demo.supervisor_persona()}
    end

    test "a newly created request has its reason and handoff note translated", %{maya: maya} do
      attrs = %{
        "absent_name" => "Noor Haddad",
        "department" => "Front Office",
        "role" => "Front Desk Agent",
        "shift_date" => Date.to_iso8601(Date.utc_today()),
        "start_time" => "08:00",
        "end_time" => "12:00",
        "location" => "Lobby front desk",
        "urgency" => "High",
        "reason" => "Noor is out sick for the morning.",
        "handoff_note" => "Brief the incoming agent on VIP arrivals."
      }

      {:ok, request} = Coordination.create_coverage_request(maya.id, attrs)

      # In production this fan-out is backgrounded so the writer never waits
      # on a provider; tests run the same path inline (see config/test.exs).
      assert Translation.lookup(request.reason, "es") == "[stub] #{request.reason}"
      assert Translation.lookup(request.handoff_note, "fr") == "[stub] #{request.handoff_note}"
    end
  end
end
