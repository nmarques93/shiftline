defmodule Sona.Translation.DeepSeek do
  @moduledoc """
  Translation provider backed by the DeepSeek API.

  Enabled by setting `DEEPSEEK_API_KEY` (see `config/runtime.exs`); with no
  key the app keeps using `Sona.Translation.Local`. The API is
  OpenAI-compatible, so this is a plain chat completion over Req: the shared
  system prompt from `Sona.Translation.Prompt`, the text as the user turn,
  and the reply read from `choices[0].message.content`.

  Two choices worth explaining:

    * The default model is `deepseek-v4-flash` rather than `-pro`. Translating
      one operational sentence is mechanical work, and this path runs once per
      locale per piece of user-entered text, so it is the cost that scales
      with usage.
    * `thinking` is not sent at all, leaving the API default. The docs show
      how to enable it but do not pin the value that disables it, and sending
      a guessed enum would fail the request outright. It is exposed in config
      for anyone who wants to tune it against the current API.

  Both are configurable:

      config :sona, Sona.Translation,
        adapter: Sona.Translation.DeepSeek,
        api_key: "...",
        model: "deepseek-v4-pro",
        thinking: %{type: "enabled"}
  """

  @behaviour Sona.Translation

  alias Sona.Translation.Prompt

  @default_base_url "https://api.deepseek.com"
  @default_model "deepseek-v4-flash"

  @impl true
  def translate(text, locale) do
    with {:ok, api_key} <- fetch_api_key(),
         {:ok, language} <- Prompt.fetch_language(locale) do
      request(text, language, api_key)
    end
  end

  defp request(text, language, api_key) do
    body =
      %{
        model: config(:model, @default_model),
        messages: [
          %{role: "system", content: Prompt.system(language)},
          %{role: "user", content: text}
        ],
        stream: false
      }
      |> maybe_put(:thinking, config(:thinking, nil))

    headers = [{"authorization", "Bearer " <> api_key}]
    url = config(:base_url, @default_base_url) <> "/chat/completions"

    case Req.post(url, json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: response}} -> read_reply(response)
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Reads the translation out of a decoded DeepSeek response.

  Public so it can be tested against recorded payloads without a network
  call or an API key.
  """
  def read_reply(%{"choices" => [%{"finish_reason" => "content_filter"} | _rest]}),
    do: {:error, :refused}

  def read_reply(%{"choices" => [%{"message" => %{"content" => content}} | _rest]})
      when is_binary(content) do
    case String.trim(content) do
      "" -> {:error, :empty_reply}
      translated -> {:ok, translated}
    end
  end

  def read_reply(%{"error" => error}), do: {:error, {:api_error, error}}
  def read_reply(body), do: {:error, {:unexpected_response, body}}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp config(key, default) do
    Application.get_env(:sona, Sona.Translation, [])[key] || default
  end

  defp fetch_api_key do
    case config(:api_key, nil) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _missing -> {:error, :missing_api_key}
    end
  end
end
