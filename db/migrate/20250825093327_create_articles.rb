class CreateArticles < ActiveRecord::Migration[8.0]
  def change
    create_table :articles do |t|
      t.string :title
      t.string :image
      t.text :excerpt
      t.string :author
      t.string :category
      t.date :publish_date

      t.timestamps
    end
  end
end
