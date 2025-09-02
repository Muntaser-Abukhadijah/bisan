class AuthorsController < ApplicationController
  include Pagy::Backend

  def index
    @q = params[:q].to_s.strip

    hits =
      if @q.present?
        Author.pagy_search(@q, hits_per_page: 12, sort: [ "name:asc" ])
      else
        Author.pagy_search("*", hits_per_page: 12, sort: [ "name:asc" ])
      end

    @pagy, @authors =
      pagy_meilisearch(hits)

  rescue MeiliSearch::ApiError, Faraday::Error => e
    # Fallback, falls Meilisearch mal nicht erreichbar ist (optional)
    scope = Author.order(:name)
    scope = scope.where("name ILIKE :q OR COALESCE(bio, '') ILIKE :q", q: "%#{@q}%") if @q.present?
    @pagy, @authors = pagy(scope, items: 12)
    Rails.logger.warn("Fallback in Authors#index: #{e.class} #{e.message}")
  end

  def show
    @author =
      Author.find(params[:id])
    @pagy, @articles =
      pagy(
        author.articles
              .order(Arel.sql("COALESCE(publish_date, created_at) DESC"))
      )
  end

  private

  def author
    @author
  end
end
