# lib/tasks/ingest.rake
# frozen_string_literal: true

require "json"
require "pathname"
require "uri"
require "rack/utils"
require "date"

namespace :ingest do
  desc 'Incremental import (no deletes). Usage: bin/rake "ingest:import[source,filename]" ' \
       "or SOURCE=metras FILENAME=/abs/path.ndjson bin/rake ingest:import"
  task :import, [ :source, :filename, :dry_run ] => :environment do |_, args|
    source   = args[:source]   || ENV["SOURCE"]   || abort("Missing source (e.g., metras)")
    filename = args[:filename] || ENV["FILENAME"] || "parsed.ndjson"
    dry_run  = ActiveModel::Type::Boolean.new.cast(args[:dry_run] || ENV["DRY_RUN"])

    # Accept absolute path, otherwise default to Rails.root/dumps/<source>/<filename>
    path = Pathname.new(filename)
    path = Rails.root.join("dumps", source, filename) unless path.absolute?
    abort("File not found: #{path}") unless File.exist?(path)

    # ---------- Load ----------
    rows = []
    File.foreach(path) do |line|
      next if line.strip.empty?
      rows << JSON.parse(line)
    end
    puts "Loaded #{rows.size} records from #{path}"

    # ---------- Helpers ----------
    def normalize_url(u)
      return nil if u.nil? || u.strip.empty?
      uri = URI(u.strip)
      return nil unless uri.scheme && uri.host
      # strip common tracking params; keep canonical-ish URL
      q = Rack::Utils.parse_nested_query(uri.query.to_s)
      q.reject! { |k, _| k =~ /\Autm_|^fbclid$|^gclid$|^igshid$/i }
      uri.query = q.empty? ? nil : URI.encode_www_form(q)
      uri.fragment = nil
      uri.to_s
    rescue
      nil
    end

    # ---------- Map NDJSON → internal fields ----------
    rows.each do |h|
      # URL: your file uses "url"
      h["source_url"] = normalize_url(h["source_url"] || h["url"])

      # Author: your file uses "author" (string)
      h["author_name"] ||= h["author"]

      # Body: prefer HTML, fallback to text
      h["body"] ||= (h["body_html"].presence || h["body_text"])

      # Publish date: derive from ISO8601 "published_at"
      if h["publish_date"].blank? && h["published_at"].present?
        begin
          h["publish_date"] = Date.iso8601(h["published_at"]).to_s
        rescue ArgumentError
          h["publish_date"] = nil
        end
      end

      # Categories array → primary category + tags CSV
      if h["categories"].is_a?(Array)
        h["category"] ||= h["categories"].first
        h["tags"]     ||= h["categories"].join(",")
      end
    end

    # Intra-batch dedupe by normalized source_url
    rows = rows.reverse.uniq { |h| h["source_url"] }.reverse

    # Filter and report
    skipped_nil = rows.count { |h| h["source_url"].blank? }
    rows.select! { |h| h["source_url"].present? }
    puts "Skipping #{skipped_nil} rows with nil/blank source_url after mapping"
    puts "Rows with source_url present: #{rows.size}"

    # ---------- Authors ----------
    author_names = rows.filter_map { |h| h["author_name"]&.strip }.uniq
    authors_map  = {}
    Author.transaction do
      author_names.each do |name|
        next if name.blank?
        authors_map[name] ||= Author.find_or_create_by!(name: name)
      end
    end

    # ---------- Build records ----------
    now = Time.current
    records = rows.map do |h|
      name   = h["author_name"]&.strip
      author = (name.present? ? authors_map[name] : nil) || Author.find_or_create_by!(name: (name.presence || "Unknown"))

      {
        title:         h["title"],
        article_image: h["article_image"],
        excerpt:       h["excerpt"],
        body:          h["body"],
        category:      h["category"],
        tags:          h["tags"],
        source_url:    h["source_url"],
        publish_date:  h["publish_date"], # "YYYY-MM-DD" string is fine for sqlite date
        author_id:     author.id,
        created_at:    now,
        updated_at:    now
      }
    end

    puts "Prepared #{records.size} article rows for upsert"

    if records.empty?
      puts "Nothing to ingest (records is empty)."
    else
      if dry_run
        puts "[DRY RUN] Skipping DB writes."
      else
        # Prefer bulk upsert using the existing unique index on source_url (partial or plain)
        conn = ActiveRecord::Base.connection
        idx  = conn.indexes(:articles).find { |i| i.unique && i.columns == [ "source_url" ] }

        if idx
          Article.upsert_all(records, unique_by: idx.name.to_sym, record_timestamps: false)
          puts "Upserted #{records.size} rows (new + updated)."
        else
          # Fallback: safe per-row upsert if no visible unique index (slower)
          puts "No unique index detected for source_url; falling back to per-row upsert (slower)."
          Article.transaction do
            records.each do |attrs|
              rec = Article.find_or_initialize_by(source_url: attrs[:source_url])
              rec.assign_attributes(attrs.except(:created_at, :updated_at))
              rec.save!(validate: false)
            end
          end
        end

        # Meilisearch: reindex affected docs (callbacks don’t fire on upsert_all)
        changed_urls = records.map { _1[:source_url] }.compact
        if changed_urls.any?
          Article.where(source_url: changed_urls).reindex!
          puts "Reindexed #{changed_urls.size} articles in Meilisearch."
        end
      end
    end

    puts "Ingest complete (incremental)."
  end
end
