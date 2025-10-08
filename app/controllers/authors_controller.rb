class AuthorsController < ApplicationController
  include Pagy::Backend

  def index
    @q = params[:q].to_s.strip
    query = @q.presence || ""
    hits = Author.pagy_search(query, highlight_pre_tag: "<mark>", highlight_post_tag: "</mark>")
    @pagy, @authors = pagy_meilisearch(hits)
  end

  def show
    @author = Author.find(params[:id])
    @pagy, @articles = pagy(@author.articles.order(Arel.sql("COALESCE(publish_date, created_at) DESC")))
  end
end
