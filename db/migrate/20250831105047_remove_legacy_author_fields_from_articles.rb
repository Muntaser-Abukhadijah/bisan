# db/migrate/xxxxxx_remove_legacy_author_fields_from_articles.rb
class RemoveLegacyAuthorFieldsFromArticles < ActiveRecord::Migration[8.0]
  def change
    remove_column :articles, :author, :string
    remove_column :articles, :author_image, :string
    # keep :tags for now
  end
end
