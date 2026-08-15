defmodule Sona.Translation do
  @moduledoc """
  Translation of *user-entered* content — the request reason a supervisor
  types, a response note, a question.

  UI copy is handled by Gettext at compile time; this module handles text
  that did not exist when the app was compiled. It is a cache in front of a
  pluggable provider:

    * on write, `translate_later/1` fans the text out to every supported
      locale in the background and stores the results;
    * on render, `lookup/2` is a single indexed read — no network call ever
      happens while a page is being rendered.

  The provider is configured, so the demo runs offline and deterministically
  while a real deployment translates anything:

      config :sona, Sona.Translation, adapter: Sona.Translation.Local
      config :sona, Sona.Translation, adapter: Sona.Translation.Claude

  See `Sona.Translation.Local` and `Sona.Translation.Claude`.
  """

  import Ecto.Query

  alias Sona.Repo
  alias Sona.Translation.ContentTranslation

  @locales ~w(en es fr)
  # Long free text is out of scope for the demo and would be the expensive
  # case to send to a provider unbounded.
  @max_length 2_000

  @doc """
  Translates `text` into `locale`, returning `{:ok, translated}` or
  `{:error, reason}`. Implementations must be free of side effects beyond
  the provider call — caching is handled here.
  """
  @callback translate(text :: String.t(), locale :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  def locales, do: @locales

  def adapter do
    :sona
    |> Application.get_env(Sona.Translation, [])
    |> Keyword.get(:adapter, Sona.Translation.Local)
  end

  @doc """
  Returns the cached translation of `text` for `locale`, or `nil`.

  Never calls a provider: rendering must not depend on the network.
  """
  def lookup(text, locale) when is_binary(text) do
    case Repo.get_by(ContentTranslation, source_hash: hash(text), locale: locale) do
      nil -> nil
      %ContentTranslation{translated_text: translated} -> translated
    end
  end

  def lookup(_text, _locale), do: nil

  @doc """
  Translates `text` into every supported locale in the background, storing
  each result. Returns immediately.

  `on_complete` runs once the fan-out finishes, so callers can broadcast and
  let connected clients re-render with the translated text.
  """
  def translate_later(text, on_complete \\ fn -> :ok end)

  def translate_later(text, on_complete) when is_binary(text) do
    cond do
      not translatable?(text) ->
        :ok

      # Tests run the fan-out inline so assertions are deterministic and the
      # work stays inside the Ecto sandbox's connection ownership.
      not async?() ->
        translate_now(text)
        on_complete.()

      true ->
        Task.Supervisor.start_child(Sona.TaskSupervisor, fn ->
          translate_now(text)
          on_complete.()
        end)
    end

    :ok
  end

  def translate_later(_text, _on_complete), do: :ok

  @doc """
  Synchronously translates `text` into every supported locale it is missing,
  returning the number of translations stored. Used by tests and by
  `translate_later/2`.
  """
  def translate_now(text) when is_binary(text) do
    if translatable?(text) do
      missing = @locales -- cached_locales(text)
      Enum.count(missing, &(store(text, &1) == :ok))
    else
      0
    end
  end

  def translate_now(_text), do: 0

  defp store(text, locale) do
    case adapter().translate(text, locale) do
      {:ok, translated} when is_binary(translated) ->
        %ContentTranslation{}
        |> ContentTranslation.changeset(%{
          source_hash: hash(text),
          locale: locale,
          source_text: text,
          translated_text: String.trim(translated)
        })
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:source_hash, :locale])

        :ok

      {:error, _reason} ->
        # A provider failure is not fatal: the UI falls back to the original
        # text with a "shown in its original language" note.
        :error
    end
  end

  defp cached_locales(text) do
    Repo.all(
      from translation in ContentTranslation,
        where: translation.source_hash == ^hash(text),
        select: translation.locale
    )
  end

  defp translatable?(text), do: String.trim(text) != "" and String.length(text) <= @max_length

  defp async?, do: Application.get_env(:sona, Sona.Translation, [])[:async] != false

  defp hash(text) do
    :crypto.hash(:sha256, String.trim(text)) |> Base.encode16(case: :lower)
  end
end
