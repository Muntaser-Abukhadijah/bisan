# frozen_string_literal: true

namespace :ingest do
  desc "Refresh a source: purge existing records for the source, then ingest. Usage: rake ingest:refresh[metras]"
  task :refresh, [ :source, :filename ] => :environment do |_, args|
    source   = args[:source]   || ENV["SOURCE"]   || abort("Missing source (e.g., metras)")
    filename = args[:filename] || ENV["FILENAME"] || "parsed.ndjson"

    # Map your source key to a domain (extend as you add sources)
    domain = case source
    when "metras" then "metras.co"
    else
               abort("Unknown source '#{source}'. Add its domain mapping first.")
    end

    # Safety: show counts before deletion
    scope = Article.where("source_url LIKE ?", "%#{domain}%")
    puts "Preparing to delete #{scope.count} articles for #{domain}…"

    ActiveRecord::Base.transaction do
      scope.delete_all
      # Clean up authors that have no remaining articles
      Author.left_joins(:articles).where(articles: { id: nil }).delete_all
    end

    puts "Purged existing #{source} content. Starting ingest…"

    report = Ingestion::Importer.new(source:).run(filename:)
    puts JSON.pretty_generate(report.to_h)

    if report.totals[:errors].to_i > 0
      warn "Ingest finished with errors: #{report.totals[:errors]}"
      exit 1
    end

    puts "Ingest complete."
  end
end
