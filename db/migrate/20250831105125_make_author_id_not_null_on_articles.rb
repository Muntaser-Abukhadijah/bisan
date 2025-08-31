# db/migrate/xxxxxx_make_author_id_not_null_on_articles.rb
class MakeAuthorIdNotNullOnArticles < ActiveRecord::Migration[8.0]
  def change
    change_column_null :articles, :author_id, false
  end
end
