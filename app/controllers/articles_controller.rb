class ArticlesController < ApplicationController
  include Pagy::Backend

  def index
    @q = params[:q].to_s.strip
    query = @q.presence || ""
    hits  = Article.pagy_search(query, highlight_pre_tag: "<mark>", highlight_post_tag: "</mark>")
    @pagy, @articles = pagy_meilisearch(hits)
  end

  def show
    @article = Article.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to articles_path, alert: I18n.t("articles.not_found", default: "Article not found.")
  end
end
