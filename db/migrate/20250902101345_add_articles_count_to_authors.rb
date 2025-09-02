class AddArticlesCountToAuthors < ActiveRecord::Migration[8.0]
  def change
    add_column :authors, :articles_count, :integer, null: false, default: 0
    add_index :authors, :articles_count
  end
end
