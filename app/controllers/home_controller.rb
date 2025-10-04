class HomeController < ApplicationController
  def index
    @recent_articles = Article.order(publish_date: :desc).limit(6)
  end
end
