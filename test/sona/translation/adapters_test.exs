defmodule Sona.Translation.AdaptersTest do
  @moduledoc """
  Provider adapters, tested against recorded payload shapes.

  No network and no API key: everything worth getting wrong in an adapter —
  reading the reply, spotting a refusal, refusing to call out without
  credentials — is reachable without spending money to check it.
  """
  use ExUnit.Case, async: true

  alias Sona.Translation.{Claude, DeepSeek, Prompt}

  describe "Prompt" do
    test "maps supported locales to language names" do
      assert Prompt.fetch_language("es") == {:ok, "Spanish"}
      assert Prompt.fetch_language("fr") == {:ok, "French"}
    end

    test "rejects a locale no provider was asked to handle" do
      assert Prompt.fetch_language("de") == {:error, {:unsupported_locale, "de"}}
    end

    test "names the target language and asks for nothing but the translation" do
      prompt = Prompt.system("Spanish")

      assert prompt =~ "Spanish"
      assert prompt =~ "nothing else"
    end
  end

  describe "DeepSeek.read_reply/1" do
    test "takes the message content" do
      assert DeepSeek.read_reply(reply("Turno de tarde")) == {:ok, "Turno de tarde"}
    end

    test "trims the surrounding whitespace a model tends to add" do
      assert DeepSeek.read_reply(reply("\n  Turno de tarde \n")) == {:ok, "Turno de tarde"}
    end

    test "treats a filtered completion as a refusal, not a translation" do
      body = %{"choices" => [%{"finish_reason" => "content_filter", "message" => %{}}]}

      assert DeepSeek.read_reply(body) == {:error, :refused}
    end

    test "reports an empty completion rather than caching an empty string" do
      assert DeepSeek.read_reply(reply("   ")) == {:error, :empty_reply}
    end

    test "surfaces an API error body" do
      body = %{"error" => %{"message" => "Insufficient Balance"}}

      assert {:error, {:api_error, %{"message" => "Insufficient Balance"}}} =
               DeepSeek.read_reply(body)
    end

    test "does not pretend to understand an unrecognised shape" do
      assert {:error, {:unexpected_response, %{}}} = DeepSeek.read_reply(%{})
    end

    defp reply(content) do
      %{"choices" => [%{"finish_reason" => "stop", "message" => %{"content" => content}}]}
    end
  end

  describe "Claude.read_reply/1" do
    test "joins the text blocks and ignores the rest" do
      body = %{
        "stop_reason" => "end_turn",
        "content" => [
          %{"type" => "thinking", "thinking" => "considering"},
          %{"type" => "text", "text" => "Turno de tarde"}
        ]
      }

      assert Claude.read_reply(body) == {:ok, "Turno de tarde"}
    end

    test "treats a refusal as an error even though the call succeeded" do
      body = %{"stop_reason" => "refusal", "content" => [%{"type" => "text", "text" => "no"}]}

      assert Claude.read_reply(body) == {:error, :refused}
    end

    test "reports a reply with no text blocks" do
      body = %{"content" => [%{"type" => "thinking", "thinking" => "..."}]}

      assert Claude.read_reply(body) == {:error, :empty_reply}
    end
  end

  describe "without credentials" do
    test "adapters fail closed instead of calling a provider" do
      # The test config sets no api_key, so reaching the network here would
      # be a bug: a missing key must be an error, never an anonymous request.
      assert DeepSeek.translate("Evening shift", "es") == {:error, :missing_api_key}
      assert Claude.translate("Evening shift", "es") == {:error, :missing_api_key}
    end
  end
end
