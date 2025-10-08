class Author < ApplicationRecord
  include Meilisearch::Rails
  extend Pagy::Meilisearch
  has_many :articles, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 255 }

  meilisearch do
    attribute :name, :bio
    searchable_attributes [ :name, :bio ]
    attributes_to_highlight [ "*" ]
    pagination max_total_hits: 10000
  end
end
