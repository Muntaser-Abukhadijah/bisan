# app/models/author.rb
class Author < ApplicationRecord
    include Meilisearch::Rails
  extend Pagy::Meilisearch
  has_many :articles, dependent: :restrict_with_error

  meilisearch do
    # Send these fields to the index
    attribute :name, :bio, :social_links, :created_at, :updated_at
    attribute :articles_count   # optional if you add a counter cache

    # What’s searchable
    searchable_attributes [ :name, :bio ]

    # Facets / filters (optional; add as needed)
    filterable_attributes [ :articles_count ]

    # Sortable fields
    sortable_attributes [ :created_at, :updated_at, :articles_count, :name ]

    attributes_to_highlight [ "*" ]
    attributes_to_crop [ :bio ]
    crop_length 30
  end
end
