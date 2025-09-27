class Article < ApplicationRecord
  include Meilisearch::Rails
  extend Pagy::Meilisearch

  belongs_to :author, counter_cache: true

  validates :source_url, presence: true, uniqueness: true

  meilisearch do
    attribute :title, :excerpt, :body
    searchable_attributes [ :title, :excerpt, :body ]
    attributes_to_highlight [ "*" ]
  end
end
