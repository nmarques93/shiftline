defmodule Sona.Translation.Prompt do
  @moduledoc """
  The instruction every provider-backed adapter sends, and the locale-to-
  language mapping behind it.

  It lives here rather than in each adapter so that swapping providers is a
  config change that does not also quietly change what the model was asked to
  do. If two providers disagree about a translation, the prompt is not the
  variable — which is the only way the comparison is worth anything.
  """

  @language_names %{"en" => "English", "es" => "Spanish", "fr" => "French"}

  @doc "The language name for a supported locale, or an error for anything else."
  def fetch_language(locale) do
    case Map.fetch(@language_names, locale) do
      {:ok, language} -> {:ok, language}
      :error -> {:error, {:unsupported_locale, locale}}
    end
  end

  @doc """
  The system prompt. It asks for the translation alone, because the caller
  stores the reply verbatim — a model that adds "Sure, here you go:" would
  put that sentence on a hotel notice board.
  """
  def system(language) do
    """
    You translate short operational messages for hotel staff.

    Translate the message into #{language}. Reply with the translation and \
    nothing else — no preamble, no quotation marks, no explanation. If the \
    message is already in #{language}, reply with it unchanged. Keep names, \
    times, dates and room or area labels exactly as written, and keep the \
    tone plain and direct, the way a colleague would speak on shift.
    """
  end
end
