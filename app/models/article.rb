# app/models/article.rb
class Article < ApplicationRecord
  include Meilisearch::Rails
  extend Pagy::Meilisearch

  # Keep validations pragmatic: allow legacy rows without source_url,
  # but enforce uniqueness when present (mirrors the partial index).
  validates :source_url, uniqueness: true, allow_nil: true

  # Basic sanity; tune as you like
  validates :title, length: { maximum: 500 }, allow_nil: true
  validates :category, length: { maximum: 200 }, allow_nil: true


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

  # Optional: tiny helper the importer will call before save
  def set_ingestion_fields!(source_id:, content_hash:)
    self.source_id   = source_id
    self.ingested_at = Time.current
    self.content_hash = content_hash
  end
end
