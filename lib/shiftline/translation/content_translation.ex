defmodule Shiftline.Translation.ContentTranslation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "content_translations" do
    field :source_hash, :string
    field :locale, :string
    field :source_text, :string
    field :translated_text, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(translation, attrs) do
    translation
    |> cast(attrs, [:source_hash, :locale, :source_text, :translated_text])
    |> validate_required([:source_hash, :locale, :source_text, :translated_text])
    |> unique_constraint([:source_hash, :locale])
  end
end
