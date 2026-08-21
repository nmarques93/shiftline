defmodule Shiftline.Translation.Claude do
  @moduledoc """
  Translation provider backed by the Claude Messages API.

  Enabled by setting `ANTHROPIC_API_KEY` (see `config/runtime.exs`); with no
  key the app keeps using `Shiftline.Translation.Local`. There is no official
  Elixir SDK, so this calls the HTTP API directly with Req, which the
  project already depends on.

  Two behaviours of the API are worth knowing when reading this:

    * Thinking is on by default on Claude Opus 5 and shares the `max_tokens`
      budget with the reply, so `max_tokens` leaves headroom above what a
      translation itself needs, and effort is set to `low` — the work is
      mechanical, and low effort is both cheaper and faster.
    * A request declined by the safety classifiers comes back as a *success*
      (HTTP 200) with `stop_reason: "refusal"`, not an error, so the reply is
      only read after checking that field.
  """

  @behaviour Shiftline.Translation

  alias Shiftline.Translation.Prompt

  @endpoint "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"
  @default_model "claude-opus-5"
  @max_tokens 2_048

  @impl true
  def translate(text, locale) do
    with {:ok, api_key} <- fetch_api_key(),
         {:ok, language} <- Prompt.fetch_language(locale) do
      request(text, language, api_key)
    end
  end

  defp request(text, language, api_key) do
    body = %{
      model: config(:model, @default_model),
      max_tokens: @max_tokens,
      output_config: %{effort: "low"},
      system: Prompt.system(language),
      messages: [%{role: "user", content: text}],
      # A policy decline would otherwise just stop; this re-serves the
      # request on Anthropic's recommended fallback model in the same call.
      fallbacks: "default"
    }

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"anthropic-beta", "server-side-fallback-2026-07-01"}
    ]

    case Req.post(@endpoint, json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: response}} -> read_reply(response)
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Reads the translation out of a decoded Messages API response. The reply is
  a list of content blocks and the translation is the text ones.

  Public so it can be tested against recorded payloads without a network
  call or an API key.
  """
  def read_reply(%{"stop_reason" => "refusal"}), do: {:error, :refused}

  def read_reply(%{"content" => blocks}) when is_list(blocks) do
    blocks
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join(& &1["text"])
    |> String.trim()
    |> case do
      "" -> {:error, :empty_reply}
      translated -> {:ok, translated}
    end
  end

  def read_reply(body), do: {:error, {:unexpected_response, body}}

  defp config(key, default) do
    Application.get_env(:shiftline, Shiftline.Translation, [])[key] || default
  end

  defp fetch_api_key do
    case config(:api_key, nil) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _missing -> {:error, :missing_api_key}
    end
  end
end
