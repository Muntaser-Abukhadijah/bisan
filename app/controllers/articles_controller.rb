class ArticlesController < ApplicationController
  include Pagy::Backend

  def index
    @q = params[:q].to_s.strip

    hits = if @q.present?
      Article.pagy_search(@q, hits_per_page: 12, sort: [ "created_at:desc" ])
    else
      # show everything when no query; "*" means match all
      Article.pagy_search("*", hits_per_page: 12, sort: [ "created_at:desc" ])
    end

    @pagy, @articles = pagy_meilisearch(hits)
  end

  def show
  end
end
