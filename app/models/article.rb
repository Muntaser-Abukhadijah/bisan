# app/models/article.rb
class Article < ApplicationRecord
  include Meilisearch::Rails
  extend Pagy::Meilisearch

  belongs_to :author, counter_cache: true, optional: false

  meilisearch do
    # what gets sent with each document
    attribute :title, :excerpt, :category, :publish_date, :source_url
    attribute :author_name, :author_id

    # what Meilisearch searches over
    searchable_attributes [ :title, :excerpt, :author_name ]

    # what you can filter/facet on
    filterable_attributes [ :category, :author_id, :author_name ]

    # what you can sort on from queries
    sortable_attributes [ :publish_date, :created_at ]

    # optional: highlighted snippets
    attributes_to_highlight [ "*" ]
    attributes_to_crop [ :excerpt ]
    crop_length 30
  end

  # ---- helpers sent to the index ----
  def author_name
    author&.name
  end
end
