defmodule Sona.Repo.Migrations.CreateContentTranslations do
  use Ecto.Migration

  def change do
    # Translations of user-entered content are computed once per (text, locale)
    # and cached here, so rendering never waits on a translation provider and
    # the same sentence is never paid for twice.
    create table(:content_translations) do
      add :source_hash, :string, null: false
      add :locale, :string, null: false
      add :source_text, :text, null: false
      add :translated_text, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:content_translations, [:source_hash, :locale])
  end
end
