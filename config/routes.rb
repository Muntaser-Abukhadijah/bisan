Rails.application.routes.draw do
  scope "(:locale)", locale: /#{I18n.available_locales.join("|")}/ do
    get "up" => "rails/health#show", as: :rails_health_check
     root "articles#index"

    resources :articles
    resources :authors, only: [ :index, :show ]
  end
end
