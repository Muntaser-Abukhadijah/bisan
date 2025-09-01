class AddUniqueIndexOnArticlesSourceUrl < ActiveRecord::Migration[8.0]
  def change
    add_index :articles, :source_url, unique: true
  end
end
