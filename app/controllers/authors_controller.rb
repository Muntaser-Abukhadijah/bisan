class AuthorsController < ApplicationController
  include Pagy::Backend

  def index
    @pagy, @authors =
      pagy(Author.order(:name))
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
