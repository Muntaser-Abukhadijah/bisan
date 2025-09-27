# db/migrate/20250927_import_prep.rb
class ImportPrep < ActiveRecord::Migration[8.0]
  def change
    # 1) Ensure authors.name is unique (dedupe by author name)
    unless index_exists?(:authors, :name, name: "index_authors_on_name")
      add_index :authors, :name, unique: true, name: "index_authors_on_name"
    end

    # 2) Keep ONE clear unique index for articles.source_url
    # Drop the extra one if present.
    if index_exists?(:articles, :source_url, name: "idx_articles_source_url_unique")
      remove_index :articles, name: "idx_articles_source_url_unique"
    end

    # Make sure the canonical one exists and is unique.
    unless index_exists?(:articles, :source_url, name: "index_articles_on_source_url")
      add_index :articles, :source_url, unique: true, name: "index_articles_on_source_url"
    end
  end
end
