class Article < ApplicationRecord
  include MeiliSearch::Rails
  extend Pagy::Meilisearch

  meilisearch do
    attribute :title, :excerpt, :category
    searchable_attributes [ :title, :excerpt ]
    filterable_attributes [ :category ]
    sortable_attributes [ :created_at ]

    # optional: enables highlighted snippets we can render if present
    attributes_to_highlight [ "*" ]
    attributes_to_crop [ :excerpt ]
    crop_length 30
  end
end
