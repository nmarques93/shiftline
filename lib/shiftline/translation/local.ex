defmodule Shiftline.Translation.Local do
  @moduledoc """
  Offline translation provider backed by the Gettext catalogs.

  This is the default so the demo runs with no API key, no network, and
  identical output every time. It can only translate strings that already
  exist in `priv/gettext` — anything a user types for the first time returns
  `{:error, :no_translation}`, and the UI shows the original text marked as
  untranslated rather than inventing one.

  For genuinely dynamic translation, configure `Shiftline.Translation.Claude`.
  """

  @behaviour Shiftline.Translation

  @impl true
  def translate(text, locale) do
    translated = Gettext.with_locale(ShiftlineWeb.Gettext, locale, fn -> gettext_lookup(text) end)

    cond do
      locale == "en" -> {:ok, text}
      translated != text -> {:ok, translated}
      true -> {:error, :no_translation}
    end
  end

  defp gettext_lookup(text), do: Gettext.gettext(ShiftlineWeb.Gettext, text)
end
