class ArticlesController < ApplicationController
  def index
    @pagy, @articles = pagy(Article.all)
  end

  def show
  end
end
