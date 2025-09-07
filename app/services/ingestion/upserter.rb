# frozen_string_literal: true

module Ingestion
  class Upserter
    Outcome = Struct.new(:status, :article_id, :author_id, :message, keyword_init: true)
    # status: :inserted | :updated | :skipped | :error

    UNKNOWN_AUTHOR = "Unknown"

    def call(normalized)
      # Ensure author
      author = find_or_create_author!(normalized[:author_name], normalized[:author_avatar_url])

      # Upsert article by natural key (source_url)
      art = Article.find_or_initialize_by(source_url: normalized[:source_url])

      # If unchanged, skip
      if art.persisted? && art.content_hash.present? && art.content_hash == normalized[:content_hash]
        return Outcome.new(status: :skipped, article_id: art.id, author_id: author.id, message: "unchanged")
      end

      art.title         = normalized[:title]
      art.article_image = normalized[:article_image]
      art.excerpt       = normalized[:excerpt]
      art.category      = normalized[:category]
      art.publish_date  = normalized[:publish_date]
      art.body          = normalized[:body_html] || "" # body is text field
      art.source_id     = normalized[:source_id]
      art.content_hash  = normalized[:content_hash]
      art.ingested_at   = Time.current
      art.author        = author

      art.save!
      Outcome.new(status: (art.previous_changes.key?("id") ? :inserted : :updated), article_id: art.id, author_id: author.id)
    rescue ActiveRecord::RecordInvalid => e
      Outcome.new(status: :error, message: e.message)
    rescue => e
      Outcome.new(status: :error, message: e.message)
    end

    private

    def find_or_create_author!(name, avatar_url)
      n = (name && !name.strip.empty?) ? name.strip : UNKNOWN_AUTHOR
      author = Author.find_or_create_by!(name: n)
      if avatar_url && !avatar_url.strip.empty? && author.avatar_url != avatar_url
        author.update!(avatar_url: avatar_url)
      end
      author
    end
  end
end
