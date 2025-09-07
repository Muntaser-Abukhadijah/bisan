# frozen_string_literal: true

require "digest/sha1"

module Ingestion
  class Normalizer
    # Keep HTML but safe-list some tags/attrs.
    ALLOWED_TAGS  = %w[p br a strong em b i u ul ol li h1 h2 h3 h4 blockquote img figure figcaption code pre span hr].freeze
    ALLOWED_ATTRS = %w[href src alt title target rel].freeze

    Result = Struct.new(
      :ok?, :error, :data, keyword_init: true
    )

    def initialize(source_id:)
      @source_id = source_id.to_s
      @sanitizer = safe_sanitizer
    end

    def call(input)
      # Required fields
      url   = str_or_nil(input[:url])
      title = str_or_nil(input[:title])

      return err("missing_url")  if url.nil? || url.empty?
      return err("missing_title") if title.nil? || title.empty?

      # Author: allow nil → importer will substitute a sentinel author
      author_name = str_or_nil(input[:author])
      author_avatar_url = str_or_nil(input[:author_avatar]) # <- NEW


      # Body preference: HTML > text
      raw_html = str_or_nil(input[:body_html])
      raw_text = str_or_nil(input[:body_text])
      body_html = raw_html || (raw_text ? h_to_p(raw_text) : nil)
      body_html = sanitize_html(body_html) if body_html

      # Dates
      published_at_iso = str_or_nil(input[:published_at])
      publish_date = begin
        published_at_iso ? Time.iso8601(published_at_iso).to_date : nil
      rescue ArgumentError
        nil
      end

      # Categories → single category (keep it simple for now)
      categories = (input[:categories].is_a?(Array) ? input[:categories].compact : [])
      category   = categories.first

      # Other fields
      article_image = str_or_nil(input[:article_image])
      excerpt       = str_or_nil(input[:excerpt])

      # Hash to detect changes
      content_hash = Digest::SHA1.hexdigest([
        title, author_name, publish_date&.iso8601, body_html, article_image, excerpt, category
      ].join("\u0001"))

      ok(
        {
          source_id: @source_id,
          source_url: url,
          title: title,
          author_name: author_name,
          author_avatar_url: author_avatar_url,   # <- NEW
          publish_date: publish_date,
          body_html: body_html,
          article_image: article_image,
          excerpt: excerpt,
          category: category,
          content_hash: content_hash
        }
      )
    end

    private

    def str_or_nil(v)
      v.is_a?(String) ? v.strip : nil
    end

    def h_to_p(text)
      # very small helper to keep formatting when no HTML provided
      CGI.escapeHTML(text).split(/\n{2,}/).map { |para| "<p>#{para}</p>" }.join
    end

    def safe_sanitizer
      # Rails ships with rails-html-sanitizer
      Rails::Html::SafeListSanitizer.new
    end

    def sanitize_html(html)
      @sanitizer.sanitize(html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRS)
    end

    def ok(data)  = Result.new(ok?: true,  error: nil,  data:)
    def err(code) = Result.new(ok?: false, error: code, data: nil)
  end
end
