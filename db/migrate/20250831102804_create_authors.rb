# db/migrate/20250831102804_create_authors.rb
class CreateAuthors < ActiveRecord::Migration[8.0]
  def change
    create_table :authors, if_not_exists: true do |t|
      t.string :name
      t.text   :bio
      t.string :avatar_url
      t.json   :social_links
      t.timestamps
    end

    # Add columns if the table exists but a column is missing (safety)
    add_column :authors, :name,        :string unless column_exists?(:authors, :name)
    add_column :authors, :bio,         :text   unless column_exists?(:authors, :bio)
    add_column :authors, :avatar_url,  :string unless column_exists?(:authors, :avatar_url)
    add_column :authors, :social_links, :json   unless column_exists?(:authors, :social_links)
  end
end
