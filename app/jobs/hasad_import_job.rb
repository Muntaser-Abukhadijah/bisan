# app/jobs/hasad_import_job.rb
require "json"
require "digest"

class HasadImportJob < ApplicationJob
  queue_as :default
  BATCH_SIZE = 1_000

  def perform
    root = ENV["HASAD_ROOT"].presence || Rails.root.join("hasad").to_s
    all_ndjson = Dir.glob(File.join(root, "**", "*.ndjson")).sort
    puts "[HasadImport] Root=#{root} ndjson_files=#{all_ndjson.size}"
    return if all_ndjson.empty?

    authors_inserted  = 0
    articles_inserted = 0

    author_buffer  = []
    article_buffer = []

    now = Time.current
    permitted_author  = Author.column_names  - %w[id created_at updated_at]
    permitted_article = Article.column_names - %w[id created_at updated_at]

    # cache authors to reduce queries
    @author_cache = Author.pluck(:name, :id).to_h

    all_ndjson.each do |path|
      puts "[HasadImport] <= #{path}"
      File.foreach(path) do |line|
        line = line.strip
        next if line.empty?

        row = parse_json!(line, path)

        # Determine record type
        rec_type = row["type"].to_s.downcase
        rec_type = "article" if rec_type.blank? && row.key?("url")
        rec_type = "author"  if rec_type.blank? && row.key?("name") && !row.key?("url")

        case rec_type
        when "author", "authors"
          attrs = build_author_attrs(row, now).slice(*permitted_author)
          next if attrs["name"].blank?
          author_buffer << attrs
          if author_buffer.size >= BATCH_SIZE
            authors_inserted += upsert_authors!(author_buffer)
            author_buffer.clear
          end

        when "article", "articles"
          attrs = build_article_attrs(row, now).slice(*permitted_article)
          next if attrs["source_url"].blank? || attrs["author_id"].blank?
          article_buffer << attrs
          if article_buffer.size >= BATCH_SIZE
            articles_inserted += insert_articles!(article_buffer)
            article_buffer.clear
          end

        else
          # Unknown line type; ignore politely
        end
      end
    end

    authors_inserted  += upsert_authors!(author_buffer)  if author_buffer.any?
    articles_inserted += insert_articles!(article_buffer) if article_buffer.any?

    ActiveRecord::Base.connection.execute <<~SQL
      UPDATE authors
      SET articles_count = (
        SELECT COUNT(*)
        FROM articles
        WHERE articles.author_id = authors.id
      );#{' '}
    SQL

    puts "[HasadImport] DONE authors_inserted≈#{authors_inserted} articles_inserted≈#{articles_inserted}"
  end

  private

  def parse_json!(line, path)
    JSON.parse(line)
  rescue JSON::ParserError => e
    raise "[HasadImport] JSON error in #{path}: #{e.message}"
  end

  # ---------- Authors ----------
  def build_author_attrs(row, now)
    {
      "name"         => row["name"].to_s.strip,
      "bio"          => row["bio"],
      "avatar_url"   => row["avatar_url"],
      "social_links" => row["social_links"].is_a?(Hash) ? row["social_links"] : {},
      "created_at"   => now,
      "updated_at"   => now
    }
  end

  def upsert_authors!(rows)
    # Prefer index name if you added it; columns array also works if unique index exists on name.
    Author.upsert_all(rows, unique_by: %i[name])
    rows.size
  rescue => e
    Rails.logger.error "[HasadImport] upsert_authors failed: #{e.class} #{e.message}"
    0
  end

  # ---------- Articles ----------
  def build_article_attrs(row, now)
    url = row["url"].presence || row["source_url"].presence
    author_name = row["author"].to_s.strip
    author_id = ensure_author_id!(author_name) if author_name.present?

    publish_date = if row["published_at_ts"].present?
                     Time.at(row["published_at_ts"].to_i).utc.to_date
    elsif row["published_at"].present?
                     Time.zone.parse(row["published_at"]).to_date rescue nil
    end

    body_html = row["content_html"].presence || row["body"].presence
    content_hash = body_html.present? ? Digest::SHA256.hexdigest(body_html) : nil

    # Generate excerpt from body if missing
    excerpt = row["excerpt"].presence || generate_excerpt(body_html)

    tags_str = case row["tags"]
    when Array  then row["tags"].join(",")
    when String then row["tags"]
    end

    {
      "title"         => row["title"],
      "article_image" => row["article_image_url"].presence || row["article_image"].presence,
      "excerpt"       => excerpt,
      "category"      => row["categorie"].presence || row["category"],
      "publish_date"  => publish_date,
      "body"          => body_html,
      "source_url"    => url,
      "tags"          => tags_str,
      "author_id"     => author_id,
      "source_id"     => row["source_id"],
      "ingested_at"   => now,
      "content_hash"  => content_hash,
      "created_at"    => now,
      "updated_at"    => now
    }
  end

  def insert_articles!(rows)
    Article.insert_all(rows, unique_by: %i[source_url])
    rows.size
  rescue => e
    Rails.logger.error "[HasadImport] insert_articles failed: #{e.class} #{e.message}"
    0
  end

  # ---------- Shared ----------
  def ensure_author_id!(name)
    return nil if name.blank?
    return author_id = (author = Author.find_by(name: name))&.id if !author_missing_in_cache?(name)

    # Cache hit?
    return @author_cache[name] if @author_cache.key?(name)

    # Create or fetch, then cache
    author = Author.find_by(name: name) || Author.create!(name: name)
    (@author_cache[name] = author.id)
  end

  def author_missing_in_cache?(name)
    # If cache empty or name not in it, treat as missing
    !(@author_cache && author_id = @author_cache[name])
  end

  def generate_excerpt(html_content)
    return nil if html_content.blank?
    
    # Strip HTML tags and get plain text
    plain_text = html_content.gsub(/<[^>]*>/, ' ')
                             .gsub(/\s+/, ' ')
                             .strip
    
    # Take first 200 characters and truncate at word boundary
    if plain_text.length <= 200
      plain_text
    else
      truncated = plain_text[0...200]
      last_space = truncated.rindex(' ')
      last_space ? truncated[0...last_space] + '...' : truncated + '...'
    end
  end
end
