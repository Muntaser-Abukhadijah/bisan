# app/models/author.rb
class Author < ApplicationRecord
  has_many :articles, dependent: :restrict_with_error
end
