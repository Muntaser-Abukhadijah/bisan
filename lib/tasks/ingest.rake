# frozen_string_literal: true

namespace :ingest do
  desc "Ingest a source from DATA_ROOT. Usage: rake ingest:source[metras]"
  task :source, [ :source, :filename ] => :environment do |_, args|
    source   = args[:source]   || ENV["SOURCE"] || abort("Missing source (e.g., metras)")
    filename = args[:filename] || ENV["FILENAME"] || "parsed.ndjson"

    report = Ingestion::Importer.new(source:).run(filename:)
    puts JSON.pretty_generate(report.to_h)

    # non-zero exit when there are JSON/normalization/upsert errors
    if report.totals[:errors].to_i > 0
      warn "Ingest finished with errors: #{report.totals[:errors]}"
      exit 1
    end
  end
end
