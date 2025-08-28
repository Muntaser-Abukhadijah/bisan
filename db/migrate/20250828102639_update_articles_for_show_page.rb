class UpdateArticlesForShowPage < ActiveRecord::Migration[8.0]
  def change
    # rename old column if it exists
    rename_column :articles, :image, :article_image if column_exists?(:articles, :image)

    add_column :articles, :body,         :text   unless column_exists?(:articles, :body)
    add_column :articles, :source_url,   :string unless column_exists?(:articles, :source_url)
    add_column :articles, :author_image, :string unless column_exists?(:articles, :author_image)
    add_column :articles, :tags,         :string unless column_exists?(:articles, :tags)
  end
end
