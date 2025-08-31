# db/migrate/20250831102831_add_author_ref_to_articles.rb
class AddAuthorRefToArticles < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:articles, :author_id)
      add_reference :articles, :author, null: true, foreign_key: true, index: true
    end
  end
end
