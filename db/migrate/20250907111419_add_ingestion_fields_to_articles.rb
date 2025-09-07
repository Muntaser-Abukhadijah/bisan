class AddIngestionFieldsToArticles < ActiveRecord::Migration[7.1]
  def change
    # New ingestion/provenance columns
    add_column :articles, :source_id,   :string    # e.g., "metras"
    add_column :articles, :ingested_at, :datetime # last time importer touched this row
    add_column :articles, :content_hash, :string   # hash of normalized content to detect changes

    # You already have source_url:string — enforce idempotency at DB level.
    # Make it unique when present (partial index keeps legacy NULLs valid).
    # Note: partial indexes require SQLite >= 3.8.0 (OK for modern rails/sqlite) and Postgres (always OK).
    add_index  :articles, :source_url, unique: true, where: "source_url IS NOT NULL", name: "idx_articles_source_url_unique"

    # Helpful for change checks or quick lookups
    add_index  :articles, :content_hash
    add_index  :articles, :source_id
  end
end
