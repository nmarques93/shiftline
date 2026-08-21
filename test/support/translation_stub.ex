defmodule Shiftline.Translation.Stub do
  @moduledoc """
  Deterministic translation provider for tests.

  Mirrors the real providers' contract — including the failure path — without
  a network call: text containing "untranslatable" returns an error so the
  fallback behaviour can be tested.
  """

  @behaviour Shiftline.Translation

  @impl true
  def translate(text, _locale) when is_binary(text) do
    if String.contains?(text, "untranslatable") do
      {:error, :no_translation}
    else
      {:ok, "[stub] #{text}"}
    end
  end
end
